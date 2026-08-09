#!/usr/bin/env node
// Real transport test: spawns server.js as a SUBPROCESS and speaks JSON-RPC over
// pipes, exactly the way VoiceOS will. --selftest skips the transport, so it can't
// catch line-buffering or stdout-pollution bugs. This can.
//
//   node test-stdio.js            (expects a stub or real orchestrator on :4001)
//
// Deliberately nasty about framing: sends two messages glued into one write, and
// one message split across two writes, because that is what a real client does.

const { spawn } = require('node:child_process');
const { join } = require('node:path');

const PHRASE = process.env.PHRASE || 'clean up my inbox and schedule everything';
const child = spawn(process.execPath, [join(__dirname, 'server.js')], {
  stdio: ['pipe', 'pipe', 'pipe'],
});

const responses = [];
const waiters = new Map();
let buf = '';
let stderrOut = '';
let polluted = null;

child.stdout.setEncoding('utf8');
child.stdout.on('data', (chunk) => {
  buf += chunk;
  const lines = buf.split('\n');
  buf = lines.pop();
  for (const line of lines) {
    if (!line.trim()) continue;
    let msg;
    try {
      msg = JSON.parse(line);
    } catch {
      // Anything non-JSON on stdout means the server console.log'd somewhere.
      polluted = polluted || line;
      continue;
    }
    responses.push(msg);
    const w = waiters.get(msg.id);
    if (w) (waiters.delete(msg.id), w(msg));
  }
});
child.stderr.on('data', (d) => (stderrOut += d));

const waitFor = (id, ms = 12000) =>
  new Promise((resolve, reject) => {
    waiters.set(id, resolve);
    setTimeout(() => (waiters.has(id) ? reject(new Error(`timeout waiting for id ${id}`)) : 0), ms);
  });

const fail = (m) => {
  process.stderr.write(`\nFAIL: ${m}\n\n--- server stderr ---\n${stderrOut}\n`);
  child.kill();
  process.exit(1);
};

const frame = (o) => JSON.stringify(o) + '\n';

(async () => {
  // 1. initialize + the initialized notification, GLUED into a single write.
  //    A correct server answers the first and stays silent on the second.
  child.stdin.write(
    frame({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-06-18', clientInfo: { name: 'crew-stdio-test', version: '1' } } }) +
      frame({ jsonrpc: '2.0', method: 'notifications/initialized' })
  );
  const init = await waitFor(1);
  if (init.error) fail(`initialize errored: ${JSON.stringify(init.error)}`);
  if (!init.result?.protocolVersion) fail('initialize returned no protocolVersion');
  console.log(`  ok  initialize        -> ${init.result.serverInfo.name} v${init.result.serverInfo.version}, proto ${init.result.protocolVersion}`);

  // 2. tools/list, SPLIT across two writes mid-JSON.
  const t = frame({ jsonrpc: '2.0', id: 2, method: 'tools/list' });
  const cut = Math.floor(t.length / 2);
  child.stdin.write(t.slice(0, cut));
  await new Promise((r) => setTimeout(r, 60)); // force the server to hold a partial line
  child.stdin.write(t.slice(cut));
  const list = await waitFor(2);
  const names = (list.result?.tools || []).map((x) => x.name);
  if (!names.includes('run_crew_task')) fail(`run_crew_task not advertised (got: ${names.join(', ') || 'none'})`);
  console.log(`  ok  tools/list        -> [${names.join(', ')}]  (survived a split frame)`);

  // 3. the real thing
  child.stdin.write(frame({ jsonrpc: '2.0', id: 3, method: 'tools/call', params: { name: 'run_crew_task', arguments: { instructions: PHRASE } } }));
  const call = await waitFor(3);
  if (call.error) fail(`tools/call errored: ${JSON.stringify(call.error)}`);
  const out = call.result?.content?.[0]?.text || '';
  console.log(`  ${call.result.isError ? '!!' : 'ok'}  run_crew_task     -> ${JSON.stringify(out)}`);

  // 4. the loop: ask "what's the crew doing?" with NO taskId, repeatedly.
  //    Nobody says "task underscore one" out loud, so this is the only version of
  //    the question that will ever actually be asked. Each answer has to be a
  //    sentence VoiceOS can read straight out — no JSON, no newlines, no (state).
  //    Skipped when step 3 could not reach an orchestrator — there is no task to
  //    ask about, and that case is already reported as exit 2 at the bottom.
  let sawDone = false;
  let id = 100;
  for (let poll = 1; poll <= 8 && !sawDone && !call.result.isError; poll++) {
    child.stdin.write(frame({ jsonrpc: '2.0', id, method: 'tools/call', params: { name: 'crew_task_status', arguments: {} } }));
    const r = await waitFor(id++);
    if (r.error) fail(`crew_task_status errored: ${JSON.stringify(r.error)}`);
    const said = r.result?.content?.[0]?.text || '';
    if (r.result?.isError) fail(`crew_task_status returned an error: ${JSON.stringify(said)}`);
    if (!said.trim()) fail('crew_task_status said nothing at all');
    if (/[{}[\]"]|\n|\(\w+\)/.test(said)) fail(`not speakable — VoiceOS would read this aloud: ${JSON.stringify(said)}`);
    if (/hasn't been given anything to do/.test(said)) fail('the bridge forgot the taskId it just started');
    console.log(`  ok  status (no id) #${poll} -> ${JSON.stringify(said)}`);
    sawDone = /crew is finished/.test(said);
    if (!sawDone) await new Promise((r2) => setTimeout(r2, 150));
  }
  if (sawDone) console.log('  ok  loop closed       -> the human is told, out loud, that it finished');
  else if (call.result.isError) console.log('  --  status loop skipped (nothing on :4001)');
  else if (process.env.REQUIRE_DONE === '1') fail('never reported the run as finished after 8 asks');
  else console.log('  --  still running after 8 asks (real orchestrator — expected, it paces at LINE_MS)');

  // 4b. a bad call must come back as a readable tool error, not a crash
  child.stdin.write(frame({ jsonrpc: '2.0', id: 4, method: 'tools/call', params: { name: 'run_crew_task', arguments: {} } }));
  const bad = await waitFor(4);
  if (!bad.result?.isError) fail('missing-instructions call should have returned isError:true');
  console.log(`  ok  missing arg       -> handled: ${JSON.stringify(bad.result.content[0].text)}`);

  // 5. the server must still be alive after all that
  child.stdin.write(frame({ jsonrpc: '2.0', id: 5, method: 'ping' }));
  await waitFor(5);
  console.log('  ok  ping              -> still alive after a bad call');

  if (polluted) fail(`non-JSON on stdout would corrupt the MCP stream: ${JSON.stringify(polluted.slice(0, 120))}`);
  if (responses.some((r) => r.id === undefined)) fail('server replied to a notification (protocol violation)');
  console.log('  ok  stdout clean      -> no stray logging on the protocol channel');

  child.stdin.end();
  if (call.result.isError) {
    console.log(`\nTRANSPORT PASS, ORCHESTRATOR DOWN — protocol is fine, but nothing is listening on :4001.`);
    process.exit(2);
  }
  console.log(`\nPASS — spoken phrase would reach the orchestrator.`);
  console.log(`       phrase: ${JSON.stringify(PHRASE)}`);
  process.exit(0);
})().catch((e) => fail(e.message));

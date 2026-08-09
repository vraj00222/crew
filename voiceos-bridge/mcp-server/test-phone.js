#!/usr/bin/env node
// The phone loop, proved over real stdio with nothing outside this machine.
//
//   node test-phone.js
//
// Three things this catches, all of which are silent failures on stage:
//
//   1. The deterministic route (CREW_PHONE_FAKE=1) still answers. This is the
//      panic button for the third act — if it breaks, it breaks quietly, and
//      you find out at the moment you reach for it.
//   2. crew_ask_user ANNOUNCES itself to the orchestrator. The agent is blocked
//      inside one tool call for up to two minutes while the phone rings; those
//      two POSTs are the only reason the dock is not frozen through it. They
//      are fire-and-forget by design, so nothing else would ever notice.
//   3. A dead phone stack does NOT kill the agent. crew_ask_user with no voice
//      server must come back as a normal result telling the agent to decide for
//      itself — not as an error that throws away the rest of its work.
//
// No a1mobile key, no tunnel, no network, no Mac.

const { spawn } = require('node:child_process');
const http = require('node:http');
const { join } = require('node:path');

let failed = 0;
const ok = (m) => console.log(`  ok    ${m}`);
const bad = (m) => (console.log(`  FAIL  ${m}`), failed++);

// Stands in for the orchestrator's POST /agent-event and records what arrived.
function eventSink() {
  const got = [];
  const server = http.createServer((req, res) => {
    let raw = '';
    req.on('data', (d) => (raw += d));
    req.on('end', () => {
      try { got.push(JSON.parse(raw)); } catch { /* shape is asserted below */ }
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end('{"ok":true}');
    });
  });
  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', () => resolve({ got, server, port: server.address().port }));
  });
}

// One tool call over real MCP stdio framing, exactly as `claude -p` makes it.
function callTool(name, args, env) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [join(__dirname, 'server.js')], {
      stdio: ['pipe', 'pipe', 'ignore'],
      env: { ...process.env, ...env },
    });
    let buf = '';
    const timer = setTimeout(() => (child.kill(), reject(new Error(`${name} never answered`))), 20000);
    child.stdout.setEncoding('utf8');
    child.stdout.on('data', (c) => {
      buf += c;
      const lines = buf.split('\n');
      buf = lines.pop();
      for (const line of lines) {
        if (!line.trim()) continue;
        let msg;
        try { msg = JSON.parse(line); } catch { continue; }
        if (msg.id === 2) {
          clearTimeout(timer);
          child.kill();
          resolve(msg.result || {});
        }
      }
    });
    const frame = (o) => JSON.stringify(o) + '\n';
    child.stdin.write(frame({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-06-18', clientInfo: { name: 'phone-test', version: '1' } } }));
    child.stdin.write(frame({ jsonrpc: '2.0', id: 2, method: 'tools/call', params: { name, arguments: args } }));
  });
}

const said = (r) => (r.content || []).map((c) => c.text).join(' ');

(async () => {
  const sink = await eventSink();
  const baseEnv = {
    CREW_ROLE: 'scheduler',
    CREW_TASK_ID: 'task_test',
    CREW_ORCH_EVENTS: `http://127.0.0.1:${sink.port}/agent-event`,
    CREW_FAKE_ASK_MS: '150', // pacing, not latency — keep the test quick
  };

  // 1. the deterministic route answers, and answers the SAME way every time
  const q = 'Two meetings both want two PM tomorrow. Which one wins, David or Priya?';
  const r1 = await callTool('crew_ask_user', { question: q }, { ...baseEnv, CREW_PHONE_FAKE: '1' });
  if (r1.isError) bad(`fake ask returned an error: ${said(r1)}`);
  else ok('crew_ask_user answers with the phone simulated');

  if (r1.structuredContent?.answered && r1.structuredContent?.text) {
    ok(`it produced an answer: "${r1.structuredContent.text}"`);
  } else {
    bad('fake ask produced no answer — the third act has no fallback');
  }
  if (/David/i.test(r1.structuredContent?.text || '')) ok('the rehearsed question gets its rehearsed answer');
  else bad('the rehearsed "which meeting wins" question did not match its canned answer');

  const r1b = await callTool('crew_ask_user', { question: q }, { ...baseEnv, CREW_PHONE_FAKE: '1' });
  if (r1b.structuredContent?.text === r1.structuredContent?.text) ok('deterministic — the same question gives the same answer twice');
  else bad('the fallback route is not deterministic; it cannot be rehearsed');

  // 2. the dock hears about it, both before and after
  const mine = sink.got.filter((e) => e.taskId === 'task_test');
  const calling = mine.find((e) => e.kind === 'calling');
  const answered = mine.find((e) => e.kind === 'answered');
  if (calling) ok('announced "calling" BEFORE the wait — the dock is not frozen through it');
  else bad('no "calling" event — the dock would sit silent while the phone rang');
  if (calling && calling.message.includes('David or Priya')) ok('the announcement carries the question, so the room hears what was asked');
  else if (calling) bad('the "calling" announcement does not include the question');
  if (answered?.text) ok('announced the answer, with the raw text for the rest of the crew');
  else bad('no "answered" event — later agents would never learn what was decided');
  if (calling?.role === 'scheduler') ok('attributed to the character that actually asked');
  else bad(`wrong role on the event: ${calling?.role}`);

  // 3. a dead phone stack degrades instead of killing the agent
  const r2 = await callTool(
    'crew_ask_user',
    { question: 'anything else?' },
    { ...baseEnv, CREW_PHONE_FAKE: '0', CREW_VOICE_PORT: '4999' } // nothing listens there
  );
  if (r2.isError) bad('a dead voice server made crew_ask_user an ERROR — the agent loses its work');
  else ok('a dead voice server is a normal result, not an error');
  if (r2.structuredContent?.unreachable) ok('and it says the line was down rather than claiming you ignored it');
  else bad('the unreachable case is not distinguished from a genuine no-answer');

  // 4. the fake route must never claim a real send
  const r3 = await callTool('crew_send_sms', { body: 'inbox cleared' }, { ...baseEnv, CREW_PHONE_FAKE: '1' });
  if (/simulated/i.test(said(r3))) ok('a simulated text tells the agent it was simulated');
  else bad(`a simulated text claimed to be real: "${said(r3)}"`);

  sink.server.close();
  console.log(
    failed
      ? `\n  ${failed} failed — the phone loop has a hole in it.\n`
      : '\n  PASS — the crew can ask, be heard, and survive the phone being dead.\n'
  );
  process.exit(failed ? 1 : 0);
})().catch((e) => {
  console.log(`  FAIL  ${e.message}`);
  process.exit(1);
});

#!/usr/bin/env node
// The demo, as a CONVERSATION — the thing the audience is actually being sold.
//
//   node demo-conversation.js            against whatever is on :4001
//   SPEAK=1 node demo-conversation.js    read the crew's replies out loud (macOS)
//
// Every other way we run this project shows the machinery: narration lines, dock
// logs, PASS. None of them show the *product*, which is a person talking to a
// crew and being answered. This drives the real MCP server over real stdio pipes
// — exactly the calls VoiceOS makes — and prints the result as a dialogue.
//
// It is the demo minus the microphone. When the Pro trial lands, VoiceOS replaces
// the left-hand column and nothing else changes; until then this is the closest
// honest picture of the voice loop, and it runs on any machine with no account,
// no Mac and no network.
//
// It is also the screen recording: this is what a video demo shows, because the
// dock is the show but the conversation is the pitch.

const { spawn } = require('node:child_process');
const { join } = require('node:path');

const ORCH = (process.env.ORCH_URL || 'http://localhost:4001').replace(/\/+$/, '');
const SPEAK = process.env.SPEAK === '1' && process.platform === 'darwin';
const OPENING = process.env.PHRASE || 'Clean up my inbox and schedule everything';

// Narrow enough to be honest about what it is: colour if we have a TTY, plain
// text if this is being piped into a file or a slide.
const tty = process.stdout.isTTY;
const dim = (s) => (tty ? `\x1b[2m${s}\x1b[0m` : s);
const bold = (s) => (tty ? `\x1b[1m${s}\x1b[0m` : s);
const cyan = (s) => (tty ? `\x1b[36m${s}\x1b[0m` : s);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// --- the MCP client half: this is what VoiceOS is, minus the microphone -------
function client() {
  const child = spawn(process.execPath, [join(__dirname, 'server.js')], { stdio: ['pipe', 'pipe', 'ignore'] });
  const waiters = new Map();
  let buf = '';
  let id = 0;

  child.stdout.setEncoding('utf8');
  child.stdout.on('data', (chunk) => {
    buf += chunk;
    const lines = buf.split('\n');
    buf = lines.pop();
    for (const line of lines) {
      if (!line.trim()) continue;
      let msg;
      try { msg = JSON.parse(line); } catch { continue; }
      const w = waiters.get(msg.id);
      if (w) (waiters.delete(msg.id), w(msg));
    }
  });

  const send = (method, params) =>
    new Promise((resolve, reject) => {
      const n = ++id;
      waiters.set(n, resolve);
      setTimeout(() => (waiters.has(n) ? (waiters.delete(n), reject(new Error(`timeout on ${method}`))) : 0), 20000);
      child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id: n, method, params }) + '\n');
    });

  return {
    child,
    init: () => send('initialize', { protocolVersion: '2025-06-18', clientInfo: { name: 'crew-demo', version: '1' } }),
    call: async (name, args) => {
      const r = await send('tools/call', { name, arguments: args || {} });
      return { text: r.result?.content?.[0]?.text || '(no reply)', isError: Boolean(r.result?.isError) };
    },
    stop: () => child.kill(),
  };
}

// --- the dialogue ------------------------------------------------------------
let spoken = 0;
const you = async (line) => {
  spoken++;
  console.log(`\n  ${dim('you  >')}  ${bold(`"${line}"`)}`);
  await sleep(400);
};

async function crew(reply) {
  console.log(`  ${cyan('crew >')}  ${reply.text}`);
  if (SPEAK) {
    const { spawnSync } = require('node:child_process');
    spawnSync('say', ['-v', 'Karen', '-r', '200', reply.text.replace(/"/g, '')], { stdio: 'ignore' });
  }
  await sleep(SPEAK ? 200 : 900);
}

async function main() {
  // Fail with a sentence, not a stack trace — this is the thing being projected.
  try {
    const res = await fetch(`${ORCH}/status/none`, { signal: AbortSignal.timeout(2500) });
    if (res.status !== 404 && !res.ok) throw new Error(`HTTP ${res.status}`);
  } catch {
    console.error(
      `\n  Nothing is listening on ${ORCH}.\n` +
      `  Start one first — either is fine:\n\n` +
      `    FAKE=1 node orchestrator/server.js                      (canned agents)\n` +
      `    node voiceos-bridge/mcp-server/stub-orchestrator.js     (scripted run)\n`
    );
    process.exit(2);
  }

  const mcp = client();
  await mcp.init();

  console.log(dim(`\n  --- CrewOS, the conversation. MCP server on stdio -> orchestrator ${ORCH} ---`));
  console.log(dim(`      (this is exactly what VoiceOS calls; the only thing missing is the mic)`));

  await you(OPENING);
  await crew(await mcp.call('run_crew_task', { instructions: OPENING }));

  // Ask the way a person would: no taskId, because nobody says "task underscore
  // one" out loud. The bridge remembers what it started.
  const followUps = ["What's the crew doing?", 'How is it going?', 'Are they done yet?'];
  let turn = 0;
  let finished = false;

  // Keep the conversation alive until the crew says it is over. A real person
  // asks again when the answer is "still going" — that IS the demo.
  for (let i = 0; i < 12 && !finished; i++) {
    await sleep(2500);
    await you(followUps[Math.min(turn++, followUps.length - 1)]);
    const reply = await mcp.call('crew_task_status', {});
    await crew(reply);
    finished = /crew is finished/i.test(reply.text);
  }

  mcp.stop();
  console.log(
    finished
      ? dim(`\n  --- the human spoke ${spoken} times, all of them questions. Nobody touched a keyboard in between. ---\n`)
      : dim('\n  --- still running. Not a failure: the orchestrator paces at LINE_MS. ---\n')
  );
  process.exit(finished ? 0 : 1);
}

main().catch((e) => {
  console.error(`\n  ${e.message}\n`);
  process.exit(1);
});

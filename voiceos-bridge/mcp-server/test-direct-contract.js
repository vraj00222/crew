#!/usr/bin/env node
// The A<->B seam in `direct` mode: every tool A's prompt tells an agent to call
// must actually exist on B's server, spelled exactly the same way.
//
//   node test-direct-contract.js
//
// A checked this by hand once and the six matched. Nothing enforced it, so a
// rename on either side would next surface as a character narrating a number it
// never measured — execution-direct.md says "narrate what is true and carry on",
// so a missing tool produces a flawless-looking run that touched nothing.
//
// No orchestrator, no Mac, no login, no network: it reads A's prompt file and
// asks B's server for its real tools/list over real stdio pipes.

const { spawn } = require('node:child_process');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { TOOLS, allowedTools, json } = require('./mcp-config.js');

const PROMPT = join(__dirname, '..', '..', 'orchestrator', 'prompts', 'execution-direct.md');
let failed = 0;
const ok = (m) => console.log(`  ok    ${m}`);
const bad = (m) => (console.log(`  FAIL  ${m}`), failed++);

// Tool names as the prompt actually writes them: `crew_gmail_archive(query | ids)`.
function toolsNamedInPrompt() {
  const text = readFileSync(PROMPT, 'utf8');
  const found = new Set();
  for (const m of text.matchAll(/\bcrew_[a-z_]+\s*\(/g)) found.add(m[0].replace(/\s*\($/, ''));
  return [...found];
}

function serverTools() {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [join(__dirname, 'server.js')], { stdio: ['pipe', 'pipe', 'ignore'] });
    let buf = '';
    const timer = setTimeout(() => (child.kill(), reject(new Error('server never answered tools/list'))), 10000);
    child.stdout.setEncoding('utf8');
    child.stdout.on('data', (c) => {
      buf += c;
      const lines = buf.split('\n');
      buf = lines.pop();
      for (const line of lines) {
        if (!line.trim()) continue;
        const msg = JSON.parse(line);
        if (msg.id === 2) {
          clearTimeout(timer);
          child.kill();
          resolve((msg.result?.tools || []).map((t) => t.name));
        }
      }
    });
    const frame = (o) => JSON.stringify(o) + '\n';
    child.stdin.write(frame({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-06-18', clientInfo: { name: 'direct-contract', version: '1' } } }));
    child.stdin.write(frame({ jsonrpc: '2.0', id: 2, method: 'tools/list' }));
  });
}

(async () => {
  const named = toolsNamedInPrompt();
  const served = await serverTools();

  if (!named.length) bad(`no crew_* tool names found in ${PROMPT} — did the prompt change shape?`);
  else ok(`execution-direct.md names ${named.length} tools`);

  for (const t of named) {
    if (served.includes(t)) ok(`prompt calls ${t} — the server has it`);
    else bad(`prompt calls ${t} — THE SERVER DOES NOT HAVE IT (agents would narrate without acting)`);
  }

  // The other direction: a tool the agents are never told about is dead weight
  // in the allowlist, not a failure. Worth saying out loud rather than hiding.
  for (const t of TOOLS) {
    if (!named.includes(t)) console.log(`  --    ${t} is served and allow-listed but no prompt calls it`);
  }

  // mcp-config.js is what makes any of the above reachable; if its own list has
  // drifted from what the server serves, the allowlist would silently deny a call.
  for (const t of TOOLS) {
    if (!served.includes(t)) bad(`mcp-config.js allow-lists ${t}, which the server does not serve`);
  }

  console.log(`\n  the two values A's orchestrator needs to pass to \`claude -p\`:\n`);
  console.log(`  --mcp-config    ${json()}`);
  console.log(`  --allowedTools  ${allowedTools()}\n`);

  console.log(
    failed
      ? `${failed} failed — direct mode would narrate without touching the mailbox.\n`
      : `PASS — every tool the direct prompt names is really served, spelled the same.\n`
  );
  process.exit(failed ? 1 : 0);
})().catch((e) => {
  console.log(`  FAIL  ${e.message}`);
  process.exit(1);
});

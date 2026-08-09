#!/usr/bin/env node
// Crew orchestrator — Node stdlib only, no deps, no build step.
//   POST /start-task  {instructions}  -> {taskId, status:"started"}
//   GET  /status/:id                  -> {taskId, status, agents:[{name,state,lastMessage}]}
// Run fake (no claude spawn, canned narration):  FAKE=1 node server.js

const http = require('node:http');
const { spawn } = require('node:child_process');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');

const PORT = 4001;
const DOCK = process.env.DOCK_URL || 'http://localhost:4002/agent-status';
const FAKE = process.env.FAKE === '1';
const TIMEOUT_MS = Number(process.env.AGENT_TIMEOUT_MS || 180_000);
// Pacing has to be >= how long a line takes to SAY, or the dock's queue grows
// every line and it starts dropping them. We both estimated ~2s; timed on the
// demo Mac at rate 200 the real spread is 2.8-4.3s, average ~3.8s. That gap is
// the whole reason lines went missing, at 1400 and again at 2200.
// 4000 is the measurement, not a guess. Re-measure if CREW_RATE changes.
const LINE_MS = Number(process.env.LINE_MS || 4000); // pacing between narration lines
// 3 content lines + the "Done:" sign-off, per agent. Bounded on purpose: two
// agents run in parallel but there is only one voice channel, so the show's
// length is (total lines x LINE_MS) and nothing else. 3+3+2 = 8 lines, ~35s.
const MAX_LINES = Number(process.env.MAX_LINES || 3); // per agent, "Done:" always passes
const ALLOWED_TOOLS = process.env.ALLOWED_TOOLS || ''; // e.g. "mcp__voiceos__speak"
// How the agents actually act: narrate (no tools) | direct (crew_* tools) | voice
// (speak to VoiceOS). One prompt file each, all three known-good — switching is
// an env var, not editing a prompt at 5:55pm with the room watching.
const MODE = process.env.CREW_MODE || 'narrate';

const tasks = new Map();
let seq = 0;

// --- routing: hardcoded keywords, not a planner. We know tomorrow's phrase. ---
function rolesFor(instructions) {
  const s = instructions.toLowerCase();
  const roles = [];
  if (/inbox|email|mail/.test(s)) roles.push('triage');
  if (/schedul|calendar|meeting|book/.test(s)) roles.push('scheduler');
  return roles.length ? roles : ['triage', 'scheduler']; // never spawn nothing on stage
}

// --- state + dock push, always together so they can't drift ---
// Fire-and-forget fetches race: integration testing caught "waking up" landing
// AFTER a later line, which on stage looks like a character going backwards.
// One chain keeps the dock's view in the order things actually happened.
// ponytail: single global chain, fine at ~20 posts/run; per-role chains if it grows.
let dockChain = Promise.resolve();

function say(task, role, state, message) {
  const agent = task.agents[role];
  agent.state = state;
  if (message) agent.lastMessage = message;
  console.log(`[${task.taskId}] ${role} (${state}): ${agent.lastMessage}`);
  const body = JSON.stringify({ character: role, message: agent.lastMessage, state });
  dockChain = dockChain.then(() =>
    fetch(DOCK, { method: 'POST', headers: { 'content-type': 'application/json' }, body })
      .catch(() => {}) // dock may not be up — never block the demo on it
  );
}

// The model usually emits all its narration in ONE event. Split to lines so the
// character speaks them one at a time instead of jumping straight to "Done:".
const toLines = (s) =>
  s.trim().split('\n')
    .map((l) => l.trim().replace(/^[-*>]\s*/, '').replace(/^#+\s*/, ''))
    .filter((l) => l && !l.startsWith('```'))
    .map((l) => (l.length <= 110 ? l : l.slice(0, 110).replace(/\s+\S*$/, '') + '…'));

// Ignore the `result` event — it repeats the final assistant text verbatim.
function narrate(evt) {
  if (evt.type !== 'assistant') return [];
  const out = [];
  for (const b of evt.message?.content || []) {
    if (b.type === 'text' && b.text.trim()) out.push(...toLines(b.text));
    // Tool calls used to narrate as "using crew_gmail_archive". Harmless while
    // the only mode was dry-run and nothing called a tool — but the dock speaks
    // these lines now, so the first live tool call would have had Moira read a
    // function name to the room. The character already says a real line before
    // every step; the tool name adds nothing an audience wants.
  }
  return out;
}

// Read prompts fresh every run — edit them without restarting the server.
function buildPrompt(role, instructions) {
  const execution = readFileSync(join(__dirname, 'prompts', `execution-${MODE}.md`), 'utf8').trim();
  return readFileSync(join(__dirname, 'prompts', `${role}.md`), 'utf8')
    .replace('{{EXECUTION}}', execution)
    .replace('{{INSTRUCTIONS}}', instructions);
}

function runRole(task, role) {
  return new Promise((resolve) => {
    // Narration is paced by us, not by token arrival — steady rhythm on stage.
    const queue = [];
    let spoken = 0, closed = false, draining = false, signedOff = false;

    const drain = () => {
      draining = true;
      const line = queue.shift();
      if (line) { say(task, role, 'working', line); return setTimeout(drain, LINE_MS); }
      draining = false;
      if (closed) { say(task, role, 'done', task.agents[role].lastMessage); resolve(); }
    };
    // "Done:" is the character's last word on stage. Agents that keep talking
    // after it (meta-commentary, caveats) get cut off — that bit us in testing.
    const push = (lines) => {
      if (signedOff) return;
      for (const l of lines) {
        const final = l.startsWith('Done:');
        if (spoken >= MAX_LINES && !final) continue; // chatty agent guard
        queue.push(l);
        spoken++;
        if (final) { signedOff = true; break; }
      }
      if (!draining) drain();
    };
    const finish = () => { closed = true; if (!draining) drain(); };

    say(task, role, 'working', 'waking up');
    if (FAKE) { push(CANNED[role]); return finish(); }

    const args = ['-p', buildPrompt(role, task.instructions), '--output-format', 'stream-json', '--verbose'];
    if (ALLOWED_TOOLS) args.push('--allowedTools', ALLOWED_TOOLS);
    const child = spawn('claude', args, { cwd: __dirname, stdio: ['ignore', 'pipe', 'pipe'] });

    const killer = setTimeout(() => {
      child.kill('SIGKILL');
      push(['Done: ran out of time.']);
    }, TIMEOUT_MS);

    let buf = '';
    child.stdout.on('data', (chunk) => {
      buf += chunk;
      const lines = buf.split('\n');
      buf = lines.pop();
      for (const line of lines) {
        if (!line.trim()) continue;
        let evt;
        try { evt = JSON.parse(line); } catch { continue; }
        push(narrate(evt));
      }
    });
    child.stderr.on('data', (d) => process.stderr.write(`[${role}] ${d}`));
    child.on('error', (e) => push([`Done: could not start (${e.message}).`]));
    child.on('close', () => { clearTimeout(killer); finish(); });
  });
}

const CANNED = {
  triage: ['Scanning the inbox.', 'Archiving six newsletters.', 'Flagging two emails that need replies.', 'Done: inbox down to two real emails.'],
  scheduler: ['Reading the flagged emails.', 'Finding open slots tomorrow.', 'Booking two PM with David Chen.', 'Done: two meetings on the calendar.'],
  recap: ['Pulling together what the crew did.', 'Done: inbox cleared, two meetings booked.'],
};

async function runTask(task) {
  await Promise.all(task.roles.map((r) => runRole(task, r)));
  await runRole(task, 'recap');
  task.status = 'done';
}

function startTask(instructions) {
  const taskId = `task_${++seq}`;
  const roles = rolesFor(instructions);
  const order = [...roles, 'recap'];
  const task = {
    taskId, instructions, status: 'running', roles, order,
    agents: Object.fromEntries(order.map((n) => [n, { name: n, state: 'idle', lastMessage: '' }])),
  };
  tasks.set(taskId, task);
  runTask(task).catch((e) => { console.error(e); task.status = 'done'; });
  return task;
}

// --- HTTP ---
const send = (res, code, obj) => {
  res.writeHead(code, { 'content-type': 'application/json' });
  res.end(JSON.stringify(obj));
};

http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');

  if (req.method === 'POST' && url.pathname === '/start-task') {
    let body = '';
    req.on('data', (d) => (body += d));
    req.on('end', () => {
      let instructions;
      try { instructions = JSON.parse(body).instructions; } catch {}
      if (typeof instructions !== 'string' || !instructions.trim()) {
        return send(res, 400, { error: 'instructions (string) required' });
      }
      const task = startTask(instructions);
      send(res, 200, { taskId: task.taskId, status: 'started' });
    });
    return;
  }

  const match = url.pathname.match(/^\/status\/(.+)$/);
  if (req.method === 'GET' && match) {
    const task = tasks.get(match[1]);
    if (!task) return send(res, 404, { error: 'unknown taskId' });
    return send(res, 200, {
      taskId: task.taskId,
      status: task.status,
      agents: task.order.map((n) => task.agents[n]),
    });
  }

  send(res, 404, { error: 'not found' });
}).listen(PORT, () => console.log(`orchestrator on :${PORT}${FAKE ? ' [FAKE]' : ''} -> dock ${DOCK}`));

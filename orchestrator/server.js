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

// `direct` mode's prompt tells each agent to call crew_gmail_archive(...), but a
// headless `claude -p` has no MCP server unless it is handed one — and B caught
// that we never handed it one. The failure was invisible rather than loud: the
// prompt says "narrate what is true and carry on, never announce a failure", so
// an agent with no tools narrates the prompt's own table, which is correct for
// the seeded mailbox. Rung 3 looked exactly like rung 2 while claiming the
// mailbox had really changed. Generated, not committed: the server path inside
// the config resolves against the spawning process's cwd, so a checked-in
// relative path is right from exactly one directory.
const BRIDGE = join(__dirname, '..', 'voiceos-bridge', 'mcp-server');
const MCP_CONFIG = JSON.stringify({
  mcpServers: { crew: { command: process.execPath, args: [join(BRIDGE, 'server.js')] } },
});
const CREW_TOOLS = [
  'crew_gmail_list_inbox', 'crew_gmail_archive', 'crew_gmail_label',
  'crew_calendar_find_slot', 'crew_calendar_book', 'crew_calendar_list',
].map((t) => `mcp__crew__${t}`).join(',');
// How the agents actually act: narrate (no tools) | direct (crew_* tools) | voice
// (speak to VoiceOS). One prompt file each, all three known-good — switching is
// an env var, not editing a prompt at 5:55pm with the room watching.
const MODE = process.env.CREW_MODE || 'narrate';

const tasks = new Map();
let seq = 0;

// --- the crew ---
// `activity` is what the character is *doing*, as opposed to who it is. The dock
// keys look and motion off it, so two agents doing research move alike without
// the dock needing to know either of their names. Adding a member here is one
// row plus a prompt file — no dock change needed for it to be heard, and none
// for it to be seen once the dock has a slot for the name.
const CREW = {
  // Transcripts are messier than typed text — a speech-to-text pass writes "in
  // box" as two words, and that alone dropped TRIAGE from the demo's own phrase.
  // Match how a transcriber spells things, not how a person types them.
  triage:     { activity: 'sorting',  match: /in[\s-]?box|e[\s-]?mail|mail/ },
  scheduler:  { activity: 'booking',  match: /schedul|calendar|meeting|book/ },
  researcher: { activity: 'research', match: /research|look up|find out|investigate|dig into/ },
  // `needs` is the feedback loop: the analyst waits for the researcher and is
  // handed what it actually found, instead of re-deriving it in parallel.
  analyst:    { activity: 'analysis', match: /analy|compare|report|numbers|breakdown/, needs: ['researcher'] },
  recap:      { activity: 'summary',  match: null }, // always last, never matched
};
const CLOSER = 'recap';

// Hardcoded keywords, not a planner. We know the demo's phrase, and a planner
// is a thing that can be wrong on stage.
function rolesFor(instructions) {
  const s = instructions.toLowerCase();
  const roles = Object.keys(CREW).filter((r) => CREW[r].match?.test(s));
  // Never spawn nothing on stage: a garbled transcript still puts the two
  // agents the demo is about on screen.
  return roles.length ? roles : ['triage', 'scheduler'];
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
  // `activity` is additive to the frozen contract — the dock ignored unknown
  // keys before this and still does, so nothing had to change to keep working.
  const body = JSON.stringify({
    character: role,
    message: agent.lastMessage,
    state,
    activity: CREW[role]?.activity ?? 'working',
  });
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
// Counted per run so a mode that is supposed to touch things can be shown to
// have touched them. Without this, "the agents used the tools" is exactly the
// kind of claim that reads true from a log while being false — the failure B
// caught, where a toolless agent narrates the prompt's own numbers and rung 3
// is indistinguishable from rung 2.
let toolCalls = 0;

function narrate(evt, role) {
  if (evt.type !== 'assistant') return [];
  const out = [];
  for (const b of evt.message?.content || []) {
    if (b.type === 'text' && b.text.trim()) out.push(...toLines(b.text));
    // Logged, never narrated. The dock speaks these lines, so a tool name here
    // would have had a character read a function name to the room.
    else if (b.type === 'tool_use') {
      toolCalls++;
      console.log(`[tool] ${role} -> ${b.name}`);
    }
  }
  return out;
}

// Read prompts fresh every run — edit them without restarting the server.
function buildPrompt(role, instructions, task) {
  const execution = readFileSync(join(__dirname, 'prompts', `execution-${MODE}.md`), 'utf8').trim();
  // The closer used to have the old three-agent crew written into its prompt,
  // so once the roster became dynamic it cheerfully reported an inbox nobody
  // had touched. It gets told who actually ran, and what each of them said.
  // Only agents that have actually finished — an agent still mid-run has a
  // half-finished line, and handing that on reads as the crew quoting a
  // sentence nobody has said yet.
  const crew = task.roles
    .filter((r) => r !== role && task.agents[r].state === 'done' && task.agents[r].lastMessage)
    .map((r) => `- ${r.toUpperCase()} (${CREW[r]?.activity}) said: "${task.agents[r].lastMessage}"`)
    .join('\n') || '(nobody has reported yet — you are first)';
  return readFileSync(join(__dirname, 'prompts', `${role}.md`), 'utf8')
    .replace('{{EXECUTION}}', execution)
    .replace('{{CREW}}', crew)
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

    const args = ['-p', buildPrompt(role, task.instructions, task), '--output-format', 'stream-json', '--verbose'];
    // Only direct mode calls tools. narrate must stay toolless — it is the safe
    // rung precisely because the agents cannot touch anything — and voice drives
    // VoiceOS by speaking, so it needs Bash rather than the crew tools.
    if (MODE === 'direct') args.push('--mcp-config', MCP_CONFIG, '--allowedTools', ALLOWED_TOOLS || CREW_TOOLS);
    else if (MODE === 'voice') args.push('--allowedTools', ALLOWED_TOOLS || 'Bash');
    else if (ALLOWED_TOOLS) args.push('--allowedTools', ALLOWED_TOOLS);
    // `detached` makes the agent its own process-group leader so the timeout can
    // kill the whole tree. An agent spawns tool subprocesses, and SIGKILLing only
    // the parent leaves orphans holding its stdout — see the killer below.
    const child = spawn('claude', args,
      { cwd: __dirname, stdio: ['ignore', 'pipe', 'pipe'], detached: true });

    const killer = setTimeout(() => {
      // Kill the GROUP, not the child. E reproduced the alternative: SIGKILL the
      // agent alone, its orphaned tool subprocess keeps the stdout pipe open,
      // 'close' never fires, and the task never reaches done — so recap never
      // appears. On stage that reads as a slow run rather than a dead one, which
      // is the worst version: nobody reaches for the panic button.
      try { process.kill(-child.pid, 'SIGKILL'); } catch { child.kill('SIGKILL'); }
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
        push(narrate(evt, role));
      }
    });
    child.stderr.on('data', (d) => process.stderr.write(`[${role}] ${d}`));
    child.on('error', (e) => push([`Done: could not start (${e.message}).`]));

    // Belt and braces, because the group kill is a fix for the cause and this is
    // a fix for the consequence. 'close' waits for every inherited stdio pipe;
    // 'exit' only for the process itself. Normal runs finish on 'close' with all
    // output drained; if a pipe is still held by something we could not kill,
    // 'exit' finishes anyway after a short grace so the run cannot wedge. Either
    // way the recap gets to happen, which is what the audience actually sees.
    let over = false;
    const done = () => { if (over) return; over = true; clearTimeout(killer); finish(); };
    child.on('close', done);
    child.on('exit', () => setTimeout(done, 1500));
  });
}

const CANNED = {
  triage: ['Scanning the inbox.', 'Archiving six newsletters.', 'Flagging two emails that need replies.', 'Done: inbox down to two real emails.'],
  scheduler: ['Reading the flagged emails.', 'Finding open slots tomorrow.', 'Booking two PM with David Chen.', 'Done: two meetings on the calendar.'],
  researcher: ['Reading what the thread actually says.', 'Checking the rollout notes against it.', 'Done: three facts worth knowing, one of them awkward.'],
  analyst: ['Lining the numbers up side by side.', 'One of these is not like the others.', 'Done: the Thursday figure is the one to ask about.'],
  recap: ['Pulling together what the crew did.', 'Done: inbox cleared, two meetings booked.'],
};

// Agents that depend on another agent's findings wait for them, and are handed
// what that agent actually said. Everything else still runs in parallel, so the
// rehearsed run is untouched: triage and scheduler need nothing and start
// together exactly as before.
//
// This is the difference between three agents working near each other and a
// crew: the analyst does not re-derive what the researcher already found, it
// reads it and argues with it.
async function runTask(task) {
  const done = new Set();
  let waves = 0;
  let pending = task.roles.filter((r) => r !== CLOSER);

  while (pending.length) {
    const ready = pending.filter((r) => (CREW[r].needs || []).every((n) => done.has(n) || !task.roles.includes(n)));
    // A cycle, or a need on a role that is not in this crew, would otherwise
    // hang forever. Run everything left rather than stall the show.
    const wave = ready.length ? ready : pending;
    if (!ready.length) console.log(`[crew] unmet dependency in [${pending}] — running anyway`);
    if (++waves > 1) console.log(`[crew] wave ${waves}: ${wave.join(', ')} (has ${[...done].join(', ')})`);
    await Promise.all(wave.map((r) => runRole(task, r)));
    wave.forEach((r) => done.add(r));
    pending = pending.filter((r) => !done.has(r));
  }

  await runRole(task, CLOSER); // always speaks alone, and always last
  task.status = 'done';
  // The whole point of direct mode is that the mailbox really changed. If no
  // agent called a tool, it did not — say so here rather than letting the run
  // look identical to a narrated one.
  if (MODE === 'direct' && !FAKE) {
    console.log(toolCalls
      ? `[tool] ${toolCalls} tool calls this run — the mailbox really changed.`
      : '[tool] NO TOOL CALLS — direct mode narrated only. The mailbox is untouched.');
  }
}

function startTask(instructions) {
  const taskId = `task_${++seq}`;
  const roles = rolesFor(instructions);
  const order = [...roles, CLOSER];
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
})
  // Without this a second orchestrator dies quietly and every client keeps
  // talking to the FIRST one — which may be running different prompts, a
  // different mode, or different pacing. test.sh spent a run reporting on a
  // stale server it had not started. Fail loudly instead.
  .on('error', (e) => {
    console.error(e.code === 'EADDRINUSE'
      ? `orchestrator: :${PORT} is already in use — another one is running.\n`
      + '  ./run-demo.sh stop   (then start this again)'
      : `orchestrator: ${e.message}`);
    process.exit(1);
  })
  .listen(PORT, () => console.log(`orchestrator on :${PORT}${FAKE ? ' [FAKE]' : ''} mode=${MODE} -> dock ${DOCK}`));

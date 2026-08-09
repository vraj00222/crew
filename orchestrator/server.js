#!/usr/bin/env node
// Crew orchestrator — Node stdlib only, no deps, no build step.
//   POST /start-task  {instructions}  -> {taskId, status:"started"}
//   GET  /status/:id                  -> {taskId, status, agents:[{name,state,lastMessage}]}
// Run fake (no claude spawn, canned narration):  FAKE=1 node server.js

const http = require('node:http');
const { spawn } = require('node:child_process');
const { readFileSync, existsSync } = require('node:fs');
const { join, delimiter } = require('node:path');

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

// `spawn('claude')` cannot start the CLI on Windows, and it fails per-agent as
// "Done: could not start (spawn claude ENOENT)" — a whole show of characters
// apologising. npm installs three shims: an extensionless shell script (Node
// spawns it as ENOENT), a `.cmd` (EINVAL — Node has refused to spawn `.cmd`
// without a shell since the CVE-2024-27980 fix), and the real `claude.exe` the
// `.cmd` points at. The `.exe` spawns cleanly with no shell, which also keeps
// the prompt out of any quoting rules — it is passed as argv either way.
//
// Worth knowing why nobody caught this: `checkpoint.sh` proves the CLI works by
// running it from the shell, where the shim resolves fine. That is a different
// thing from what `server.js` does, so the check passed green on a box where
// real agents could never start.
const CLAUDE = (() => {
  if (process.env.CLAUDE_BIN) return process.env.CLAUDE_BIN;
  if (process.platform !== 'win32') return 'claude';
  for (const dir of (process.env.PATH || '').split(delimiter)) {
    if (!dir) continue;
    for (const p of [
      join(dir, 'claude.exe'),
      // npm's global bin holds the shims; the real binary sits in the package.
      join(dir, 'node_modules', '@anthropic-ai', 'claude-code', 'bin', 'claude.exe'),
    ]) if (existsSync(p)) return p;
  }
  return 'claude'; // let it fail loudly rather than guess a path that isn't there
})();

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
  triage:     { activity: 'sorting',  match: /in[\s-]?box|e[\s-]?mail|mail|newsletter|unread|junk/ },
  scheduler:  { activity: 'booking',  match: /schedul|calendar|meeting|book/ },
  researcher: { activity: 'research', match: /research|look up|find out|investigate|dig into/ },
  // `needs` is the feedback loop: the analyst waits for the researcher and is
  // handed what it actually found, instead of re-deriving it in parallel.
  // `summar`/`note`/`digest` land here: "summarise my newsletters and make a note"
  // is analysis, and it is the phrasing people actually reach for.
  analyst:    { activity: 'analysis', match: /analy|compare|report|numbers|breakdown|summar|digest|note/, needs: ['researcher'] },
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
  // Remembered so `wakeAndListen` can tell the crew's voice from yours.
  if (agent.lastMessage) {
    spokenLines.push(agent.lastMessage);
    if (spokenLines.length > 60) spokenLines.shift();
  }
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
    if (FAKE) { push(cannedFor(task, role)); return finish(); }

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
    // `detached` is a no-op on Windows for process groups (there is no
    // setsid, and process.kill(-pid) is not a thing), so the group kill below
    // falls through to killing the child alone. Harmless: it is the same
    // behaviour we had before E's fix, and the `exit` grace still un-wedges it.
    const child = spawn(CLAUDE, args,
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
  recap: ['Pulling together what the crew did.'], // its sign-off is built from who ran
};

// The closer's canned sign-off was hardcoded to the inbox demo, so a research
// crew closed the show by claiming it had cleared a mailbox nobody had touched
// — spoken out loud, last line, and false. Real mode never had this: the closer
// is handed {{CREW}} and reports what actually ran. Fake mode now takes its
// sign-off from the same place, the roster.
// The rehearsed pair still produces the rehearsed line, byte for byte:
// triage + scheduler -> "Done: inbox cleared, two meetings booked."
const CANNED_CLOSE = {
  triage: 'inbox cleared',
  scheduler: 'two meetings booked',
  researcher: 'three facts worth knowing',
  analyst: 'the Thursday figure flagged',
};
const cannedFor = (task, role) =>
  role !== CLOSER ? CANNED[role] : [
    ...CANNED[CLOSER],
    // Unknown roles contribute nothing rather than a placeholder — a closer that
    // says "and something else" out loud is worse than one that stays specific.
    `Done: ${task.roles.filter((r) => CANNED_CLOSE[r]).map((r) => CANNED_CLOSE[r]).join(', ')
      || 'nothing to report'}.`,
  ];

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
  // Give the microphone back, so the next ⌘⌥C can hear a person again.
  if (MODE === 'voice') micTo(HUMAN_MIC);
  // The whole point of direct mode is that the mailbox really changed. If no
  // agent called a tool, it did not — say so here rather than letting the run
  // look identical to a narrated one.
  if (MODE === 'direct' && !FAKE) {
    console.log(toolCalls
      ? `[tool] ${toolCalls} tool calls this run — the mailbox really changed.`
      : '[tool] NO TOOL CALLS — direct mode narrated only. The mailbox is untouched.');
  }
}

// --- wake, ask, listen ---
// VoiceOS writes every transcript to `voice_sessions` in its own SQLite db, so
// we can read what the person said without VoiceOS needing to know we exist.
// (`dictations` is empty and legacy in 0.1.21 — that cost us half a day.)
const VOICEOS_DB = process.env.VOICEOS_DB
  || `${process.env.HOME}/Library/Application Support/VoiceOS/voiceos.db`;
const GREETING = process.env.CREW_GREETING || 'Hey. What can I do for you?';
const HUMAN_MIC = process.env.CREW_HUMAN_MIC || 'MacBook Pro Microphone';

/// Point the system input at a device. Best effort — a missing
/// `switchaudio-osx` must never stop a run, it just means the handover is manual.
const micTo = (device) => new Promise((resolve) => {
  const p = spawn('SwitchAudioSource', ['-t', 'input', '-s', device], { stdio: 'ignore' });
  p.on('close', (code) => { if (!code) console.log(`[wake] microphone -> ${device}`); resolve(); });
  p.on('error', () => resolve());
});
const LISTEN_MS = Number(process.env.LISTEN_MS || 30_000);

const sqlite = (sql) => new Promise((resolve) => {
  const p = spawn('sqlite3', ['-readonly', VOICEOS_DB, sql], { stdio: ['ignore', 'pipe', 'ignore'] });
  let out = '';
  p.stdout.on('data', (d) => (out += d));
  p.on('close', () => resolve(out.trim()));
  p.on('error', () => resolve(''));
});

let waking = false;

// Every line the crew has spoken. The dock narrates through the speakers and
// VoiceOS listens on the real microphone, so the crew hears ITSELF: a live run
// produced `heard: "two o'clock tomorrow is free day"` moments after a character
// said "Two o'clock tomorrow is free — David Chen, yours." Left alone the demo
// takes its own narration as the next instruction and talks to itself forever.
// The device split solves this for the agent loop; nothing could solve it here,
// because the whole point is that the microphone is open to the room.
const spokenLines = [];
const normalise = (s) => s.toLowerCase().replace(/[^a-z0-9 ]/g, ' ').replace(/\s+/g, ' ').trim();

function isOurOwnVoice(heard) {
  const words = new Set(normalise(heard).split(' ').filter((w) => w.length > 2));
  if (!words.size) return false;
  return spokenLines.some((line) => {
    const mine = new Set(normalise(line).split(' ').filter((w) => w.length > 2));
    if (!mine.size) return false;
    let hits = 0;
    for (const w of words) if (mine.has(w)) hits++;
    return hits / words.size >= 0.6;   // most of what we heard, we just said
  });
}

/// A transcript we should act on, or a reason not to.
function usable(heard) {
  const words = heard.trim().split(/\s+/).filter(Boolean);
  // "p" arrived as a task on a live run. A real instruction is a sentence.
  if (words.length < 3 || heard.trim().length < 12) return 'too short to be an instruction';
  if (isOurOwnVoice(heard)) return 'that was the crew talking, not you';
  return null;
}

async function wakeAndListen() {
  if (waking) return;              // one conversation at a time
  // Don't ask again while the crew is still working — a second greeting over a
  // running show is how one run became three on stage.
  const busy = [...tasks.values()].some((t) => t.status === 'running');
  if (busy) { console.log('[wake] ignored — the crew is still working'); return; }
  waking = true;
  const greeter = Object.keys(CREW)[0];
  const task = { taskId: 'wake', agents: { [greeter]: { name: greeter, state: 'idle', lastMessage: '' } } };

  // The crew arrives and asks. This is the beat the whole demo turns on: the
  // audience sees them show up *before* anyone has said what the job is.
  say(task, greeter, 'working', GREETING);

  let before = Number(await sqlite('SELECT COALESCE(MAX(rowid),0) FROM voice_sessions;')) || 0;
  console.log(`[wake] listening — say what you want (${LISTEN_MS / 1000}s)`);

  const deadline = Date.now() + LISTEN_MS;
  let heard = '';
  while (Date.now() < deadline && !heard) {
    await new Promise((r) => setTimeout(r, 700));
    const row = await sqlite(
      `SELECT transcript FROM voice_sessions WHERE rowid > ${before} AND transcript IS NOT NULL `
      + "AND trim(transcript) <> '' ORDER BY rowid DESC LIMIT 1;");
    if (!row) continue;
    const candidate = row.replace(/\s+/g, ' ').trim();
    const why = usable(candidate);
    if (why) { console.log(`[wake] ignoring "${candidate}" — ${why}`); before = Number(await sqlite('SELECT COALESCE(MAX(rowid),0) FROM voice_sessions;')) || before; continue; }
    heard = candidate;
  }

  waking = false;
  if (!heard) {
    // Distinguish "you said nothing" from "VoiceOS was not listening", because
    // they look identical from here and only one of them is your fault. A run
    // where the transcript table never moved means the microphone was never
    // opened — hands-free is a human press and nothing we do can make it.
    const after = Number(await sqlite('SELECT COALESCE(MAX(rowid),0) FROM voice_sessions;')) || 0;
    if (after === before) {
      console.log('[wake] VoiceOS never heard ANYTHING — hands-free is probably off.');
      console.log('       press fn+space once, then try again. It stays on after that.');
    } else {
      console.log('[wake] heard something but nothing usable — running the rehearsed task');
    }
    // Never leave a character standing there having asked a question. Falling
    // back means a failed transcription costs the demo its opening line, not
    // the demo.
    say(task, greeter, 'working', 'I did not catch that. I will start with the inbox.');
    return startTask(process.env.CREW_PHRASE || 'clean up my inbox and schedule everything');
  }
  console.log(`[wake] heard: "${heard}"`);
  // Hand the microphone to the crew. You spoke on the real mic; in `voice` mode
  // the agents drive VoiceOS by speaking to BlackHole, and one VoiceOS cannot
  // listen to both. Requires `voiceos-setup.sh auto` so VoiceOS follows the
  // system default rather than a pinned device — then this is instant and costs
  // no restart. Silent no-op in every other mode, where nobody is competing.
  if (MODE === 'voice') await micTo('BlackHole 2ch');
  return startTask(heard);
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

  // POST /wake — the demo's real opening. The crew arrives, ASKS what you want,
  // listens, and works on whatever you actually said. The hotkey used to fire a
  // hardcoded sentence, which is a demo of a script; this is a demo of a crew.
  //
  // Answers immediately and does the waiting in the background, because the
  // dock's key handler must not block for the length of a conversation.
  if (req.method === 'POST' && url.pathname === '/wake') {
    wakeAndListen();
    return send(res, 200, { status: 'listening' });
  }

  // Additive to the frozen contract — nothing existing changes shape. This is
  // how we see that VoiceOS actually reached the orchestrator when VoiceOS,
  // rather than a script, started the task: the bridge log proves the tool was
  // called, this proves a task exists because of it.
  if (req.method === 'GET' && url.pathname === '/tasks') {
    return send(res, 200, [...tasks.values()].map((t) => ({
      taskId: t.taskId, status: t.status, instructions: t.instructions,
    })));
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

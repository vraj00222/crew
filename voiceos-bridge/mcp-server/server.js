#!/usr/bin/env node
// Crew VoiceOS bridge — MCP server (stdio). Node stdlib only, no deps, no build step.
//
//   VoiceOS  --(spoken command)-->  run_crew_task  --POST-->  :4001/start-task
//
// Register:  voiceos add mcp
//   command: node   args: ["<abs path>/server.js"]
//
// Env:
//   ORCH_URL   orchestrator base       (default http://localhost:4001)
//   CREW_LOG   append-only JSONL audit (default ./crew-bridge.log next to this file)
//   TIMEOUT_MS orchestrator fetch cap  (default 8000)
//
// Self-test without an MCP client:  node server.js --selftest
//
// STDOUT IS THE PROTOCOL CHANNEL. Never console.log here — it corrupts the stream
// and the client silently drops the server. All human output goes to stderr.

const { appendFileSync } = require('node:fs');
const { join } = require('node:path');

// Which mailbox the crew_gmail_*/crew_calendar_* tools act on.
//   fake   — in-memory, seeded from demo-seed/fixtures.json. No account needed.
//   google — the real demo account, via demo-seed's token.json.
// Defaults to fake: an unconfigured machine gets a working demo, not a stack trace.
const BACKEND_NAME = process.env.CREW_BACKEND === 'google' ? 'google' : 'fake';

const ORCH_URL = (process.env.ORCH_URL || 'http://localhost:4001').replace(/\/+$/, '');
const LOG_PATH = process.env.CREW_LOG || join(__dirname, 'crew-bridge.log');
const TIMEOUT_MS = Number(process.env.TIMEOUT_MS || 8000);
const SERVER_NAME = 'crew';
const SERVER_VERSION = '0.1.0';

// Protocol versions we know how to speak, newest first. We echo the client's
// version when we recognise it (widest client compatibility), else offer ours.
const SUPPORTED = ['2025-06-18', '2025-03-26', '2024-11-05'];

// --- logging: stderr for humans, JSONL for proof of what VoiceOS actually sent ---
const log = (...a) => process.stderr.write(`[crew-mcp] ${a.join(' ')}\n`);

function audit(event, data) {
  const line = JSON.stringify({ ts: new Date().toISOString(), event, ...data });
  try {
    appendFileSync(LOG_PATH, line + '\n');
  } catch (e) {
    log('audit write failed:', e.message); // never fatal — logging must not kill the demo
  }
  return line;
}

// --- tools ---
const TOOLS = [
  {
    name: 'run_crew_task',
    description:
      'Hand a whole multi-step personal-productivity job to the Crew agent swarm. ' +
      'Use this for broad, open-ended requests about the user\'s inbox, email, ' +
      'calendar, meetings or scheduling — especially ones that bundle several ' +
      'chores together, such as "clean up my inbox and schedule everything". ' +
      'Pass the user\'s spoken request through verbatim; do not summarise, split, ' +
      'or rephrase it. Returns immediately with a taskId while the crew works.',
    inputSchema: {
      type: 'object',
      properties: {
        instructions: {
          type: 'string',
          description:
            "The user's request, word for word as they said it. " +
            'e.g. "clean up my inbox and schedule everything"',
        },
      },
      required: ['instructions'],
    },
  },
  {
    name: 'crew_task_status',
    description:
      'Check how a Crew task that is already running is progressing, and what each ' +
      'agent last did. Only for following up on a task previously started by ' +
      'run_crew_task — never use this to start new work.',
    inputSchema: {
      type: 'object',
      properties: {
        taskId: {
          type: 'string',
          description: 'The taskId returned by run_crew_task, e.g. "task_1".',
        },
      },
      required: ['taskId'],
    },
  },
];

// --- the work tools: names frozen in COORDINATION.md, A writes prompts against them ---
// Loaded lazily so a missing/broken google token can't stop the server from starting —
// run_crew_task must keep working even if the mailbox half is misconfigured.
let _backend = null;
function backend() {
  if (!_backend) {
    _backend = require(BACKEND_NAME === 'google' ? './backend-google.js' : './backend-fake.js');
    log(`mailbox backend: ${_backend.name}`);
  }
  return _backend;
}

const WORK_TOOLS = [
  {
    name: 'crew_gmail_list_inbox',
    description:
      'List what is currently in the inbox. Optional plain-English query such as ' +
      '"newsletters", "meeting requests", or a sender name — no Gmail search syntax needed.',
    inputSchema: {
      type: 'object',
      properties: {
        query: { type: 'string', description: 'e.g. "newsletters". Omit for everything.' },
        limit: { type: 'number', description: 'Max messages to return. Default 25.' },
      },
    },
  },
  {
    name: 'crew_gmail_archive',
    description:
      'Archive messages out of the inbox. Give a plain-English query like "newsletters", ' +
      'or explicit message ids. Archiving only removes the INBOX label — nothing is deleted.',
    inputSchema: {
      type: 'object',
      properties: {
        query: { type: 'string', description: 'e.g. "newsletters"' },
        ids: { type: 'array', items: { type: 'string' }, description: 'Explicit ids, instead of a query.' },
      },
    },
  },
  {
    name: 'crew_gmail_label',
    description: 'Apply a label to messages matching a query or id list. Creates the label if new.',
    inputSchema: {
      type: 'object',
      properties: {
        label: { type: 'string', description: 'Label to apply, e.g. "Needs reply".' },
        query: { type: 'string' },
        ids: { type: 'array', items: { type: 'string' } },
      },
      required: ['label'],
    },
  },
  {
    name: 'crew_calendar_find_slot',
    description:
      'Find the first free slot of a given length on a given day. Returns ISO start/end. ' +
      'Use this before booking — never guess whether a time is free.',
    inputSchema: {
      type: 'object',
      properties: {
        durationMin: { type: 'number', description: 'Length in minutes. Default 60.' },
        dayOffset: { type: 'number', description: '0 = today, 1 = tomorrow (default).' },
        afterISO: { type: 'string', description: 'Only consider slots at or after this ISO time.' },
      },
    },
  },
  {
    name: 'crew_calendar_book',
    description:
      'Book an event. Use a start time returned by crew_calendar_find_slot. ' +
      'No invitation email is sent to anyone.',
    inputSchema: {
      type: 'object',
      properties: {
        summary: { type: 'string', description: 'Event title, e.g. "Q3 rollout sync".' },
        startISO: { type: 'string', description: 'ISO start time.' },
        durationMin: { type: 'number', description: 'Default 60.' },
        attendee: { type: 'string', description: 'Who it is with, e.g. "David Chen".' },
      },
      required: ['summary', 'startISO'],
    },
  },
  {
    name: 'crew_calendar_list',
    description: "List a day's events. dayOffset 0 = today, 1 = tomorrow (default).",
    inputSchema: {
      type: 'object',
      properties: { dayOffset: { type: 'number' } },
    },
  },
];

// tool name -> backend call. Kept as data so both backends stay interchangeable.
const WORK_DISPATCH = {
  crew_gmail_list_inbox: (b, a) => b.listInbox(a),
  crew_gmail_archive: (b, a) => b.archive(a),
  crew_gmail_label: (b, a) => b.label(a),
  crew_calendar_find_slot: (b, a) => b.findSlot(a),
  crew_calendar_book: (b, a) => b.book(a),
  crew_calendar_list: (b, a) => b.listEvents(a),
};

const text = (s, isError = false) => ({ content: [{ type: 'text', text: s }], isError });

async function orchFetch(path, init) {
  const res = await fetch(`${ORCH_URL}${path}`, {
    ...init,
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  const body = await res.text();
  let json;
  try {
    json = JSON.parse(body);
  } catch {
    /* orchestrator returned non-JSON; surface the raw body below */
  }
  return { ok: res.ok, status: res.status, body, json };
}

// Turn any failure into a sentence a voice assistant can read out. The demo
// should never die on a stack trace, but it must say *which* hop broke.
function explainFailure(e) {
  if (e?.name === 'TimeoutError' || e?.name === 'AbortError') {
    return `The orchestrator at ${ORCH_URL} did not answer within ${TIMEOUT_MS}ms.`;
  }
  const cause = e?.cause?.code || e?.code;
  if (cause === 'ECONNREFUSED') {
    return `Could not reach the orchestrator at ${ORCH_URL} — is it running? (node orchestrator/server.js)`;
  }
  return `Could not reach the orchestrator at ${ORCH_URL}: ${e?.message || e}`;
}

async function callTool(name, args) {
  if (name === 'run_crew_task') {
    const instructions = args?.instructions;
    if (typeof instructions !== 'string' || !instructions.trim()) {
      return text('run_crew_task needs a non-empty "instructions" string.', true);
    }
    // Log BEFORE dispatching: if the orchestrator is down we still have proof of
    // exactly what VoiceOS heard and passed us. That's the thing under test.
    audit('run_crew_task', { instructions });
    log(`run_crew_task <- ${JSON.stringify(instructions)}`);

    try {
      // A's contract: POST /start-task {instructions} -> {taskId, status:"started"}
      const r = await orchFetch('/start-task', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ instructions }),
      });
      if (!r.ok) {
        audit('orchestrator_error', { status: r.status, body: r.body.slice(0, 500) });
        return text(`The orchestrator rejected the task (HTTP ${r.status}): ${r.body.slice(0, 200)}`, true);
      }
      const taskId = r.json?.taskId ?? '(no taskId returned)';
      audit('orchestrator_ok', { taskId, status: r.json?.status });
      log(`started ${taskId}`);
      return text(
        `The crew is on it. Task ${taskId} started — the agents are waking up on the dock now.`
      );
    } catch (e) {
      const msg = explainFailure(e);
      audit('orchestrator_unreachable', { error: String(e?.message || e) });
      log(msg);
      return text(msg, true);
    }
  }

  if (name === 'crew_task_status') {
    const taskId = args?.taskId;
    if (typeof taskId !== 'string' || !taskId.trim()) {
      return text('crew_task_status needs a "taskId" string.', true);
    }
    try {
      const r = await orchFetch(`/status/${encodeURIComponent(taskId)}`, { method: 'GET' });
      if (!r.ok) return text(`No such task ${taskId} (HTTP ${r.status}).`, true);
      const agents = r.json?.agents || [];
      // A's note: an agent starts 'idle' and only 'done' means finished.
      const lines = agents.map((a) => `${a.name} (${a.state}): ${a.lastMessage || '—'}`);
      return text(
        `Task ${taskId} is ${r.json?.status}.\n` + (lines.join('\n') || 'No agents reporting yet.')
      );
    } catch (e) {
      return text(explainFailure(e), true);
    }
  }

  const work = WORK_DISPATCH[name];
  if (work) {
    audit(name, { args });
    log(`${name} <- ${JSON.stringify(args || {})}`);
    try {
      const result = await work(backend(), args || {});
      audit(`${name}_ok`, { result });
      return text(JSON.stringify(result, null, 2));
    } catch (e) {
      // Backend failures are readable sentences, not stack traces — VoiceOS may
      // read this out loud, and it should say which half broke.
      audit(`${name}_error`, { error: String(e?.message || e) });
      log(`${name} failed: ${e?.message || e}`);
      return text(`${name} failed (${BACKEND_NAME} backend): ${e?.message || e}`, true);
    }
  }

  return text(`Unknown tool: ${name}`, true);
}

// --- JSON-RPC 2.0 over newline-delimited stdio ---
const send = (msg) => process.stdout.write(JSON.stringify(msg) + '\n');
const ok = (id, result) => send({ jsonrpc: '2.0', id, result });
const err = (id, code, message) => send({ jsonrpc: '2.0', id, error: { code, message } });

async function handle(msg) {
  const { id, method, params } = msg;
  const isNotification = id === undefined || id === null;

  switch (method) {
    case 'initialize': {
      const want = params?.protocolVersion;
      const version = SUPPORTED.includes(want) ? want : SUPPORTED[0];
      audit('initialize', { client: params?.clientInfo, protocolVersion: want });
      log(`initialize from ${params?.clientInfo?.name || 'unknown client'} (proto ${want}) -> ${version}`);
      return ok(id, {
        protocolVersion: version,
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: SERVER_NAME, version: SERVER_VERSION },
      });
    }

    // Notifications get no reply, ever. Replying to one is a protocol violation.
    case 'notifications/initialized':
    case 'initialized':
      log('client ready');
      return;

    case 'ping':
      return ok(id, {});

    case 'tools/list':
      return ok(id, { tools: [...TOOLS, ...WORK_TOOLS] });

    case 'tools/call': {
      const { name, arguments: args } = params || {};
      try {
        return ok(id, await callTool(name, args));
      } catch (e) {
        log(`tool ${name} threw: ${e?.stack || e}`);
        return err(id, -32603, `Internal error in ${name}: ${e?.message || e}`);
      }
    }

    // Advertised as unsupported in capabilities, but some clients probe anyway.
    case 'resources/list':
      return ok(id, { resources: [] });
    case 'prompts/list':
      return ok(id, { prompts: [] });

    default:
      if (isNotification) return; // unknown notification: ignore, don't error
      return err(id, -32601, `Method not found: ${method}`);
  }
}

function serve() {
  let buf = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (chunk) => {
    buf += chunk;
    const lines = buf.split('\n');
    buf = lines.pop(); // keep the partial line for the next chunk
    for (const line of lines) {
      if (!line.trim()) continue;
      let msg;
      try {
        msg = JSON.parse(line);
      } catch {
        log(`parse error on: ${line.slice(0, 200)}`);
        err(null, -32700, 'Parse error');
        continue;
      }
      handle(msg).catch((e) => log(`handler crashed: ${e?.stack || e}`));
    }
  });
  process.stdin.on('end', () => process.exit(0));
  log(`ready on stdio -> orchestrator ${ORCH_URL} (log: ${LOG_PATH})`);
}

// --- self-test: drives this same handler through a real handshake, no client needed ---
async function selftest() {
  const out = [];
  const realWrite = process.stdout.write.bind(process.stdout);
  process.stdout.write = (s) => (out.push(s.trim()), true);

  await handle({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-06-18', clientInfo: { name: 'selftest', version: '0' } } });
  await handle({ jsonrpc: '2.0', method: 'notifications/initialized' });
  await handle({ jsonrpc: '2.0', id: 2, method: 'tools/list' });
  await handle({ jsonrpc: '2.0', id: 3, method: 'tools/call', params: { name: 'run_crew_task', arguments: { instructions: 'clean up my inbox and schedule everything' } } });

  process.stdout.write = realWrite;

  const res = out.map((l) => JSON.parse(l));
  const [init, list, call] = [res[0], res[1], res[2]];
  const fail = (m) => (process.stderr.write(`FAIL: ${m}\n`), process.exit(1));

  if (out.length !== 3) fail(`expected 3 responses (the notification must NOT get one), got ${out.length}`);
  if (init.result?.serverInfo?.name !== SERVER_NAME) fail('initialize did not return serverInfo');
  if (!list.result?.tools?.some((t) => t.name === 'run_crew_task')) fail('run_crew_task missing from tools/list');
  if (!list.result.tools[0].inputSchema?.required?.includes('instructions')) fail('instructions not required');
  if (!call.result?.content?.[0]?.text) fail('tools/call returned no text content');

  process.stderr.write(`\nprotocol OK  (init -> ${init.result.protocolVersion}, ${list.result.tools.length} tools)\n`);
  process.stderr.write(`tools/call  -> ${JSON.stringify(call.result.content[0].text)}\n`);
  process.stderr.write(call.result.isError
    ? `\nPASS (protocol). Orchestrator unreachable — expected if :4001 is not running.\n`
    : `\nPASS — full path works: MCP tool call reached the orchestrator on ${ORCH_URL}.\n`);
}

if (process.argv.includes('--selftest')) selftest();
else serve();

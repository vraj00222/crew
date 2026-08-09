#!/usr/bin/env node
// Crew VoiceOS bridge — MCP server (stdio). Node stdlib only, no deps, no build step.
//
//   VoiceOS  --(spoken command)-->  run_crew_task     --POST-->  :4001/start-task
//   VoiceOS  --("how's it going?")->  crew_task_status --GET -->  :4001/status/:id
//                                        `-> one spoken sentence, not JSON
//
// Register in VoiceOS settings as a custom MCP server:
//   name: crew   command: node   args: ["<absolute path>/server.js"]
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

const { appendFileSync, readFileSync, writeFileSync, statSync } = require('node:fs');
const { join } = require('node:path');
const { speakStatus } = require('./status-speech.js');

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

// --- what the crew is currently working on ---
// The demo is a *loop*, not a one-shot: the human says one sentence, then asks
// "what's the crew doing?" and later "are they done?". VoiceOS has no memory of a
// taskId across those turns, and a person will never say one out loud — so the
// bridge remembers it and crew_task_status takes it as optional.
let lastTaskId = null;

// If VoiceOS respawns this server between starting the task and asking about it,
// the in-memory id is gone but the audit log still has it. Cheap to read, and the
// worst case is a stale id from an earlier run, which the orchestrator answers
// with a 404 and we report honestly rather than inventing progress.
function rememberedTaskId() {
  if (lastTaskId) return lastTaskId;
  try {
    const lines = readFileSync(LOG_PATH, 'utf8').trim().split('\n');
    for (let i = lines.length - 1; i >= 0; i--) {
      let rec;
      try { rec = JSON.parse(lines[i]); } catch { continue; } // torn line: keep scanning
      if (rec.event === 'orchestrator_ok' && rec.taskId) return rec.taskId;
    }
  } catch {
    /* no log yet — not knowing is a valid answer here */
  }
  return null;
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
    annotations: {
      title: 'Put the crew to work',
      readOnlyHint: false,
      destructiveHint: false, // archiving only unfiles mail; booking only adds an event
      idempotentHint: false, // saying it twice starts two runs
      openWorldHint: true,
    },
  },
  {
    name: 'crew_task_status',
    description:
      'Ask what the Crew is doing right now, how far along it is, or whether it has ' +
      'finished. Use this for any follow-up about work already running — "what are ' +
      'they doing?", "how is it going?", "are they done yet?", "what did the crew ' +
      'do?". Answers with a short spoken progress report naming each agent. ' +
      'Takes no arguments in the normal case: it reports on the most recent task. ' +
      'Never use this to start new work — that is run_crew_task.',
    inputSchema: {
      type: 'object',
      properties: {
        taskId: {
          type: 'string',
          description:
            'Optional. Only needed to ask about an older task by id, e.g. "task_1". ' +
            'Omit it to report on the task that is running now.',
        },
      },
    },
    annotations: {
      title: 'Ask the crew how it is going',
      readOnlyHint: true, // pure GET against the orchestrator; changes nothing
      idempotentHint: true,
      openWorldHint: true,
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

// A note on `annotations`, because the values are load-bearing and it is tempting
// to lie: VoiceOS reads these hints when building confirmation cards. Read-only
// tools go through without a human click; writes still ask. So they are declared
// exactly as they behave, no more: archive/label are writes but `destructiveHint`
// is false because archiving only drops the INBOX label and nothing is deleted.
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
    annotations: { title: 'Read the inbox', readOnlyHint: true, idempotentHint: true, openWorldHint: true },
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
    annotations: {
      title: 'Archive mail out of the inbox',
      readOnlyHint: false,
      destructiveHint: false, // removes the INBOX label only — reversible, nothing deleted
      idempotentHint: true, // archiving an already-archived message is a no-op
      openWorldHint: true,
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
    annotations: {
      title: 'Label mail',
      readOnlyHint: false,
      destructiveHint: false, // adds a label; removes nothing
      idempotentHint: true,
      openWorldHint: true,
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
    annotations: { title: 'Find a free slot', readOnlyHint: true, idempotentHint: true, openWorldHint: true },
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
    annotations: {
      title: 'Book a meeting',
      readOnlyHint: false,
      destructiveHint: false, // adds an event; never overwrites or cancels one
      idempotentHint: false, // booking twice puts two meetings on the calendar
      openWorldHint: true,
    },
  },
  {
    name: 'crew_calendar_list',
    description: "List a day's events. dayOffset 0 = today, 1 = tomorrow (default).",
    inputSchema: {
      type: 'object',
      properties: { dayOffset: { type: 'number' } },
    },
    annotations: { title: "Read the day's calendar", readOnlyHint: true, idempotentHint: true, openWorldHint: true },
  },
  // --- a1mobile: a real text and a real phone call, not simulations ---
  // The API only reaches numbers a human has OTP-verified (consent), so the
  // blast radius is the demo phone and nothing else. The OTP flow itself is
  // deliberately NOT a tool — it is a one-time human step, node a1mobile.js.
  {
    name: 'crew_send_sms',
    description:
      'Send a real SMS text message to the user\'s phone. Use only when the user ' +
      'asked to be texted — "text me", "send me a message", "SMS me the summary". ' +
      'Omit "to" to reach the user\'s own verified phone.',
    inputSchema: {
      type: 'object',
      properties: {
        body: { type: 'string', description: 'The text message, e.g. "Inbox cleared, two meetings booked."' },
        to: { type: 'string', description: 'E.164 number, e.g. +14155551234. Omit for the user\'s phone.' },
      },
      required: ['body'],
    },
    annotations: {
      title: 'Text the user\'s phone',
      readOnlyHint: false,
      destructiveHint: false, // sends a message; changes and deletes nothing
      idempotentHint: false, // saying it twice sends two texts
      openWorldHint: true,
    },
  },
  {
    name: 'crew_place_call',
    description:
      'Place a real phone call to the user: their phone rings, a voice speaks the ' +
      'message aloud, then hangs up. Use only when the user asked to be called — ' +
      '"call me", "ring me when it\'s done". Omit "to" to reach the user\'s own ' +
      'verified phone.',
    inputSchema: {
      type: 'object',
      properties: {
        message: { type: 'string', description: 'What the call says out loud, one or two spoken sentences.' },
        to: { type: 'string', description: 'E.164 number, e.g. +14155551234. Omit for the user\'s phone.' },
      },
      required: ['message'],
    },
    annotations: {
      title: 'Call the user\'s phone',
      readOnlyHint: false,
      destructiveHint: false, // rings a phone; changes and deletes nothing
      idempotentHint: false, // calling twice rings twice
      openWorldHint: true,
    },
  },
  {
    name: 'crew_ask_user',
    description:
      'You are stuck and need the user\'s decision to continue: call their phone, ' +
      'state the problem, and get their spoken answer back as text. The call asks ' +
      'the question, beeps, and listens; this tool waits (up to ~2 minutes) and ' +
      'returns what they said. Use it for a genuine blocker with a real choice in ' +
      'it — never for status updates (that is crew_send_sms / crew_place_call) and ' +
      'never twice in a row for the same question.',
    inputSchema: {
      type: 'object',
      properties: {
        question: {
          type: 'string',
          description:
            'The blocker plus the question, as one or two spoken sentences. ' +
            'e.g. "Two meetings both want two PM tomorrow. Which one wins, David or Priya?"',
        },
        to: { type: 'string', description: 'E.164 number, e.g. +14155551234. Omit for the user\'s phone.' },
      },
      required: ['question'],
    },
    annotations: {
      title: 'Phone the user a question and wait for the answer',
      readOnlyHint: false,
      destructiveHint: false, // rings a phone; changes and deletes nothing
      idempotentHint: false, // asking twice rings twice
      openWorldHint: true,
    },
  },
];

// Lazy like the mailbox backend, and for the same reason: a machine with no
// team key must still serve every other tool. Only sms/call can fail there.
let _a1 = null;
const a1 = () => (_a1 ??= require('./a1mobile.js'));

// An outbound call runs the pointed webhook on ANSWER, so the message must be
// queued on voice-webhook.js before the dial, not after. Queue failure is a
// hard error: a call that answers and speaks the wrong message reads as broken
// on stage in a way a clean "start the voice server" sentence never does.
const VOICE_URL = `http://localhost:${process.env.CREW_VOICE_PORT || 4003}`;
// How long crew_ask_user waits for the person to pick up, talk, and the
// transcript to land. The orchestrator sizes its per-agent kill timer off this
// same number in direct mode, so an agent can no longer be killed mid-call.
const ASK_WAIT_MS = Number(process.env.CREW_ASK_WAIT_MS || 120_000);

// Who we are and where to report it. The orchestrator sets all three when it
// spawns the agent that owns this bridge process (see its mcpConfig). Absent —
// a hand-run bridge, or VoiceOS's own — announcing is simply skipped.
const ROLE = process.env.CREW_ROLE || '';
const TASK_ID = process.env.CREW_TASK_ID || '';
const EVENTS_URL = process.env.CREW_ORCH_EVENTS || '';

// Put a line on stage for the character that is holding the phone. Nothing this
// function does may break a call: it is the narration of the event, not the
// event, so every failure is swallowed. The whole point is the two minutes
// between the dial and the transcript, during which this agent writes nothing
// to stdout and the dock would otherwise sit frozen while the presenter's phone
// rings in their hand.
async function announce(kind, message, text) {
  if (!EVENTS_URL || !TASK_ID || !ROLE) return;
  try {
    await fetch(EVENTS_URL, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ taskId: TASK_ID, role: ROLE, kind, message, text }),
      signal: AbortSignal.timeout(3000),
    });
  } catch { /* the dock is decoration here — a call must never fail over it */ }
}

// --- the deterministic route ---
// The same idea as `./run-demo.sh fake`, for the phone: a rung that cannot fail
// because it depends on nothing outside this process. No a1mobile, no team key,
// no tunnel, no Telnyx, no whisper, no network. The dock still gets the entire
// performance — the character still says it is calling you, still says what you
// "said", and the crew still works from that answer — so the story the audience
// watches is identical. What is missing is only the ringing.
//
// This exists because the real path has five things that can be down at 5:55pm
// (key, verified number, voice server, tunnel, transcription) and a hackathon
// demo cannot be one bad wifi away from having no third act.
//   CREW_PHONE_FAKE=1   everything below is simulated, and says so
//   CREW_FAKE_ANSWER    force one specific answer, for a rehearsed run
const PHONE_FAKE = process.env.CREW_PHONE_FAKE === '1';
// Long enough that the room reads "calling you…" on the dock before the answer
// lands on top of it. Pacing, not latency simulation.
const FAKE_ASK_MS = Number(process.env.CREW_FAKE_ASK_MS || 6000);

// Keyword-matched, not generated — a planner is a thing that can be wrong on
// stage, and the whole point of this route is that it cannot be. Ordered most
// specific first; the last entry is what an unrehearsed question gets.
const FAKE_ANSWERS = [
  [/anything else|something else|what else/i, "No, that's everything. Thanks."],
  [/which|who|whose|pick|choose|David|Priya|wins?\b/i, 'Give the two PM slot to David, and offer Priya Thursday morning.'],
  [/junk|spam|important|archive|delete|bin/i, "Archive it, it's junk — but anything from the bank, keep."],
  [/book|schedule|move|reschedule|slot|calendar/i, 'Book it, and keep the afternoon after four clear.'],
];
const fakeAnswer = (q) =>
  process.env.CREW_FAKE_ANSWER
  || (FAKE_ANSWERS.find(([re]) => re.test(q)) || [null, 'Use your best judgment on that one, I trust you.'])[1];

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function queueOnVoiceServer(path, body) {
  try {
    const r = await fetch(`${VOICE_URL}${path}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(3000),
    });
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
  } catch {
    throw new Error(
      `the call-script server is not answering on ${VOICE_URL} — start it with: node voice-webhook.js`
    );
  }
}

// One report per run. Several agents get the same "text me" instruction and
// each obeys it — live run task_1 sent the user two texts, one from the
// scheduler and one from the analyst. The bridge is the one place every send
// passes through, so it holds the line: a repeat inside the window comes back
// as a normal "already sent" result the agent can narrate past, not an error.
// Asks are exempt — a question is deliberate, and unanswered is its own state.
//
// The mark is a FILE, not a variable, and that is load-bearing: in direct mode
// every agent spawns its own bridge process (mcp-config.js), so memory in one
// never sees a send from another — which is precisely how the double text
// happened. The file's mtime is the shared clock.
const REPORT_COOLDOWN_MS = Number(process.env.CREW_REPORT_COOLDOWN_MS || 120_000);
const REPORT_MARK = join(__dirname, '.report-mark');
function oneReport(send) {
  return async (args) => {
    try {
      if (Date.now() - statSync(REPORT_MARK).mtimeMs < REPORT_COOLDOWN_MS) return { duplicate: true };
    } catch { /* no mark yet — first report */ }
    const result = await send(args); // a failed send does not claim the slot
    writeFileSync(REPORT_MARK, new Date().toISOString());
    return result;
  };
}

// Wrapped by oneReport at the dispatch table below, so the simulated route
// dedupes exactly like the real one — a rehearsal that texts once and a show
// that texts twice would be the worst possible way to find this out.
async function sendSms(args) {
  const body = args?.body;
  if (typeof body !== 'string' || !body.trim()) throw new Error('crew_send_sms needs a non-empty "body"');
  if (PHONE_FAKE) return { fake: true, to: args?.to || 'the demo phone', body };
  return a1().sendSms({ to: args?.to, body });
}

async function callWithMessage(args) {
  const message = args?.message;
  if (typeof message !== 'string' || !message.trim()) throw new Error('crew_place_call needs a non-empty "message"');
  if (PHONE_FAKE) {
    await announce('calling', 'Calling your phone now.');
    return { fake: true, to: args?.to || 'the demo phone', message };
  }
  await queueOnVoiceServer('/say', { message });
  await announce('calling', 'Calling your phone now.');
  return a1().placeCall({ to: args?.to });
}

// The stuck-agent loop: ring the user, ask, park until they have spoken and
// whisper has written it down, hand the words back to the agent. "No answer"
// comes back as a normal result, not an error — being stuck is the state the
// agent was already in, and it should carry on with its best judgment, said
// out loud, rather than crash the show.
async function askUser(args) {
  const question = args?.question;
  if (typeof question !== 'string' || !question.trim()) throw new Error('crew_ask_user needs a non-empty "question"');
  // The deterministic route. Same beats, same timing, same lines on the dock —
  // the only thing that does not happen is the ringing.
  if (PHONE_FAKE) {
    const text = fakeAnswer(question);
    await announce('calling', `I need you on this one. Calling you now: ${question.trim()}`);
    await sleep(FAKE_ASK_MS);
    await announce('answered', `You said: ${text}. Carrying on.`, text);
    return { fake: true, answered: true, text };
  }

  // Real path, but never fatal. If the voice server or the tunnel is down there
  // will be no call at all, and killing the agent over it would throw away the
  // rest of its work. Being stuck is the state it was already in, so it gets
  // told plainly that the line is dead and carries on deciding for itself —
  // and it is told the line failed, not that "you did not answer", because we
  // never actually rang and should not say we did.
  try {
    await queueOnVoiceServer('/ask', { question });
  } catch (e) {
    await announce('calling', 'I could not get through to you — deciding this one myself.');
    return { answered: false, unreachable: true, text: null, reason: e.message };
  }
  // Said on the dock BEFORE the dial, and it carries the question itself: the
  // room can hear the characters but not the earpiece, so this is the only way
  // the audience knows what the presenter is being asked while they pick up.
  await announce('calling', `I need you on this one. Calling you now: ${question.trim()}`);
  const placed = await a1().placeCall({ to: args?.to });
  if (placed.dry) return placed;
  const r = await fetch(`${VOICE_URL}/answer?timeout=${ASK_WAIT_MS}`, {
    signal: AbortSignal.timeout(ASK_WAIT_MS + 10_000),
  });
  const { text } = await r.json();
  // The answer goes on stage AND onto the task, so every agent that runs after
  // this one is handed what the user decided rather than re-guessing it.
  await announce(
    'answered',
    text ? `You said: ${text}. Carrying on.` : 'No answer — I will use my best judgment.',
    text || undefined
  );
  return { ...placed, answered: !!text, text: text || null };
}

// tool name -> its call. Each entry loads its own dependency, so a broken
// google token stops mailbox tools only and a missing team key stops phone
// tools only — never each other.
const WORK_DISPATCH = {
  crew_gmail_list_inbox: (a) => backend().listInbox(a),
  crew_gmail_archive: (a) => backend().archive(a),
  crew_gmail_label: (a) => backend().label(a),
  crew_calendar_find_slot: (a) => backend().findSlot(a),
  crew_calendar_book: (a) => backend().book(a),
  crew_calendar_list: (a) => backend().listEvents(a),
  // Outward-facing on purpose, and real — see the tool descriptions above.
  // oneReport wraps the FAKE-aware entry points, not the raw client, so the
  // simulated phone is deduped on the same rule as the real one.
  crew_send_sms: oneReport((a) => sendSms(a)),
  crew_place_call: oneReport((a) => callWithMessage(a)),
  crew_ask_user: (a) => askUser(a),
};

const text = (s, isError = false, structuredContent) => ({
  content: [{ type: 'text', text: s }],
  ...(structuredContent === undefined ? {} : { structuredContent }),
  isError,
});

function plural(n, one, many = `${one}s`) {
  return `${n} ${n === 1 ? one : many}`;
}

function thereAre(n, thing) {
  return `There ${n === 1 ? 'is' : 'are'} ${plural(n, thing)}`;
}

function sayTime(iso) {
  if (!iso) return 'that time';
  return new Date(iso).toLocaleString('en-US', {
    weekday: 'short',
    hour: 'numeric',
    minute: '2-digit',
  });
}

function workReply(name, result) {
  switch (name) {
    case 'crew_gmail_list_inbox': {
      const matched = result?.matched ?? 0;
      const total = result?.total ?? matched;
      if (matched === total) return `${thereAre(total, 'message')} in the inbox.`;
      return `I found ${plural(matched, 'matching message')} out of ${plural(total, 'message')} in the inbox.`;
    }
    case 'crew_gmail_archive': {
      const archived = result?.archived ?? 0;
      const remaining = result?.remainingInInbox;
      if (remaining === null || remaining === undefined) return `Archived ${plural(archived, 'message')}.`;
      return `Archived ${plural(archived, 'message')}; ${plural(remaining, 'message')} ${remaining === 1 ? 'remains' : 'remain'} in the inbox.`;
    }
    case 'crew_gmail_label':
      return `Marked ${plural(result?.labelled ?? 0, 'message')} as ${result?.label || 'requested'}.`;
    case 'crew_calendar_find_slot':
      if (result?.found) return `Found a ${result.durationMin || 60}-minute opening at ${sayTime(result.start)}.`;
      return result?.reason || 'No open slot matched that request.';
    case 'crew_calendar_book':
      if (result?.booked) {
        const event = result.event || {};
        const who = event.attendee ? ` with ${event.attendee}` : '';
        return `Booked ${event.summary || 'the meeting'}${who} at ${sayTime(event.start)}.`;
      }
      return result?.reason || 'That meeting could not be booked.';
    case 'crew_calendar_list':
      return `${thereAre(result?.events?.length ?? 0, 'event')} on ${result?.day || 'that day'}.`;
    // `dry` is the real client staging a send; `fake` is the deterministic
    // route standing in for the whole phone. Both are told to the agent as
    // plainly as they are told to us — an agent that thinks it really texted
    // someone will say so out loud, and that is a lie on stage.
    case 'crew_send_sms':
      if (result?.duplicate) return 'A report already went to the phone for this job — not sending another. Carry on.';
      if (result?.dry) return 'Rehearsal mode — the text was written but not really sent.';
      if (result?.fake) return 'Simulated — the text was composed but no phone was contacted. Report it as done.';
      return 'The text is sent — it should be on the phone now.';
    case 'crew_place_call':
      if (result?.duplicate) return 'A report already went to the phone for this job — not calling again. Carry on.';
      if (result?.dry) return 'Rehearsal mode — the call was staged but the phone will not ring.';
      if (result?.fake) return 'Simulated — no phone was contacted. Report it as done.';
      return 'Calling now — the phone should start ringing in a moment.';
    case 'crew_ask_user':
      if (result?.dry) return 'Rehearsal mode — the question was staged but the phone will not ring.';
      if (result?.unreachable) {
        return 'The phone line is down, so nobody was actually called. Decide with your '
          + 'best judgment and say out loud which way you went.';
      }
      if (result?.answered) return `The user said: "${result.text}"`;
      return 'The user did not answer, or said nothing. Decide with your best judgment and say which way you went.';
    default:
      return 'Done.';
  }
}

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
    return 'The crew is awake but taking too long to answer. Start a clean run and ask me again.';
  }
  const cause = e?.cause?.code || e?.code;
  if (cause === 'ECONNREFUSED') {
    return "The crew isn't awake yet. Start the orchestrator and ask me again.";
  }
  return `The crew could not be reached: ${e?.message || e}`;
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
      if (r.json?.taskId) lastTaskId = r.json.taskId; // so "what's the crew doing?" needs no id
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
    const asked = typeof args?.taskId === 'string' ? args.taskId.trim() : '';
    const taskId = asked || rememberedTaskId();
    // Nobody says a taskId out loud, so "no id and nothing running" is a normal
    // conversational turn, not an error — answer it like one.
    if (!taskId) {
      return text("The crew hasn't been given anything to do yet.");
    }
    try {
      const r = await orchFetch(`/status/${encodeURIComponent(taskId)}`, { method: 'GET' });
      if (r.status === 404) {
        lastTaskId = null; // a remembered id from a previous orchestrator run
        return text(`I can't find ${taskId} any more — the orchestrator has no record of it.`, true);
      }
      if (!r.ok) return text(`The orchestrator could not report on ${taskId} (HTTP ${r.status}).`, true);
      lastTaskId = taskId; // an id asked for by hand becomes the one we follow
      const spoken = speakStatus(r.json);
      log(`crew_task_status ${taskId} -> ${spoken}`);
      audit('crew_task_status', { taskId, status: r.json?.status, spoken });
      return text(spoken);
    } catch (e) {
      return text(explainFailure(e), true);
    }
  }

  const work = WORK_DISPATCH[name];
  if (work) {
    audit(name, { args });
    log(`${name} <- ${JSON.stringify(args || {})}`);
    try {
      const result = await work(args || {});
      audit(`${name}_ok`, { result });
      return text(workReply(name, result), false, result);
    } catch (e) {
      // Backend failures are readable sentences, not stack traces — VoiceOS may
      // read this out loud, and it should say which half broke. Phone tools do
      // not go through the mailbox backend, so blaming it would misdirect.
      audit(`${name}_error`, { error: String(e?.message || e) });
      log(`${name} failed: ${e?.message || e}`);
      const where = /^crew_(send_|place_|ask_)/.test(name) ? 'a1mobile' : `${BACKEND_NAME} backend`;
      return text(`${name} failed (${where}): ${e?.message || e}`, true);
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
  // The fake phone is loud in the log on purpose. It is the one setting that
  // makes the show look completely normal while nothing leaves the machine —
  // exactly the state you must never discover by wondering why a phone that
  // was supposed to ring did not.
  log(`ready on stdio -> orchestrator ${ORCH_URL}${PHONE_FAKE ? ' [PHONE FAKE — no phone will ring]' : ''} (log: ${LOG_PATH})`);
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

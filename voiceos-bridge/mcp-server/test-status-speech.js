#!/usr/bin/env node
// What the crew SAYS when the human asks how it is going.
//
//   node test-status-speech.js
//
// No orchestrator, no VoiceOS, no network, no Mac. VoiceOS reads these strings out
// verbatim, so this file is really a script review: read the right-hand side aloud
// and if it sounds like a machine reading a struct, the test has done its job.

const { speakStatus } = require('./status-speech.js');

let failed = 0;
const cases = [];

// `want` is a substring or a RegExp — the exact wording is allowed to be tuned,
// the shape of the answer is not.
const check = (label, status, want, reject) => cases.push({ label, status, want, reject });

const agents = (...rows) => rows.map(([name, state, lastMessage]) => ({ name, state, lastMessage: lastMessage || '' }));

// --- the four moments the demo actually goes through ---------------------------
check(
  'just started — both agents wake on the same beat',
  { status: 'running', agents: agents(['triage', 'working', 'waking up'], ['scheduler', 'working', 'waking up'], ['recap', 'idle', '']) },
  /Triage and Scheduler are both waking up\. Recap hasn't started yet\./
);

check(
  'mid-run — the answer A asked for',
  { status: 'running', agents: agents(['triage', 'working', 'Archiving six newsletters.'], ['scheduler', 'working', 'Booking two PM with David Chen.'], ['recap', 'idle', '']) },
  /^Triage is archiving six newsletters and Scheduler is booking two PM with David Chen\. Recap hasn't started yet\.$/
);

check(
  'one agent home early',
  { status: 'running', agents: agents(['triage', 'done', 'Done: inbox down to two real emails.'], ['scheduler', 'working', 'Booking two PM with David Chen.'], ['recap', 'idle', '']) },
  /^Scheduler is booking two PM with David Chen\. Triage is already finished and Recap hasn't started yet\.$/
);

check(
  'finished — recap closes the loop',
  { status: 'done', agents: agents(['triage', 'done', 'Done: inbox down to two real emails.'], ['scheduler', 'done', 'Done: two meetings on the calendar.'], ['recap', 'done', 'Done: inbox cleared, two meetings booked.']) },
  /^The crew is finished\. Inbox cleared, two meetings booked\.$/
);

// --- the edges that would embarrass us on stage --------------------------------
check(
  'asked before anyone woke up',
  { status: 'running', agents: agents(['triage', 'idle', ''], ['scheduler', 'idle', ''], ['recap', 'idle', '']) },
  /nobody has reported in yet/
);

check(
  'between phases — two signed off, recap not awake',
  { status: 'running', agents: agents(['triage', 'done', 'Done: inbox down to two real emails.'], ['scheduler', 'done', 'Done: two meetings on the calendar.'], ['recap', 'idle', '']) },
  /^The crew is still going\. Triage and Scheduler are already finished and Recap hasn't started yet\.$/
);

check(
  'every agent done but the orchestrator has not flipped status yet',
  { status: 'running', agents: agents(['triage', 'done', 'Done: nothing to archive.'], ['recap', 'done', 'Done: quiet morning.']) },
  /^The crew is finished\. Quiet morning\.$/
);

check(
  'an agent that ran out of time still gets reported honestly',
  { status: 'done', agents: agents(['triage', 'done', 'Done: ran out of time.'], ['recap', 'done', 'Done: triage timed out, nothing changed.']) },
  /^The crew is finished\. Triage timed out, nothing changed\.$/
);

check(
  'recap never got a line out — fall back to everyone else',
  { status: 'done', agents: agents(['triage', 'done', 'Done: inbox down to two real emails.'], ['recap', 'done', '']) },
  /^The crew is finished\. Inbox down to two real emails\.$/,
  /undefined|null/
);

// A's clarification to the frozen contract: only 'done' means finished. A state we
// have never seen must never be reported as the run being over.
check(
  'an unknown state counts as still running, never as finished',
  { status: 'running', agents: agents(['triage', 'thinking', 'Archiving six newsletters.'], ['recap', 'idle', '']) },
  /still going|hasn't started yet/,
  /finished\./
);

check(
  'a line that is not a gerund does not get mangled into "is David"',
  { status: 'running', agents: agents(['triage', 'working', 'David Chen wants a slot tomorrow.'], ['recap', 'idle', '']) },
  /Triage reports: David Chen wants a slot tomorrow/,
  /is david/i
);

check(
  '"Nothing left in the inbox" is not a verb',
  { status: 'running', agents: agents(['triage', 'working', 'Nothing left in the inbox.'], ['recap', 'idle', '']) },
  /Triage reports: Nothing left in the inbox/,
  /Triage is nothing/i
);

// A posts the last line twice — once as 'working', then as 'done'. Caught live:
// in that window the crew used to answer "Recap reports inbox cleared, two
// meetings booked", i.e. present tense about an agent that had already signed off.
check(
  'the double-post window: signed off in words, not yet in state',
  { status: 'running', agents: agents(['triage', 'done', 'Done: inbox down to two real emails.'], ['scheduler', 'done', 'Done: two meetings on the calendar.'], ['recap', 'working', 'Done: inbox cleared, two meetings booked.']) },
  /^The crew is finished\. Inbox cleared, two meetings booked\.$/,
  /reports/
);

check(
  'one agent signs off early, in words only',
  { status: 'running', agents: agents(['triage', 'working', 'Done: inbox down to two real emails.'], ['scheduler', 'working', 'Booking two PM with David Chen.'], ['recap', 'idle', '']) },
  /^Scheduler is booking two PM with David Chen\. Triage is already finished and Recap hasn't started yet\.$/
);

// A's roster is a table now and grows by a row (researcher, analyst, …). The
// bridge should need no edit for a member it has never heard of.
check(
  'a crew member this file has never heard of',
  { status: 'running', agents: agents(['researcher', 'working', 'Reading what the thread actually says.'], ['analyst', 'working', 'Lining the numbers up side by side.'], ['recap', 'idle', '']) },
  /^Researcher is reading what the thread actually says and Analyst is lining the numbers up side by side\. Recap hasn't started yet\.$/
);

// A's analyst really says this, and it is not a gerund — "Analyst is one of
// these is not like the others" is the failure it protects against.
check(
  "A's analyst line, which no \"<Name> is …\" frame fits",
  { status: 'running', agents: agents(['analyst', 'working', 'One of these is not like the others.'], ['recap', 'idle', '']) },
  /^Analyst reports: One of these is not like the others\. Recap hasn't started yet\.$/
);

check(
  'four working at once still reads as a list',
  { status: 'running', agents: agents(['triage', 'working', 'Scanning the inbox.'], ['scheduler', 'working', 'Finding open slots tomorrow.'], ['researcher', 'working', 'Reading the rollout notes.'], ['recap', 'idle', '']) },
  /^Triage is scanning the inbox, Scheduler is finding open slots tomorrow, and Researcher is reading the rollout notes\. Recap hasn't started yet\.$/
);

// The closer is whoever A put last, not whoever is called 'recap'.
check(
  'the closer is positional, not named',
  { status: 'done', agents: agents(['researcher', 'done', 'Done: three facts worth knowing.'], ['wrapup', 'done', 'Done: here is what we found.']) },
  /^The crew is finished\. Here is what we found\.$/
);

check('no agents at all', { status: 'running', agents: [] }, /just started/);
check('a garbage payload still says something sayable', {}, /just started/);

// --- run ------------------------------------------------------------------------
for (const c of cases) {
  let out;
  try {
    out = speakStatus(c.status);
  } catch (e) {
    console.log(`  FAIL  ${c.label}\n        threw: ${e.message}`);
    failed++;
    continue;
  }
  const bad =
    (c.want instanceof RegExp ? !c.want.test(out) : !String(out).includes(c.want)) ||
    (c.reject && c.reject.test(out));
  if (bad) {
    console.log(`  FAIL  ${c.label}\n        said: ${JSON.stringify(out)}\n        want: ${c.want}${c.reject ? `\n        not:  ${c.reject}` : ''}`);
    failed++;
  } else {
    console.log(`  ok    ${c.label}\n        ${JSON.stringify(out)}`);
  }
}

// Nothing VoiceOS reads aloud may contain JSON punctuation, a newline, or a
// bracketed state — that was the whole bug this file exists to prevent.
for (const c of cases) {
  const out = String(speakStatus(c.status));
  if (/[{}\[\]"]|\n|\(\w+\)/.test(out)) {
    console.log(`  FAIL  unspeakable characters in: ${JSON.stringify(out)}`);
    failed++;
  }
}

console.log(
  failed
    ? `\n${failed} failed — the crew would say something a person wouldn't.\n`
    : `\nPASS — ${cases.length} status replies, all of them sentences.\n`
);
process.exit(failed ? 1 : 0);

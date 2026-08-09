// Turn A's /status/:taskId JSON into one thing a person would say out loud.
//
// This is not formatting. VoiceOS reads a tool's reply back VERBATIM, so whatever
// comes out of here IS the crew's only spoken answer to "what are you doing?" —
// and the thing that tells the human the run is over. The previous reply was
//
//     Task task_1 is running.
//     triage (working): Archiving six newsletters.
//     scheduler (idle): —
//
// which read aloud is "triage open paren working close paren colon". Now:
//
//     Triage is archiving six newsletters and Scheduler is booking two PM with
//     David Chen. Recap hasn't started yet.
//
// No I/O in here on purpose — every branch is testable with no orchestrator, no
// VoiceOS and no network:  node test-status-speech.js
'use strict';

// The three roles are characters on screen, so they get proper names. That also
// keeps the grammar trivial: no "the scheduler" / "triage" article mismatch.
const NAMES = { triage: 'Triage', scheduler: 'Scheduler', recap: 'Recap' };
const label = (n) => NAMES[n] || (n ? String(n)[0].toUpperCase() + String(n).slice(1) : 'An agent');

// "Done: inbox down to two real emails." -> "inbox down to two real emails"
// The "Done:" marker is A's sign-off convention and the state field already
// carries that fact; spoken back it just sounds like the agent stuttering.
const plain = (msg) =>
  String(msg || '').trim().replace(/^Done:\s*/i, '').replace(/[.!\s]+$/, '').trim();

const lower1 = (s) => (s ? s[0].toLowerCase() + s.slice(1) : s);
const sentence = (s) => (s ? s[0].toUpperCase() + s.slice(1) + '.' : '');

// Every line the role prompts allow starts with a gerund ("Archiving six
// newsletters"), which is exactly what "<Name> is …" needs. Anything else keeps
// its capital and gets a frame that doesn't need one — lowercasing blindly turns
// "David Chen wants a slot" into "david Chen wants a slot".
const NOT_A_VERB = /^(nothing|something|anything|everything|morning|evening|during)$/i;
function isGerund(s) {
  const w = (String(s).match(/^([A-Za-z]+ing)\b/) || [])[1];
  return Boolean(w) && !NOT_A_VERB.test(w);
}

// "a" | "a and b" | "a, b, and c"
function join(parts) {
  if (parts.length <= 1) return parts[0] || '';
  if (parts.length === 2) return `${parts[0]} and ${parts[1]}`;
  return `${parts.slice(0, -1).join(', ')}, and ${parts[parts.length - 1]}`;
}

// What one agent is doing. No internal punctuation — these get joined into a list.
function clause(agent) {
  const name = label(agent.name);
  const msg = plain(agent.lastMessage);
  if (!msg) return `${name} is just starting`;
  return isGerund(msg) ? `${name} is ${lower1(msg)}` : `${name} reports ${msg}`;
}

// A posts an agent's final "Done:" line TWICE — once as working, then again as
// done, because the second one is the signal C's character stops animating on.
// Between the two the agent has plainly said its last word, so believe the line
// rather than the state; otherwise the crew answers "Recap reports inbox cleared,
// two meetings booked" about an agent that has already gone home. The orchestrator
// stops queueing after the first "Done:", so that prefix is terminal by construction.
const signedOff = (a) => a.state === 'done' || /^Done:/i.test(String(a?.lastMessage || '').trim());

// Recap's entire job is to close the loop, so its sign-off IS the summary of the
// run. Only fall back to reciting everyone's last line if it never got one out.
function closing(agents) {
  const recap = agents.find((a) => a.name === 'recap' && plain(a.lastMessage));
  if (recap) return sentence(plain(recap.lastMessage));
  const all = agents.map((a) => plain(a.lastMessage)).filter(Boolean);
  return all.length ? all.map(sentence).join(' ') : 'Nothing to report.';
}

/**
 * @param {{status?: string, agents?: Array<{name:string,state:string,lastMessage:string}>}} status
 * @returns {string} one or two spoken sentences
 */
function speakStatus(status) {
  const agents = Array.isArray(status?.agents) ? status.agents : [];
  // A's clarification to the frozen contract: an agent starts 'idle', and only
  // 'done' means finished — treat anything else as still running. So the split is
  // on *evidence*, not on the spelling of the state: an agent that has said
  // something is doing something, whatever its state is called. A state we have
  // never seen must never be reported as the run being over.
  const done = agents.filter(signedOff);
  const active = agents.filter((a) => !signedOff(a) && plain(a.lastMessage));
  const waiting = agents.filter((a) => !signedOff(a) && !plain(a.lastMessage));

  const finished = status?.status === 'done' || (agents.length > 0 && done.length === agents.length);
  if (finished) return `The crew is finished. ${closing(agents)}`;

  if (!agents.length) return 'The crew has just started — nobody has reported in yet.';
  if (!active.length && !done.length) return 'The crew is just waking up — nobody has reported in yet.';

  const now = [];
  if (active.length) {
    // Both agents wake on the same beat and say the same thing, so without this
    // every run opens with "Triage is waking up and Scheduler is waking up".
    const msgs = active.map((a) => plain(a.lastMessage));
    const shared = msgs.every((m) => m === msgs[0]) && isGerund(msgs[0]);
    now.push(
      shared && active.length > 1
        ? `${join(active.map((a) => label(a.name)))} are ${active.length === 2 ? 'both' : 'all'} ${lower1(msgs[0])}.`
        : `${join(active.map(clause))}.`
    );
  } else {
    // Between phases: the first two have signed off and recap hasn't woken yet.
    now.push('The crew is still going.');
  }

  const tail = [];
  if (done.length) {
    tail.push(`${join(done.map((a) => label(a.name)))} ${done.length > 1 ? 'are' : 'is'} already finished`);
  }
  if (waiting.length) {
    tail.push(`${join(waiting.map((a) => label(a.name)))} ${waiting.length > 1 ? "haven't" : "hasn't"} started yet`);
  }
  if (tail.length) now.push(sentence(join(tail)));

  return now.join(' ');
}

module.exports = { speakStatus, plain, isGerund, join, label };

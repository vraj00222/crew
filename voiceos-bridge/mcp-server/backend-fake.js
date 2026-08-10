// Fake Gmail/Calendar backend, seeded from demo-seed/fixtures.json.
//
// Why this exists: the real backend needs a demo Google account and OAuth
// credentials that did not exist when the tools were written. Same trick that
// worked for the orchestrator — build against a stub, swap it later. It also
// makes CREW_BACKEND=fake a genuine panic button: the inbox half of the demo
// works with no network, no account and no Claude spend.
//
// State persists to disk because VoiceOS spawns the MCP server as a subprocess
// and may respawn it between calls. In memory only, "archive" would silently
// undo itself between two agent steps.

const { readFileSync, writeFileSync, existsSync } = require('node:fs');
const { join } = require('node:path');

const FIXTURES = join(__dirname, '..', 'demo-seed', 'fixtures.json');
const STATE = process.env.CREW_STATE || join(__dirname, '.crew-mailbox.json');

const NEWSLETTER_HINTS = /newsletter|unsubscribe|digest|daily|weekly/i;

function seed() {
  const fx = JSON.parse(readFileSync(FIXTURES, 'utf8'));
  const now = Date.now();
  return {
    seededAt: new Date().toISOString(),
    messages: fx.emails.map((e) => ({
      id: e.id,
      from: `${e.from_name} <${e.from_email}>`,
      fromName: e.from_name,
      subject: e.subject,
      category: e.category,
      receivedAt: new Date(now - e.hours_ago * 3600_000).toISOString(),
      inInbox: true,
      unread: true,
      labels: [].concat(e.important ? ['IMPORTANT'] : [], e.starred ? ['STARRED'] : []),
      snippet: String(e.body).split('\n')[0].slice(0, 120),
    })),
    // Calendar fixtures use days_ahead + HH:MM local; resolve once, at seed time.
    events: fx.calendar.map((c) => {
      const d = new Date();
      d.setDate(d.getDate() + c.days_ahead);
      const [sh, sm] = c.start.split(':').map(Number);
      const [eh, em] = c.end.split(':').map(Number);
      const start = new Date(d); start.setHours(sh, sm, 0, 0);
      const end = new Date(d); end.setHours(eh, em, 0, 0);
      return { id: c.id, summary: c.summary, start: start.toISOString(), end: end.toISOString(), seeded: true };
    }),
  };
}

function load() {
  if (!existsSync(STATE)) {
    const fresh = seed();
    writeFileSync(STATE, JSON.stringify(fresh, null, 2));
    return fresh;
  }
  return JSON.parse(readFileSync(STATE, 'utf8'));
}

const save = (db) => writeFileSync(STATE, JSON.stringify(db, null, 2));

// Deliberately loose: the agents phrase queries in English, not Gmail syntax.
// "all newsletters", "newsletters in my inbox" and "category:newsletter" all work.
function matches(msg, query) {
  if (!query || !query.trim()) return true;
  const q = query.toLowerCase();

  // Category first, and ONLY category when the message has one. The fixture labels
  // every message, so the word-sniffing fallback below is pure downside here: it
  // caught Calendly's "your *weekly* availability" as a newsletter and archived 7
  // where the character says six. Heuristics are for data we didn't author.
  const byCategory = {
    newsletter: 'newsletter',
    noise: 'noise', promo: 'noise', receipt: 'noise', notification: 'noise',
    travel: 'travel', flight: 'travel', trip: 'travel',
    meeting: 'meeting-request', invite: 'meeting-request', schedul: 'meeting-request',
    reply: 'needs-reply',
  };
  for (const [word, category] of Object.entries(byCategory)) {
    if (q.includes(word)) {
      if (msg.category) return msg.category === category;
      return category === 'newsletter' ? NEWSLETTER_HINTS.test(`${msg.subject} ${msg.snippet}`) : false;
    }
  }
  if (/unread/.test(q)) return msg.unread;
  const hay = `${msg.fromName} ${msg.from} ${msg.subject} ${msg.snippet} ${msg.category}`.toLowerCase();
  return q.split(/\s+/).filter(Boolean).every((term) => hay.includes(term));
}

const overlaps = (aS, aE, bS, bE) => aS < bE && bS < aE;

module.exports = {
  name: 'fake',

  reset() {
    const fresh = seed();
    save(fresh);
    return { ok: true, messages: fresh.messages.length, events: fresh.events.length };
  },

  listInbox({ query, limit = 25 } = {}) {
    const db = load();
    const msgs = db.messages
      .filter((m) => m.inInbox && matches(m, query))
      .sort((a, b) => b.receivedAt.localeCompare(a.receivedAt))
      .slice(0, limit);
    return {
      total: db.messages.filter((m) => m.inInbox).length,
      matched: msgs.length,
      messages: msgs.map((m) => ({
        id: m.id, from: m.fromName, subject: m.subject,
        category: m.category, unread: m.unread, labels: m.labels,
      })),
    };
  },

  archive({ query, ids } = {}) {
    const db = load();
    const targets = ids?.length
      ? db.messages.filter((m) => ids.includes(m.id) && m.inInbox)
      : db.messages.filter((m) => m.inInbox && matches(m, query));
    for (const m of targets) { m.inInbox = false; m.unread = false; }
    save(db);
    return {
      archived: targets.length,
      subjects: targets.map((m) => m.subject),
      remainingInInbox: db.messages.filter((m) => m.inInbox).length,
    };
  },

  label({ ids, query, label } = {}) {
    const db = load();
    const targets = ids?.length
      ? db.messages.filter((m) => ids.includes(m.id))
      : db.messages.filter((m) => matches(m, query));
    for (const m of targets) if (!m.labels.includes(label)) m.labels.push(label);
    save(db);
    return { labelled: targets.length, label, subjects: targets.map((m) => m.subject) };
  },

  // Walks 30-min boundaries inside working hours and returns the first gap that
  // fits. The fixture leaves tomorrow 14:00 free on purpose — that is the line
  // the whole demo exists to produce.
  findSlot({ durationMin = 60, afterISO, dayOffset = 1, workStart = 9, workEnd = 18 } = {}) {
    const db = load();
    const day = new Date();
    day.setDate(day.getDate() + dayOffset);
    day.setHours(workStart, 0, 0, 0);
    const dayEnd = new Date(day); dayEnd.setHours(workEnd, 0, 0, 0);
    const floor = afterISO ? new Date(afterISO) : day;

    for (let t = new Date(Math.max(day, floor)); t < dayEnd; t = new Date(+t + 30 * 60_000)) {
      const end = new Date(+t + durationMin * 60_000);
      if (end > dayEnd) break;
      const clash = db.events.find((e) => overlaps(+t, +end, +new Date(e.start), +new Date(e.end)));
      if (!clash) {
        return { found: true, start: t.toISOString(), end: end.toISOString(), durationMin };
      }
    }
    return { found: false, reason: `No ${durationMin}-minute gap on that day between ${workStart}:00 and ${workEnd}:00.` };
  },

  book({ summary, startISO, endISO, durationMin = 60, attendee } = {}) {
    const db = load();
    const start = new Date(startISO);
    const end = endISO ? new Date(endISO) : new Date(+start + durationMin * 60_000);
    const clash = db.events.find((e) => overlaps(+start, +end, +new Date(e.start), +new Date(e.end)));
    if (clash) return { booked: false, reason: `That slot collides with "${clash.summary}".` };

    const ev = {
      id: `crew-${Date.now().toString(36)}`,
      summary, attendee,
      start: start.toISOString(), end: end.toISOString(),
      createdByCrew: true,
    };
    db.events.push(ev);
    save(db);
    return { booked: true, event: ev };
  },

  // CREW_REAL_CALENDAR=1 reads the MAC's actual calendar instead of the fixture,
  // via AppleScript. The fixture exists so the demo runs anywhere with no
  // account; this exists so it can be real when someone asks about THEIR week and
  // wants to see their own events on screen.
  //
  // ~9s on this machine — Calendar.app scripting is slow and there is nothing to
  // be done about that, so it is opt-in rather than the default.
  realEvents(days = 7) {
    const { execFileSync } = require('node:child_process');
    // ONE whose-clause, not nested repeats. The loop version walked every event
    // of every calendar in AppleScript and timed out at 30s; this is the same
    // question asked in a form Calendar.app can answer in about nine.
    const q = (what) =>
      `tell application "Calendar" to get ${what} of every event of every calendar `
      + `whose start date > (current date) and start date < ((current date) + ${days} * days)`;
    const run = (what) => execFileSync('osascript', ['-e', q(what)],
      { encoding: 'utf8', timeout: 60000 }).trim();
    // Summaries only. AppleScript returns a comma-joined list and its dates
    // contain commas of their own ("date Tuesday, August 11, 2026 at 5:30 PM"),
    // so pairing the two lists by index silently mismatched them. The names are
    // what a person asked for; a wrong time is worse than no time.
    return run('summary').split(', ')
      .map((x) => x.trim())
      .filter((x) => x && x !== ',')
      .map((summary) => ({ summary, createdByCrew: false }));
  },

  listEvents({ dayOffset = 1 } = {}) {
    if (process.env.CREW_REAL_CALENDAR === '1') {
      try {
        const events = this.realEvents(Number(process.env.CREW_CALENDAR_DAYS || 7));
        return { source: 'your real calendar', count: events.length, events };
      } catch (e) {
        // Never fail the run over this — fall through to the fixture and say so.
        return { source: 'fixture (real calendar unreadable: ' + e.message.slice(0, 60) + ')',
                 ...this._fixtureEvents({ dayOffset }) };
      }
    }
    return this._fixtureEvents({ dayOffset });
  },

  _fixtureEvents({ dayOffset = 1 } = {}) {
    const db = load();
    const day = new Date();
    day.setDate(day.getDate() + dayOffset);
    const key = day.toDateString();
    return {
      day: key,
      events: db.events
        .filter((e) => new Date(e.start).toDateString() === key)
        .sort((a, b) => a.start.localeCompare(b.start))
        .map((e) => ({ summary: e.summary, start: e.start, end: e.end, createdByCrew: !!e.createdByCrew })),
    };
  },
};

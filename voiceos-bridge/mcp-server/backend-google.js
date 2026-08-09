// Real Gmail/Calendar backend. Raw REST over fetch — no googleapis dependency,
// so the MCP server still has nothing to `npm install` on the demo machine.
//
// Reads the SAME token.json that demo-seed/seed.py writes, so authorising once
// for seeding also authorises the tools. If it isn't there, run:
//     cd voiceos-bridge/demo-seed && uv run seed.py
//
// Category queries ("newsletters") are resolved against fixtures.json rather than
// guessed from Gmail search syntax — we know exactly which senders we seeded, so
// `from:(a OR b OR ...)` is deterministic where `category:promotions` is a coin flip.

const { readFileSync, existsSync, writeFileSync } = require('node:fs');
const { join } = require('node:path');

const TOKEN = process.env.CREW_TOKEN || join(__dirname, '..', 'demo-seed', 'token.json');
const FIXTURES = join(__dirname, '..', 'demo-seed', 'fixtures.json');
const GMAIL = 'https://gmail.googleapis.com/gmail/v1/users/me';
const CAL = 'https://www.googleapis.com/calendar/v3/calendars/primary';

let cached = { access: null, expires: 0 };

function tokenFile() {
  if (!existsSync(TOKEN)) {
    throw new Error(
      `No Google token at ${TOKEN}. Authorise once with: cd voiceos-bridge/demo-seed && uv run seed.py`
    );
  }
  return JSON.parse(readFileSync(TOKEN, 'utf8'));
}

async function accessToken() {
  if (cached.access && Date.now() < cached.expires - 60_000) return cached.access;
  const t = tokenFile();
  const res = await fetch(t.token_uri || 'https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: t.client_id,
      client_secret: t.client_secret,
      refresh_token: t.refresh_token,
      grant_type: 'refresh_token',
    }),
  });
  const j = await res.json();
  if (!res.ok) throw new Error(`Token refresh failed: ${j.error_description || j.error || res.status}`);
  cached = { access: j.access_token, expires: Date.now() + (j.expires_in || 3600) * 1000 };
  return cached.access;
}

async function api(url, init = {}) {
  const token = await accessToken();
  const res = await fetch(url, {
    ...init,
    headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json', ...(init.headers || {}) },
  });
  const body = await res.text();
  const json = body ? JSON.parse(body) : {};
  if (!res.ok) throw new Error(`${res.status} ${json.error?.message || body.slice(0, 200)}`);
  return json;
}

const fixtures = () => JSON.parse(readFileSync(FIXTURES, 'utf8'));

function sendersFor(category) {
  return fixtures().emails.filter((e) => e.category === category).map((e) => e.from_email);
}

// English -> Gmail search. Anything we don't recognise is passed through, so a
// real Gmail query still works if an agent happens to emit one.
function toGmailQuery(query) {
  const q = (query || '').toLowerCase();
  const byCategory = (cat) => {
    const from = sendersFor(cat);
    return from.length ? `in:inbox from:(${from.join(' OR ')})` : 'in:inbox';
  };
  if (/newsletter/.test(q)) return byCategory('newsletter');
  if (/noise|promo|receipt|notification/.test(q)) return byCategory('noise');
  if (/travel|flight|trip/.test(q)) return byCategory('travel');
  if (/meeting|invite|schedul/.test(q)) return byCategory('meeting-request');
  if (!q.trim()) return 'in:inbox';
  return q.includes(':') ? query : `in:inbox ${query}`;
}

const header = (msg, name) =>
  msg.payload?.headers?.find((h) => h.name.toLowerCase() === name)?.value || '';

async function hydrate(ids) {
  // Sequential on purpose: ~18 messages, and a burst of parallel requests is the
  // fastest way to eat a 429 in front of an audience.
  const out = [];
  for (const id of ids) {
    const m = await api(
      `${GMAIL}/messages/${id}?format=metadata&metadataHeaders=From&metadataHeaders=Subject`
    );
    out.push({
      id,
      from: header(m, 'from'),
      subject: header(m, 'subject'),
      unread: (m.labelIds || []).includes('UNREAD'),
      labels: (m.labelIds || []).filter((l) => !['INBOX', 'UNREAD'].includes(l)),
    });
  }
  return out;
}

async function idsFor(query, limit) {
  const r = await api(`${GMAIL}/messages?q=${encodeURIComponent(toGmailQuery(query))}&maxResults=${limit}`);
  return (r.messages || []).map((m) => m.id);
}

const overlaps = (aS, aE, bS, bE) => aS < bE && bS < aE;

async function eventsOn(dayOffset) {
  const day = new Date();
  day.setDate(day.getDate() + dayOffset);
  const min = new Date(day); min.setHours(0, 0, 0, 0);
  const max = new Date(day); max.setHours(23, 59, 59, 999);
  const r = await api(
    `${CAL}/events?timeMin=${min.toISOString()}&timeMax=${max.toISOString()}&singleEvents=true&orderBy=startTime`
  );
  return (r.items || []).filter((e) => e.start?.dateTime);
}

module.exports = {
  name: 'google',

  reset() {
    // Reseeding real Gmail is demo-seed's job, not a tool the agents can reach.
    return { ok: false, reason: 'Reset is not available on the google backend. Use: uv run seed.py' };
  },

  async listInbox({ query, limit = 25 } = {}) {
    const ids = await idsFor(query, limit);
    const messages = await hydrate(ids);
    const all = await api(`${GMAIL}/messages?q=in:inbox&maxResults=100`);
    return { total: (all.messages || []).length, matched: messages.length, messages };
  },

  async archive({ query, ids } = {}) {
    const targets = ids?.length ? ids : await idsFor(query, 100);
    if (!targets.length) return { archived: 0, subjects: [], remainingInInbox: null };
    const detail = await hydrate(targets);
    // Archive = drop the INBOX label. Nothing is deleted; this is reversible.
    await api(`${GMAIL}/messages/batchModify`, {
      method: 'POST',
      body: JSON.stringify({ ids: targets, removeLabelIds: ['INBOX', 'UNREAD'] }),
    });
    const left = await api(`${GMAIL}/messages?q=in:inbox&maxResults=100`);
    return {
      archived: targets.length,
      subjects: detail.map((m) => m.subject),
      remainingInInbox: (left.messages || []).length,
    };
  },

  async label({ ids, query, label } = {}) {
    const targets = ids?.length ? ids : await idsFor(query, 100);
    if (!targets.length) return { labelled: 0, label, subjects: [] };
    const existing = await api(`${GMAIL}/labels`);
    let found = (existing.labels || []).find((l) => l.name === label);
    if (!found) {
      found = await api(`${GMAIL}/labels`, {
        method: 'POST',
        body: JSON.stringify({ name: label, labelListVisibility: 'labelShow', messageListVisibility: 'show' }),
      });
    }
    const detail = await hydrate(targets);
    await api(`${GMAIL}/messages/batchModify`, {
      method: 'POST',
      body: JSON.stringify({ ids: targets, addLabelIds: [found.id] }),
    });
    return { labelled: targets.length, label, subjects: detail.map((m) => m.subject) };
  },

  async findSlot({ durationMin = 60, afterISO, dayOffset = 1, workStart = 9, workEnd = 18 } = {}) {
    const busy = await eventsOn(dayOffset);
    const day = new Date();
    day.setDate(day.getDate() + dayOffset);
    day.setHours(workStart, 0, 0, 0);
    const dayEnd = new Date(day); dayEnd.setHours(workEnd, 0, 0, 0);
    const floor = afterISO ? new Date(afterISO) : day;

    for (let t = new Date(Math.max(day, floor)); t < dayEnd; t = new Date(+t + 30 * 60_000)) {
      const end = new Date(+t + durationMin * 60_000);
      if (end > dayEnd) break;
      const clash = busy.find((e) =>
        overlaps(+t, +end, +new Date(e.start.dateTime), +new Date(e.end.dateTime))
      );
      if (!clash) return { found: true, start: t.toISOString(), end: end.toISOString(), durationMin };
    }
    return { found: false, reason: `No ${durationMin}-minute gap between ${workStart}:00 and ${workEnd}:00.` };
  },

  async book({ summary, startISO, endISO, durationMin = 60, attendee } = {}) {
    const start = new Date(startISO);
    const end = endISO ? new Date(endISO) : new Date(+start + durationMin * 60_000);
    const body = {
      summary,
      start: { dateTime: start.toISOString() },
      end: { dateTime: end.toISOString() },
      extendedProperties: { private: { crewDemoSeed: '1' } },
    };
    // No `attendees` on purpose: adding one makes Google email a real person.
    if (attendee) body.description = `Requested by ${attendee} (Crew demo — no invite sent).`;
    const ev = await api(`${CAL}/events`, { method: 'POST', body: JSON.stringify(body) });
    return {
      booked: true,
      event: { id: ev.id, summary: ev.summary, start: ev.start.dateTime, end: ev.end.dateTime, attendee },
    };
  },

  async listEvents({ dayOffset = 1 } = {}) {
    const items = await eventsOn(dayOffset);
    const day = new Date();
    day.setDate(day.getDate() + dayOffset);
    return {
      day: day.toDateString(),
      events: items.map((e) => ({
        summary: e.summary,
        start: e.start.dateTime,
        end: e.end.dateTime,
        createdByCrew: e.extendedProperties?.private?.crewDemoSeed === '1',
      })),
    };
  },
};

#!/usr/bin/env node
// Drives the ACTUAL demo through the MCP tools over real stdio, and checks that the
// numbers the characters say out loud are the numbers the mailbox really ends up with.
//
//   node test-demo-flow.js            (fake backend — no account, no network)
//   CREW_BACKEND=google node test-demo-flow.js   (real demo account; reseed first)
//
// The assertions are the demo script:
//   "Archiving six newsletters."          -> exactly 6 archived
//   "Booking two PM with David Chen."     -> 14:00 tomorrow, and it was actually free
//   "Done: inbox down to two real emails." -> exactly 2 left

const { spawn } = require('node:child_process');
const { join } = require('node:path');
const { rmSync } = require('node:fs');

const BACKEND = process.env.CREW_BACKEND === 'google' ? 'google' : 'fake';
if (BACKEND === 'fake') rmSync(join(__dirname, '.crew-mailbox.json'), { force: true }); // fresh seed

const child = spawn(process.execPath, [join(__dirname, 'server.js')], {
  stdio: ['pipe', 'pipe', 'pipe'],
  env: { ...process.env, CREW_BACKEND: BACKEND },
});

let buf = '', stderrOut = '', id = 0;
const waiters = new Map();
child.stdout.setEncoding('utf8');
child.stdout.on('data', (c) => {
  buf += c;
  const lines = buf.split('\n');
  buf = lines.pop();
  for (const line of lines) {
    if (!line.trim()) continue;
    try {
      const m = JSON.parse(line);
      const w = waiters.get(m.id);
      if (w) (waiters.delete(m.id), w(m));
    } catch { /* non-JSON on stdout is caught by test-stdio.js */ }
  }
});
child.stderr.on('data', (d) => (stderrOut += d));

const fail = (m) => {
  console.error(`\nFAIL: ${m}\n\n--- server stderr ---\n${stderrOut}`);
  child.kill();
  process.exit(1);
};

function rpc(method, params) {
  const myId = ++id;
  return new Promise((resolve, reject) => {
    waiters.set(myId, resolve);
    child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id: myId, method, params }) + '\n');
    setTimeout(() => (waiters.has(myId) ? reject(new Error(`timeout on ${method}`)) : 0), 30000);
  });
}

async function call(name, args) {
  const r = await rpc('tools/call', { name, arguments: args });
  if (r.error) fail(`${name}: ${JSON.stringify(r.error)}`);
  const body = r.result.content[0].text;
  if (r.result.isError) fail(`${name} returned an error: ${body}`);
  if (r.result.structuredContent) return r.result.structuredContent;
  try { return JSON.parse(body); } catch { return body; }
}

const eq = (actual, expected, what) => {
  if (actual !== expected) fail(`${what}: expected ${expected}, got ${actual}`);
  console.log(`  ok  ${what} = ${actual}`);
};

(async () => {
  console.log(`\nDemo flow against the ${BACKEND} backend\n`);
  await rpc('initialize', { protocolVersion: '2025-06-18', clientInfo: { name: 'demo-flow', version: '1' } });
  child.stdin.write(JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }) + '\n');

  // --- what the audience sees before anyone speaks ---
  const before = await call('crew_gmail_list_inbox', {});
  eq(before.total, 18, 'inbox at curtain-up');

  // --- TRIAGE: "Archiving six newsletters." ---
  const news = await call('crew_gmail_list_inbox', { query: 'newsletters' });
  eq(news.matched, 6, 'newsletters found');
  const archived = await call('crew_gmail_archive', { query: 'newsletters' });
  eq(archived.archived, 6, 'newsletters archived');

  const noise = await call('crew_gmail_archive', { query: 'noise' });
  const travel = await call('crew_gmail_archive', { query: 'travel' });
  eq(noise.archived + travel.archived, 8, 'noise + travel archived');

  // --- TRIAGE: "Flagging two emails that need replies." ---
  const flagged = await call('crew_gmail_label', { query: 'needs-reply', label: 'Needs reply' });
  eq(flagged.labelled, 2, 'flagged for reply');

  // --- SCHEDULER: the line the whole demo exists to produce ---
  const slot = await call('crew_calendar_find_slot', { durationMin: 60, dayOffset: 1, afterISO: tomorrowAt(13) });
  if (!slot.found) fail(`no slot found tomorrow afternoon: ${slot.reason}`);
  const hour = new Date(slot.start).getHours();
  eq(hour, 14, 'first free afternoon hour tomorrow');

  const booked = await call('crew_calendar_book', {
    summary: 'Q3 rollout sync', startISO: slot.start, durationMin: 60, attendee: 'David Chen',
  });
  if (!booked.booked) fail(`booking refused: ${booked.reason}`);
  console.log(`  ok  booked "${booked.event.summary}" with ${booked.event.attendee}`);

  // Priya's 30 minutes, the morning after.
  const slot2 = await call('crew_calendar_find_slot', { durationMin: 30, dayOffset: 2 });
  if (!slot2.found) fail(`no slot for Priya: ${slot2.reason}`);
  const b2 = await call('crew_calendar_book', {
    summary: 'Contract review', startISO: slot2.start, durationMin: 30, attendee: 'Priya Nair',
  });
  if (!b2.booked) fail(`Priya booking refused: ${b2.reason}`);
  console.log(`  ok  booked "${b2.event.summary}" with ${b2.event.attendee}`);

  // A booked request is a handled request — it leaves the inbox. Without this the
  // inbox ends on 4, and "down to two real emails" is false on stage.
  const handled = await call('crew_gmail_archive', { query: 'meeting requests' });
  eq(handled.archived, 2, 'handled meeting requests archived');

  // --- "Done: inbox down to two real emails." / "two meetings on the calendar." ---
  const after = await call('crew_gmail_list_inbox', {});
  eq(after.total, 2, 'inbox at curtain-down');
  const left = after.messages.map((m) => m.subject).sort();
  console.log(`  ok  what survived: ${JSON.stringify(left)}`);

  const day = await call('crew_calendar_list', { dayOffset: 1 });
  const crewEvents = day.events.filter((e) => e.createdByCrew);
  eq(crewEvents.length, 1, 'crew-created events tomorrow');

  // Booking must not have landed on top of something already there.
  const clash = day.events.find(
    (e) => !e.createdByCrew && new Date(e.start) < new Date(booked.event.end) && new Date(booked.event.start) < new Date(e.end)
  );
  if (clash) fail(`booked over an existing meeting: "${clash.summary}"`);
  console.log(`  ok  did not double-book (${day.events.length} events tomorrow)`);

  console.log(`\nPASS — every number the characters say out loud is true of the real mailbox.`);
  child.stdin.end();
  process.exit(0);
})().catch((e) => fail(e.message));

function tomorrowAt(h) {
  const d = new Date();
  d.setDate(d.getDate() + 1);
  d.setHours(h, 0, 0, 0);
  return d.toISOString();
}

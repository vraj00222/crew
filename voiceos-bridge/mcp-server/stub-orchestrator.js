#!/usr/bin/env node
// Stub of A's orchestrator (Interface 1) so B can build and test without waiting.
// Same HTTP contract as orchestrator/server.js, but it spawns nothing.
//   node stub-orchestrator.js
// Every received body is printed loudly — this is how we prove what VoiceOS sent.
// GET /status/:id walks a scripted run: waking up -> working -> one done -> recap
// -> finished, one phase per call. Ask it five times and you have seen a whole run.

const http = require('node:http');

const PORT = Number(process.env.PORT || 4001);
const tasks = new Map();
let seq = 0;

// A whole run, in A's exact shape, one phase per /status call. The demo is a loop —
// the human asks "what are they doing?" more than once and has to hear it change,
// and eventually hear that it finished. Polling drives it rather than a timer so a
// test gets the same four answers every time, and so does a human with curl.
const A = (name, state, lastMessage) => ({ name, state, lastMessage });
const PHASES = [
  { status: 'running', agents: [A('triage', 'working', 'waking up'), A('scheduler', 'working', 'waking up'), A('recap', 'idle', '')] },
  { status: 'running', agents: [A('triage', 'working', 'Archiving six newsletters.'), A('scheduler', 'working', 'Booking two PM with David Chen.'), A('recap', 'idle', '')] },
  { status: 'running', agents: [A('triage', 'done', 'Done: inbox down to two real emails.'), A('scheduler', 'working', 'Booking two PM with David Chen.'), A('recap', 'idle', '')] },
  { status: 'running', agents: [A('triage', 'done', 'Done: inbox down to two real emails.'), A('scheduler', 'done', 'Done: two meetings on the calendar.'), A('recap', 'working', 'Pulling together what the crew did.')] },
  { status: 'done', agents: [A('triage', 'done', 'Done: inbox down to two real emails.'), A('scheduler', 'done', 'Done: two meetings on the calendar.'), A('recap', 'done', 'Done: inbox cleared, two meetings booked.')] },
];

const send = (res, code, obj) => {
  res.writeHead(code, { 'content-type': 'application/json' });
  res.end(JSON.stringify(obj));
};

http
  .createServer((req, res) => {
    const url = new URL(req.url, 'http://localhost');

    if (req.method === 'POST' && url.pathname === '/start-task') {
      let body = '';
      req.on('data', (d) => (body += d));
      req.on('end', () => {
        let instructions;
        try {
          instructions = JSON.parse(body).instructions;
        } catch {}
        if (typeof instructions !== 'string' || !instructions.trim()) {
          console.log(`\n  !! BAD BODY: ${body}\n`);
          return send(res, 400, { error: 'instructions (string) required' });
        }
        const taskId = `task_${++seq}`;
        tasks.set(taskId, { instructions, polls: 0 });
        console.log(`\n${'='.repeat(64)}`);
        console.log(`  STUB ORCHESTRATOR RECEIVED  ${taskId}`);
        console.log(`  instructions: ${JSON.stringify(instructions)}`);
        console.log(`${'='.repeat(64)}\n`);
        send(res, 200, { taskId, status: 'started' });
      });
      return;
    }

    const m = url.pathname.match(/^\/status\/(.+)$/);
    if (req.method === 'GET' && m) {
      const task = tasks.get(m[1]);
      if (task === undefined) return send(res, 404, { error: 'unknown taskId' });
      // Advance one phase per call and stay on the last one, so repeated asking
      // ends at "done" instead of looping back to the start.
      const phase = PHASES[Math.min(task.polls++, PHASES.length - 1)];
      console.log(`  status ${m[1]} -> phase ${Math.min(task.polls, PHASES.length)}/${PHASES.length} (${phase.status})`);
      return send(res, 200, { taskId: m[1], ...phase });
    }

    send(res, 404, { error: 'not found' });
  })
  .listen(PORT, () => console.log(`stub orchestrator on :${PORT} — waiting for /start-task`));

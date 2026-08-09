#!/usr/bin/env node
// Stub of A's orchestrator (Interface 1) so B can build and test without waiting.
// Same HTTP contract as orchestrator/server.js, but it spawns nothing.
//   node stub-orchestrator.js
// Every received body is printed loudly — this is how we prove what VoiceOS sent.

const http = require('node:http');

const PORT = Number(process.env.PORT || 4001);
const tasks = new Map();
let seq = 0;

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
        tasks.set(taskId, instructions);
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
      const instructions = tasks.get(m[1]);
      if (instructions === undefined) return send(res, 404, { error: 'unknown taskId' });
      // Canned agents in A's exact shape, including the 'idle' state A flagged.
      return send(res, 200, {
        taskId: m[1],
        status: 'running',
        agents: [
          { name: 'triage', state: 'working', lastMessage: 'Archiving six newsletters.' },
          { name: 'scheduler', state: 'working', lastMessage: 'Booking two PM with David Chen.' },
          { name: 'recap', state: 'idle', lastMessage: '' },
        ],
      });
    }

    send(res, 404, { error: 'not found' });
  })
  .listen(PORT, () => console.log(`stub orchestrator on :${PORT} — waiting for /start-task`));

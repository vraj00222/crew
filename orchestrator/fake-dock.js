#!/usr/bin/env node
// Stand-in for C's Swift listener on :4002. Prints whatever the orchestrator pushes.
require('node:http').createServer((req, res) => {
  let body = '';
  req.on('data', (d) => (body += d));
  req.on('end', () => {
    console.log(`DOCK <- ${body}`);
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end('{"ok":true}');
  });
}).listen(4002, () => console.log('fake dock on :4002'));

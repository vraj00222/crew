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
})
  // The real dock owns :4002 too. Without this, a running Crew.app makes the
  // smoke test fail as "nothing reached the dock" — which reads as a broken
  // orchestrator when it is just the port already being served correctly.
  .on('error', (e) => {
    console.error(e.code === 'EADDRINUSE'
      ? 'fake dock: :4002 is taken — the real Crew.app is probably running.\n'
      + '  ./run-demo.sh stop   (then re-run this)'
      : `fake dock: ${e.message}`);
    process.exit(1);
  })
  .listen(4002, () => console.log('fake dock on :4002'));

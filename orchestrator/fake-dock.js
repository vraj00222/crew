#!/usr/bin/env node
// Stand-in for C's Swift listener. Prints whatever the orchestrator pushes.
const PORT = Number(process.env.DOCK_PORT || 4002);
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
  // Own port by default so the smoke test never poisons the real dock's.
  // Node leaves accepted connections in TIME_WAIT on 4002, and Network.framework
  // (the Swift dock) cannot bind over another process's TIME_WAIT sockets — so
  // running the test used to make the next real dock fail with EADDRINUSE while
  // nothing was listening at all. Set DOCK_PORT=4002 to stand in for real.
  .listen(PORT, () => console.log(`fake dock on :${PORT}`));

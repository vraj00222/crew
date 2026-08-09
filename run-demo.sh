#!/bin/bash
# The whole demo, one command. This is what gets run on stage.
#   ./run-demo.sh          real agents (headless claude), ~30s
#   ./run-demo.sh fake     canned narration, no Claude calls  <- PANIC BUTTON
#   ./run-demo.sh stop     kill everything
set -uo pipefail
cd "$(dirname "$0")"
PHRASE="clean up my inbox and schedule everything"

stop() {
  pkill -f "Crew.app/Contents/MacOS/Crew" 2>/dev/null
  pkill -f "orchestrator/server.js" 2>/dev/null
  pkill -f "node server.js" 2>/dev/null
  sleep 1
}

[ "${1:-}" = stop ] && { stop; echo "stopped."; exit 0; }

FAKE=""
[ "${1:-}" = fake ] && FAKE="FAKE=1"

stop
[ -x crew-dock/Crew.app/Contents/MacOS/Crew ] || { echo "building dock..."; ./crew-dock/build.sh >/dev/null; }

open crew-dock/Crew.app
sleep 2
pgrep -f "Crew.app/Contents/MacOS/Crew" >/dev/null || { echo "dock failed to start"; exit 1; }
echo "dock up on :4002"

env $FAKE node orchestrator/server.js > /tmp/crew-orchestrator.log 2>&1 &
for _ in $(seq 1 20); do
  curl -sf -o /dev/null localhost:4001/status/x && break
  curl -s -o /dev/null -w '' localhost:4001/status/x 2>/dev/null && break
  sleep 0.3
done
echo "orchestrator up on :4001 ${FAKE:+(FAKE MODE)}"
echo

ID=$(curl -sf -X POST localhost:4001/start-task -H 'content-type: application/json' \
  -d "{\"instructions\":\"$PHRASE\"}" | node -pe 'JSON.parse(require("fs").readFileSync(0)).taskId')
echo "\"$PHRASE\" -> $ID"
echo "watch the dock. narration below:"
echo

tail -f /tmp/crew-orchestrator.log &
TAIL=$!
for _ in $(seq 1 120); do
  S=$(curl -sf "localhost:4001/status/$ID" 2>/dev/null) || continue
  [ "$(echo "$S" | node -pe 'JSON.parse(require("fs").readFileSync(0)).status' 2>/dev/null)" = done ] && break
  sleep 1
done
kill $TAIL 2>/dev/null
echo
echo "=== final ==="
echo "$S" | node -pe 'JSON.parse(require("fs").readFileSync(0)).agents.map(a=>`  ${a.name} [${a.state}] ${a.lastMessage}`).join("\n")'
echo
echo "(dock still running so the characters stay up — ./run-demo.sh stop to clear)"

#!/bin/bash
# Smoke test: contract shape + routing + dock push. Runs in FAKE mode, ~10s.
set -u
cd "$(dirname "$0")"
fail() { echo "FAIL: $1"; exit 1; }

node fake-dock.js > /tmp/crew-fakedock.log 2>&1 &
DOCK_PID=$!
# LINE_MS is stage rhythm (4000ms, set from how long a line takes to SAY) and
# this test is about contract shape, not rhythm. Left at the demo value the run
# outlasts the poll budget below and the test fails as "never finished".
FAKE=1 LINE_MS=200 node server.js > /tmp/crew-srv.log 2>&1 &
SRV_PID=$!
trap 'kill $SRV_PID $DOCK_PID 2>/dev/null' EXIT
until curl -sf localhost:4001/status/nope -o /dev/null || [ $? -eq 22 ]; do sleep 0.2; done

START=$(curl -sf -X POST localhost:4001/start-task \
  -H 'content-type: application/json' \
  -d '{"instructions":"clean up my inbox and schedule everything"}')
echo "start-task -> $START"
[ "$(echo "$START" | node -pe 'JSON.parse(require("fs").readFileSync(0)).status')" = started ] \
  || fail "status != started"
ID=$(echo "$START" | node -pe 'JSON.parse(require("fs").readFileSync(0)).taskId')

for _ in $(seq 1 40); do
  S=$(curl -sf "localhost:4001/status/$ID")
  [ "$(echo "$S" | node -pe 'JSON.parse(require("fs").readFileSync(0)).status')" = done ] && break
  sleep 0.5
done
echo "status -> $S"

echo "$S" | node -e '
  const t = JSON.parse(require("fs").readFileSync(0));
  const names = t.agents.map(a => a.name).join(",");
  if (t.status !== "done") throw new Error("never finished");
  if (names !== "triage,scheduler,recap") throw new Error("bad roles: " + names);
  if (!t.agents.every(a => a.state === "done" && a.lastMessage)) throw new Error("agent not done/silent");
' || fail "status payload wrong"

curl -sf -X POST localhost:4001/start-task -H 'content-type: application/json' \
  -d '{"instructions":"just tidy my email"}' > /dev/null
sleep 0.3
grep -q '"character":"triage"' /tmp/crew-fakedock.log \
  || fail "nothing reached the dock — $(head -2 /tmp/crew-fakedock.log)"

echo "PASS — contract, routing, and dock push all good"

#!/bin/bash
# The whole demo, one command. This is what gets run on stage.
#   ./run-demo.sh          real agents (headless claude), ~30s
#   ./run-demo.sh fake     canned narration, no Claude calls  <- PANIC BUTTON
#   ./run-demo.sh stop     kill everything
set -uo pipefail
cd "$(dirname "$0")"
PHRASE="clean up my inbox and schedule everything"

# Narration goes to the room, never to the device VoiceOS listens on — otherwise
# the dock talks over the agents' own commands. `spike.sh split` proves the
# separation (0.00 vs 0.80 on BlackHole). CREW_MUTE=1 silences the dock entirely.
export CREW_AUDIO_DEVICE="${CREW_AUDIO_DEVICE:-MacBook Pro Speakers}"

# One accent each, so three characters don't sound like one process with three
# sprites. Audition alternatives with ./crew-dock/voices.sh audition.
export CREW_VOICE_TRIAGE="${CREW_VOICE_TRIAGE:-Moira}"        # en_IE — dry
export CREW_VOICE_SCHEDULER="${CREW_VOICE_SCHEDULER:-Daniel}" # en_GB — brisk
export CREW_VOICE_RECAP="${CREW_VOICE_RECAP:-Karen}"          # en_AU — warm

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

# Run the binary, not `open` — `open` discards stderr, and the dock's stderr is
# the only proof a line reached the audience. The orchestrator log only proves
# what was *sent*; it printed a flawless run once while the dock was dead.
crew-dock/Crew.app/Contents/MacOS/Crew > /tmp/crew-dock.log 2>&1 &
sleep 2
pgrep -f "Crew.app/Contents/MacOS/Crew" >/dev/null || { echo "dock failed to start"; exit 1; }
echo "dock up on :4002 (narrating to '$CREW_AUDIO_DEVICE', log: /tmp/crew-dock.log)"

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
kill $TAIL 2>/dev/null; wait $TAIL 2>/dev/null

# The orchestrator finishes ~10s before the room does — speech trails the bubbles.
# Without this the summary prints over the recap and `stop` cuts Karen off
# mid-sentence, which is how the show ends silently on stage.
LAST=""; STILL=0
for _ in $(seq 1 40); do
  NOW=$(grep -c '^SAY ->' /tmp/crew-dock.log 2>/dev/null); NOW=${NOW:-0}
  [ "$NOW" = "$LAST" ] && STILL=$((STILL + 1)) || STILL=0
  [ "$STILL" -ge 3 ] && break
  LAST=$NOW; sleep 1
done
echo
echo "=== final ==="
echo "$S" | node -pe 'JSON.parse(require("fs").readFileSync(0)).agents.map(a=>`  ${a.name} [${a.state}] ${a.lastMessage}`).join("\n")'
echo
# What the audience actually got, from the dock's own log rather than ours.
SPOKEN=$(grep -c '^SAY ->' /tmp/crew-dock.log 2>/dev/null); SPOKEN=${SPOKEN:-0}
echo "=== spoken on stage ($SPOKEN lines) ==="
grep '^SAY ->' /tmp/crew-dock.log 2>/dev/null | sed 's/^SAY -> /  /'
grep -q '^DOCK <-' /tmp/crew-dock.log 2>/dev/null \
  || echo "  !! dock received NOTHING — the orchestrator log above is not evidence."
echo
echo "(dock still running so the characters stay up — ./run-demo.sh stop to clear)"

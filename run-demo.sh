#!/bin/bash
# The whole demo, one command. This is what gets run on stage.
#   ./run-demo.sh          real agents, narrated — nothing is touched  <- SAFE
#   ./run-demo.sh live     real agents calling the crew_* tools; the mailbox changes
#   ./run-demo.sh voice    real agents speaking commands to VoiceOS  <- the real thing
#   ./run-demo.sh wait     bring everything up and let VOICEOS start the task
#   ./run-demo.sh fake     canned narration, no Claude calls  <- PANIC BUTTON
#   ./run-demo.sh stop     kill everything
#
# Each mode is a whole prompt file that is known-good on its own
# (orchestrator/prompts/execution-*.md). Dropping down a rung at 5:55pm is a
# different word on this command line, never an edit to a prompt.
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

# If the Piper models are here, speak through them: on-device neural TTS (MIT),
# no account and no network, and it is the difference between a crew and a
# screen reader. `crew-say` falls back to `say` on its own, so this can only
# change how the dock sounds. `./crew-dock/voices.sh piper-install` fetches them.
# A Piper line costs ~1.1s to synthesise on top of speaking it, so pacing has to
# grow to match or the dock starts dropping lines again — same rule as before,
# LINE_MS >= how long a line actually takes.
if [ -z "${CREW_SAY:-}" ] && ls crew-dock/voices/*.onnx >/dev/null 2>&1; then
  export CREW_SAY="$PWD/crew-dock/crew-say"
  export LINE_MS="${LINE_MS:-5500}"
fi

stop() {
  pkill -f "Crew.app/Contents/MacOS/Crew" 2>/dev/null
  pkill -f "orchestrator/server.js" 2>/dev/null
  pkill -f "node server.js" 2>/dev/null
  pkill -f "fake-dock.js" 2>/dev/null
  # Wait for the ports, don't sleep and hope. A listener takes a moment to let
  # go, and starting the next dock inside that window fails the bind — which
  # used to leave an app on screen that could never receive a line.
  #
  # Connect rather than ask lsof: lsof cannot see these sockets at all in a
  # sandboxed shell, so it reported "free" every time and this loop never
  # waited. Trying the connection is what we actually mean, and it can't lie.
  for _ in $(seq 1 20); do
    node -e 'const net=require("net");let n=0;const done=()=>{if(++n===2)process.exit(open?1:0)};let open=false;
      for (const p of [4001,4002]) {
        const s=net.connect(p,"127.0.0.1");
        s.on("connect",()=>{open=true;s.destroy();done()});
        s.on("error",()=>done());
      }' && return 0
    sleep 0.25
  done
  echo "warning: :4001/:4002 still held after 5s" >&2
}

[ "${1:-}" = stop ] && { stop; echo "stopped."; exit 0; }

FAKE=""
WAIT=""
case "${1:-}" in
  fake)  FAKE="FAKE=1"; LABEL="canned, no Claude" ;;
  live)  export CREW_MODE=direct; LABEL="direct — the mailbox really changes" ;;
  voice) export CREW_MODE=voice;  LABEL="voice — agents speak to VoiceOS" ;;
  wait)  export CREW_MODE=narrate; LABEL="narrate — waiting for VoiceOS to start it"; WAIT=1 ;;
  "")    export CREW_MODE=narrate; LABEL="narrate — real agents, nothing touched" ;;
  *)     echo "unknown mode '$1' — use: (none) | live | voice | fake | wait | stop"; exit 1 ;;
esac
# Fail here, not on stage: a missing prompt file means every agent dies silently.
[ -n "$FAKE" ] || [ -f "orchestrator/prompts/execution-${CREW_MODE}.md" ] \
  || { echo "no prompt for mode '$CREW_MODE'"; exit 1; }

stop
# Rebuild when the sources are newer, not only when the binary is missing. The
# old `-x` guard meant a `git pull` that brought new Swift left you running the
# previous build with no warning — the dock fix was on disk and not in the app.
# swiftc is ~3s, so there is no reason to be clever about it.
DOCK_BIN=crew-dock/Crew.app/Contents/MacOS/Crew
if [ ! -x "$DOCK_BIN" ] || [ -n "$(find crew-dock/Sources crew-dock/build.sh -newer "$DOCK_BIN" 2>/dev/null)" ]; then
  echo "building dock..."; ./crew-dock/build.sh >/dev/null
fi

# Run the binary, not `open` — `open` discards stderr, and the dock's stderr is
# the only proof a line reached the audience. The orchestrator log only proves
# what was *sent*; it printed a flawless run once while the dock was dead.
crew-dock/Crew.app/Contents/MacOS/Crew > /tmp/crew-dock.log 2>&1 &
sleep 2
pgrep -f "Crew.app/Contents/MacOS/Crew" >/dev/null || { echo "dock failed to start"; exit 1; }
# Running is not the same as listening — the bind is asynchronous and can fail
# while the app stays happily on screen, receiving nothing all show.
grep -q 'listening on :4002' /tmp/crew-dock.log \
  || { echo "dock is up but never bound :4002:"; cat /tmp/crew-dock.log; exit 1; }
echo "dock up on :4002 (narrating to '$CREW_AUDIO_DEVICE', log: /tmp/crew-dock.log)"

env $FAKE node orchestrator/server.js > /tmp/crew-orchestrator.log 2>&1 &
for _ in $(seq 1 20); do
  curl -sf -o /dev/null localhost:4001/status/x && break
  curl -s -o /dev/null -w '' localhost:4001/status/x 2>/dev/null && break
  sleep 0.3
done
echo "orchestrator up on :4001  [$LABEL]"
echo

# `wait` is the VoiceOS-driven demo: everything is up, nothing has been asked
# for, and the trigger is a human speaking rather than this script. Watching the
# task list is how we know VoiceOS actually reached the orchestrator — the thing
# a spoken demo has to prove and the thing the bridge log alone cannot.
if [ -n "$WAIT" ]; then
  echo "READY — nothing has been asked for yet."
  echo
  echo "  1. press fn+space"
  echo "  2. say: \"$PHRASE\""
  echo
  echo "waiting for VoiceOS to call run_crew_task (ctrl-C to give up)..."
  for _ in $(seq 1 600); do
    ID=$(curl -sf localhost:4001/tasks 2>/dev/null | node -pe 'JSON.parse(require("fs").readFileSync(0)).at(-1)?.taskId||""' 2>/dev/null)
    [ -n "$ID" ] && break
    sleep 1
  done
  [ -n "$ID" ] || { echo "nothing arrived. Is the Crew app registered, and did the trigger fire?"; exit 1; }
  echo "VoiceOS started $ID — the crew is live."
else
ID=$(curl -sf -X POST localhost:4001/start-task -H 'content-type: application/json' \
  -d "{\"instructions\":\"$PHRASE\"}" | node -pe 'JSON.parse(require("fs").readFileSync(0)).taskId')
fi
echo "task: $ID"
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
# Without this the summary prints over the recap and `stop` cuts the last
# character off mid-sentence, which is how the show ends silently on stage.
#
# Wait on the recap's own sign-off rather than on silence: the gap while the
# recap agent spawns is several seconds of no speech, and a silence-based wait
# reads that as the end and returns before the last character has said a word.
RECAP_LAST=$(echo "$S" | node -pe 'JSON.parse(require("fs").readFileSync(0)).agents.at(-1).lastMessage' 2>/dev/null)
for _ in $(seq 1 60); do
  grep -Fq "$RECAP_LAST" /tmp/crew-dock.log 2>/dev/null \
    && grep -F "$RECAP_LAST" /tmp/crew-dock.log | grep -q '^SAY ->' && break
  sleep 1
done
sleep 1   # the line is logged when `say` starts, so let the audio finish
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

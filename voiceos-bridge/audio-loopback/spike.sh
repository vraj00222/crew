#!/bin/bash
# Audio loopback spike — run on A's Mac (the demo machine).
#   ./spike.sh install   one-time, asks for your password (installs an audio driver)
#   ./spike.sh on        route audio into VoiceOS's mic
#   ./spike.sh say "..." speak a command into VoiceOS
#   ./spike.sh verify    proves the audio path, NO VoiceOS needed  <- run before rehearsal
#   ./spike.sh split     proves dock narration and agent commands stay separate
#   ./spike.sh test      the whole go/no-go: routes, speaks, checks, restores
#   ./spike.sh off       put audio back to normal  <- ALWAYS run this when done
set -euo pipefail

# The two speech streams, kept apart by device rather than by timing. `say -a`
# targets one device per utterance, so the dock can narrate to the room while an
# agent talks to VoiceOS and neither ever hears the other. `./spike.sh split`
# measures it. run-demo.sh passes DOCK_DEVICE to the dock as CREW_AUDIO_DEVICE.
DOCK_DEVICE="${DOCK_DEVICE:-MacBook Pro Speakers}"      # audience only
VOICEOS_DEVICE="${VOICEOS_DEVICE:-BlackHole 2ch}"       # VoiceOS only

# `say -a` takes a device NAME or a numeric ID, and the name path is broken:
#
#   $ say -a "BlackHole 2ch" hello
#   NSInvalidArgumentException: Range {0, 13} out of bounds; string length 7
#
# It compares the requested name against the connected device names, and the
# comparison runs off the end of a shorter one. Reproduced with EarPods (7 chars)
# plugged in: BOTH "BlackHole 2ch" and "MacBook Pro Speakers" crashed. Unplug
# EarPods and the same two names work again — so whether it crashes depends on
# what is currently connected, which is not something to reason about on stage.
# Numeric IDs have no such path. Always resolve the name to an ID.
#
# IDs are NOT stable: plugging EarPods in and out moved BlackHole 89 -> 88.
# So resolve at start-up (which the dock does) and do not change audio devices
# mid-run — a cached ID can go stale under you.
say_id() {  # say_id "<device name>" -> numeric id, or empty if not present
  say -a '?' 2>/dev/null | awk -v want="$1" '
    { id=$1; $1=""; sub(/^ +/,""); if ($0==want) { print id; exit } }'
}

# The original 4-line plan sets only the INPUT to BlackHole. That cannot work:
# `say` writes to the OUTPUT device, so nothing ever reaches BlackHole's input
# side. Output must go to BlackHole too. But then the room hears nothing — so
# for the actual demo you want a Multi-Output Device (BlackHole + speakers),
# created once in Audio MIDI Setup.app. `on` below is the headphones-off
# test rig; `demo` assumes you made that multi-output device and named it "crew".

case "${1:-}" in
install)
  brew install blackhole-2ch switchaudio-osx
  echo
  echo "Now create the multi-output device (once, GUI, 30 seconds):"
  echo "  1. open -a 'Audio MIDI Setup'"
  echo "  2. + button (bottom left) -> Create Multi-Output Device"
  echo "  3. tick 'BlackHole 2ch' AND your speakers/MacBook Pro Speakers"
  echo "  4. rename it to: crew"
  ;;

on)  # silent test rig — room hears nothing
  SwitchAudioSource -t output -s "BlackHole 2ch"
  SwitchAudioSource -t input  -s "BlackHole 2ch"
  echo "loopback ON (silent). input=$(SwitchAudioSource -t input -c), output=$(SwitchAudioSource -t output -c)"
  ;;

demo)  # room hears the agents AND VoiceOS hears them
  SwitchAudioSource -t output -s "crew" || { echo "No 'crew' multi-output device — run: $0 install"; exit 1; }
  SwitchAudioSource -t input  -s "BlackHole 2ch"
  echo "loopback DEMO. input=$(SwitchAudioSource -t input -c), output=$(SwitchAudioSource -t output -c)"
  ;;

say)
  # -r 190 is a touch slower than default; transcription is more reliable.
  say -v Samantha -r 190 "${2:?usage: $0 say \"the command\"}"
  ;;

off)
  SwitchAudioSource -t output -s "$DOCK_DEVICE" 2>/dev/null || true
  SwitchAudioSource -t input  -s "MacBook Pro Microphone" 2>/dev/null || true
  echo "restored. input=$(SwitchAudioSource -t input -c), output=$(SwitchAudioSource -t output -c)"
  ;;

verify)  # proves the audio path with NO VoiceOS involved. Run this before rehearsal.
  command -v sox >/dev/null || { echo "needs sox: brew install sox"; exit 1; }
  trap '"$0" off >/dev/null' EXIT INT TERM
  "$0" demo >/dev/null
  sox -q -d /tmp/crew-loop.wav trim 0 7 2>/dev/null &
  REC=$!
  sleep 1
  say -v Samantha -r 190 "The quick brown fox jumps over the lazy dog"
  wait $REC 2>/dev/null
  AMP=$(sox /tmp/crew-loop.wav -n stat 2>&1 | awk '/Maximum amplitude/{print $3}')
  echo "captured peak amplitude: $AMP  (expect > 0.10; silence reads ~0.00)"
  # BlackHole has no microphone — audio can only arrive via the digital loopback.
  awk -v a="$AMP" 'BEGIN{exit !(a>0.10)}' \
    && echo "PASS — say() reaches the virtual mic. Voice loop is physically possible." \
    || { echo "FAIL — no audio on the loopback. Check the 'crew' multi-output device"
         echo "       exists and has BlackHole 2ch ticked (Audio MIDI Setup)."; exit 1; }
  ;;

split)  # proves the two speech streams cannot collide. NO VoiceOS needed.
  # C raised this: agents drive VoiceOS with `say`, the dock also narrates with
  # `say`, and a mix of the two on one mic breaks the loop on stage. The fix is
  # per-utterance `-a`, and this measures that it actually separates them:
  # narration to the speakers must read ~0.00 on BlackHole, commands must be loud.
  command -v sox >/dev/null || { echo "needs sox: brew install sox"; exit 1; }
  trap '"$0" off >/dev/null' EXIT INT TERM
  SwitchAudioSource -t input -s "BlackHole 2ch" >/dev/null   # listen where VoiceOS listens
  peak() {  # peak() <device> — speak one line to $1, report what BlackHole heard
    sox -q -d /tmp/crew-split.wav trim 0 5 2>/dev/null & local rec=$!
    sleep 1
    say -v Samantha -r 190 -a "$(say_id "$1")" "The quick brown fox jumps over the lazy dog"
    wait $rec 2>/dev/null
    sox /tmp/crew-split.wav -n stat 2>&1 | awk '/Maximum amplitude/{print $3}'
  }
  NARR=$(peak "$DOCK_DEVICE")
  CMD=$(peak "$VOICEOS_DEVICE")
  echo "dock narration -> '$DOCK_DEVICE'    : BlackHole heard $NARR  (want ~0.00)"
  echo "agent command  -> '$VOICEOS_DEVICE' : BlackHole heard $CMD  (want > 0.10)"
  awk -v n="$NARR" -v c="$CMD" 'BEGIN{exit !(n<0.02 && c>0.10)}' \
    && echo "PASS — streams are isolated. VoiceOS hears commands only, the room hears narration only." \
    || { echo "FAIL — the streams are bleeding into each other."
         echo "       Most likely the system output is set to the 'crew' multi-output"
         echo "       device, which copies everything to BlackHole. Use ./spike.sh off."; exit 1; }
  ;;

test)  # the whole go/no-go, hands-off except for one key press
  BEFORE=$(sqlite3 -readonly "$HOME/Library/Application Support/VoiceOS/voiceos.db" \
    "SELECT COUNT(*) FROM dictations;" 2>/dev/null || echo 0)
  printf 'crew loopback scratch — dictated text lands here\n\n' > /tmp/crew-dictation.txt
  open -a TextEdit /tmp/crew-dictation.txt   # absorbs the text so it can't type into your terminal
  sleep 2
  # Restore audio no matter how we exit — a dead mic is not an obvious failure.
  trap '"$0" off' EXIT INT TERM
  "$0" demo
  echo
  echo ">>> Click the TextEdit window, then hold your VoiceOS trigger (Fn) <<<"
  echo ">>> I'll speak a test phrase every 8s for the next 48 seconds.     <<<"
  echo
  for i in 1 2 3 4 5 6; do
    echo "[$i/6] speaking..."
    say -v Samantha -r 190 "The quick brown fox jumps over the lazy dog"
    sleep 5
  done
  echo
  AFTER=$(sqlite3 -readonly "$HOME/Library/Application Support/VoiceOS/voiceos.db" \
    "SELECT COUNT(*) FROM dictations;" 2>/dev/null || echo 0)
  echo "=== dictations before=$BEFORE after=$AFTER ==="
  if [ "$AFTER" -gt "$BEFORE" ]; then
    echo "*** VOICE LOOP IS LIVE — VoiceOS transcribed audio it never heard through a microphone ***"
    sqlite3 -readonly "$HOME/Library/Application Support/VoiceOS/voiceos.db" \
      "SELECT created_at, final_transcription FROM dictations ORDER BY rowid DESC LIMIT 3;"
  else
    echo "No new dictation. Check, in this order:"
    echo "  1. did you actually hold the trigger while it was speaking?"
    echo "  2. VoiceOS mic set to 'BlackHole 2ch'?  ./voiceos-setup.sh show"
    echo "  3. muteWhenDictating still true?        ./voiceos-setup.sh apply"
    echo "  4. does dictation work at all — press Fn and talk normally first"
  fi
  echo "(audio restored automatically)"
  ;;

list) SwitchAudioSource -a ;;

*) sed -n '2,6p' "$0"; exit 1 ;;
esac

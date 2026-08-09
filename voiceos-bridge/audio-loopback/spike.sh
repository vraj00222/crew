#!/bin/bash
# Audio loopback spike — run on A's Mac (the demo machine).
#   ./spike.sh install   one-time, asks for your password (installs an audio driver)
#   ./spike.sh on        route audio into VoiceOS's mic
#   ./spike.sh say "..." speak a command into VoiceOS
#   ./spike.sh test      the whole go/no-go: routes, speaks, checks, restores
#   ./spike.sh off       put audio back to normal  <- ALWAYS run this when done
set -euo pipefail

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
  SwitchAudioSource -t output -s "MacBook Pro Speakers" 2>/dev/null || true
  SwitchAudioSource -t input  -s "MacBook Pro Microphone" 2>/dev/null || true
  echo "restored. input=$(SwitchAudioSource -t input -c), output=$(SwitchAudioSource -t output -c)"
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

#!/bin/bash
# Pick the crew's voices by ear, not by argument.
#   ./voices.sh              speak the current cast, in demo order
#   ./voices.sh audition     every installed accent saying that character's line
#   ./voices.sh check        are the good (Enhanced/Premium) voices installed?
#
# Personality is two things and only one of them is here. This file is the
# accent. The *words* are in orchestrator/prompts/{triage,scheduler,recap}.md,
# and they matter more — a great voice reading "Task completed successfully"
# still sounds like a robot.
set -uo pipefail

# One accent each, so three characters never sound like one process with three
# sprites. These are the CREW_VOICE_* defaults run-demo.sh exports.
TRIAGE_VOICE="${CREW_VOICE_TRIAGE:-Moira}"        # en_IE — dry, weary, human
SCHEDULER_VOICE="${CREW_VOICE_SCHEDULER:-Daniel}" # en_GB — brisk, clipped
RECAP_VOICE="${CREW_VOICE_RECAP:-Karen}"          # en_AU — warm sign-off
RATE="${CREW_RATE:-200}"
DEVICE="${CREW_AUDIO_DEVICE:-MacBook Pro Speakers}"

TRIAGE_LINE="Six newsletters. None of them urgent, obviously."
SCHEDULER_LINE="Two o'clock is open. David Chen, that's yours."
RECAP_LINE="That's the lot. Your morning is yours again."

case "${1:-}" in
piper-install)
  # Piper (MIT) — neural TTS that runs on this machine. No account, no
  # subscription, no network once the models are here. ~63MB per voice, not
  # committed. Everything still works without them; you just get the 2005 voices.
  command -v uvx >/dev/null || { echo "needs uv: brew install uv"; exit 1; }
  command -v play >/dev/null || { echo "needs sox: brew install sox"; exit 1; }
  mkdir -p "$(dirname "$0")/voices"
  for V in en_GB-alba-medium en_GB-northern_english_male-medium en_US-amy-medium; do
    if [ -f "$(dirname "$0")/voices/$V.onnx" ]; then echo "  have  $V"; continue; fi
    echo "  fetching $V (~63MB)..."
    uvx --from piper-tts python -m piper.download_voices "$V" \
      --data-dir "$(dirname "$0")/voices" 2>&1 | tail -1
  done
  echo
  echo "Try it:  CREW_SAY=./crew-dock/crew-say ./run-demo.sh fake"
  echo "Or set it permanently — run-demo.sh picks it up automatically once the models exist."
  ;;

audition)
  # Candidates that are installed by default on every Mac, so this runs anywhere.
  for v in Moira Tessa Samantha Fiona Karen Serena; do
    say -v "$v" -r "$RATE" -a "$DEVICE" -- "$TRIAGE_LINE" 2>/dev/null \
      && echo "  triage    <- $v" || echo "  triage    -- $v not installed"
  done
  for v in Daniel Rishi Oliver Alex Fred; do
    say -v "$v" -r "$RATE" -a "$DEVICE" -- "$SCHEDULER_LINE" 2>/dev/null \
      && echo "  scheduler <- $v" || echo "  scheduler -- $v not installed"
  done
  for v in Karen Tessa Moira Samantha Tara; do
    say -v "$v" -r "$RATE" -a "$DEVICE" -- "$RECAP_LINE" 2>/dev/null \
      && echo "  recap     <- $v" || echo "  recap     -- $v not installed"
  done
  echo
  echo "Set the winners in run-demo.sh (CREW_VOICE_TRIAGE / _SCHEDULER / _RECAP)."
  ;;

check)
  # The single biggest quality jump available, and it is a GUI download with no
  # CLI: System Settings -> Accessibility -> Spoken Content -> System Voice ->
  # Manage Voices, then tick the Enhanced or Premium build of each name below.
  # The compact voices that ship by default are the robotic ones.
  echo "installed English voices: $(say -v '?' | grep -c en_)"
  GOOD=$(say -v '?' | grep -Eic '\((Premium|Enhanced)\)')
  echo "Enhanced/Premium among them: $GOOD"
  for v in "$TRIAGE_VOICE" "$SCHEDULER_VOICE" "$RECAP_VOICE"; do
    say -v '?' | grep -qi "^$v " && echo "  ok      $v" || echo "  MISSING $v"
  done
  [ "$GOOD" -gt 0 ] || cat <<'TXT'

None installed — the cast will sound like 2005. ~2 minutes, one time, on the
demo Mac, and it is the biggest single improvement available to the narration:
  System Settings -> Accessibility -> Spoken Content -> System Voice
  -> Manage Voices -> download the Enhanced (or Premium) build of
     Moira, Daniel and Karen.
Enhanced names resolve under the same `-v` name, so nothing in the code changes.
TXT
  ;;

*)
  # Demo order, so you hear the show's actual shape.
  say -v "$TRIAGE_VOICE"    -r "$RATE" -a "$DEVICE" -- "$TRIAGE_LINE"
  say -v "$SCHEDULER_VOICE" -r "$RATE" -a "$DEVICE" -- "$SCHEDULER_LINE"
  say -v "$RECAP_VOICE"     -r "$RATE" -a "$DEVICE" -- "$RECAP_LINE"
  echo "cast: triage=$TRIAGE_VOICE  scheduler=$SCHEDULER_VOICE  recap=$RECAP_VOICE  (rate $RATE)"
  ;;
esac

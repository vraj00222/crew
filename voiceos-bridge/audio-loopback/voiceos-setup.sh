#!/bin/bash
# Apply the VoiceOS settings the voice loop needs.
#   ./voiceos-setup.sh apply    quits VoiceOS, patches settings, relaunches
#   ./voiceos-setup.sh revert   restores the newest backup
#   ./voiceos-setup.sh auto     VoiceOS follows the system input — lets the crew take the mic
#   ./voiceos-setup.sh mic ["Name"]  pin which mic VoiceOS hears
#   ./voiceos-setup.sh handsfree  rebind hands-free off `fn` so a script can trigger it
#   ./voiceos-setup.sh show     print the settings that matter, change nothing
#
# Each setting here was found by reading VoiceOS's own config on 2026-08-08.
# Why each one matters is in coordination.md — do not "clean these up".
set -euo pipefail
CFG="$HOME/Library/Application Support/VoiceOS/config.json"
[ -f "$CFG" ] || { echo "No VoiceOS config at $CFG"; exit 1; }

show() {
  node -pe '
    const s = JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
    [`mic                 : ${s.settings.micSelected}`,
     `micExplicitlySet    : ${s.settings.micExplicitlySet}`,
     `muteWhenDictating   : ${s.settings.muteWhenDictating}   (must be false)`,
     `agentVoiceEnabled   : ${s.settings.agentVoiceEnabled}   (must be false)`,
     `connectedIntegrations: ${JSON.stringify(s.connectedIntegrations)}`,
     `customMcpServers    : ${s.customMcpServers.length} registered`,
     `onboardingCompleted : ${s.onboarding.onboardingCompleted}`].join("\n")' "$CFG"
}

case "${1:-show}" in
apply)
  cp "$CFG" "$CFG.backup-$(date +%Y%m%d-%H%M%S)"
  osascript -e 'quit app "VoiceOS"' 2>/dev/null || true
  sleep 3
  pkill -f "VoiceOS.app/Contents/MacOS" 2>/dev/null || true
  sleep 1
  # Patched with VoiceOS QUIT — Electron rewrites this file on exit and would
  # clobber the edit otherwise.
  node -e '
    const fs=require("fs"), p=process.argv[1];
    const c=JSON.parse(fs.readFileSync(p,"utf8")), s=c.settings;
    s.muteWhenDictating=false;   // else VoiceOS ducks the very `say` audio we feed it
    s.agentVoiceEnabled=false;   // else its own replies loop back into the mic
    s.micDeviceId=s.micSelected=s.preferredMicDeviceId=s.preferredMicSelected="BlackHole 2ch";
    s.micExplicitlySet=true;     // stop "Auto select" flipping back mid-demo
    fs.writeFileSync(p, JSON.stringify(c,null,2));
  ' "$CFG"
  open -a VoiceOS
  sleep 5
  echo "applied:"; show
  ;;

dictate)
  # Make control+option DICTATION-ONLY, so VoiceOS writes down what you say and
  # does nothing about it.
  #
  # This is the difference between a demo of VoiceOS and a demo of the crew. Its
  # chord is mode 3 = agent mode out of the box: on a live run "summarize the
  # last 30 emails and make a note" made VoiceOS produce the Note ITSELF, in its
  # own notch UI, while the crew was still introducing itself. The crew looked
  # like decoration on top of a product that had already finished.
  #
  # mode 0 is plain dictation — transcribe, act on nothing. Then the crew is the
  # only thing that acts, and the agents drive VoiceOS themselves afterwards.
  # `./voiceos-setup.sh agentmode` puts it back.
  MODE="${2:-0}"
  cp "$CFG" "$CFG.backup-$(date +%Y%m%d-%H%M%S)"
  osascript -e 'quit app "VoiceOS"' 2>/dev/null || true
  sleep 3
  pkill -f "VoiceOS.app/Contents/MacOS" 2>/dev/null || true
  sleep 1
  node -e '
    const fs=require("fs"), p=process.argv[1], mode=Number(process.argv[2]);
    const c=JSON.parse(fs.readFileSync(p,"utf8")), s=c.settings;
    for (const k of (s.keyboardShortcuts||[]))
      if ((k.keys||[]).some(x=>/control/.test(x))) k.mode = mode;
    s.agentVoiceEnabled=false; s.muteWhenDictating=false;
    fs.writeFileSync(p, JSON.stringify(c,null,2));
  ' "$CFG" "$MODE"
  open -a VoiceOS
  sleep 4
  echo "control+option is now mode $MODE $([ "$MODE" = 0 ] && echo "(dictation only — VoiceOS will not act)" || echo "(agent mode — VoiceOS acts)")"
  ;;

agentmode)
  "$0" dictate 3
  ;;

auto)
  # Let VoiceOS follow the SYSTEM default input instead of a pinned device.
  #
  # This is what makes one VoiceOS serve both halves of the demo. You speaking
  # needs the real microphone; the agents speaking need BlackHole. Pinned, those
  # are mutually exclusive and switching costs a VoiceOS restart mid-show.
  # Unpinned, `SwitchAudioSource -t input` flips it instantly and VoiceOS follows
  # — so the crew can take over the microphone the moment you stop talking.
  cp "$CFG" "$CFG.backup-$(date +%Y%m%d-%H%M%S)"
  osascript -e 'quit app "VoiceOS"' 2>/dev/null || true
  sleep 3
  pkill -f "VoiceOS.app/Contents/MacOS" 2>/dev/null || true
  sleep 1
  node -e '
    const fs=require("fs"), p=process.argv[1];
    const c=JSON.parse(fs.readFileSync(p,"utf8")), s=c.settings;
    s.micExplicitlySet=false;      // follow the system default
    s.agentVoiceEnabled=false;     // it keeps turning itself back on
    s.muteWhenDictating=false;
    fs.writeFileSync(p, JSON.stringify(c,null,2));
  ' "$CFG"
  open -a VoiceOS
  sleep 5
  echo "VoiceOS now follows the system input device."
  echo "  you speak   : SwitchAudioSource -t input -s 'MacBook Pro Microphone'"
  echo "  agents speak: SwitchAudioSource -t input -s 'BlackHole 2ch'"
  show
  ;;

mic)
  # Which microphone VoiceOS listens on, and it is NOT one setting for both jobs:
  #
  #   YOU speaking      -> the real microphone. BlackHole has no mic, so with the
  #                        loopback rig applied VoiceOS literally cannot hear you.
  #   AGENTS speaking   -> BlackHole 2ch, so `say` reaches it with no air involved.
  #
  # `apply` sets BlackHole because that is the agent loop. Testing your own voice
  # needs this flipped back, and forgetting is indistinguishable from a broken
  # setup: you talk, and nothing happens, and nothing says why.
  DEV="${2:-MacBook Pro Microphone}"
  cp "$CFG" "$CFG.backup-$(date +%Y%m%d-%H%M%S)"
  osascript -e 'quit app "VoiceOS"' 2>/dev/null || true
  sleep 3
  pkill -f "VoiceOS.app/Contents/MacOS" 2>/dev/null || true
  sleep 1
  node -e '
    const fs=require("fs"), p=process.argv[1], dev=process.argv[2];
    const c=JSON.parse(fs.readFileSync(p,"utf8")), s=c.settings;
    s.micDeviceId=s.micSelected=s.preferredMicDeviceId=s.preferredMicSelected=dev;
    s.micExplicitlySet=true;
    // VoiceOS keeps turning this back on, and in a loopback rig it hears its own
    // replies and re-triggers itself. Off every time we touch the config.
    s.agentVoiceEnabled=false;
    s.muteWhenDictating=false;
    fs.writeFileSync(p, JSON.stringify(c,null,2));
  ' "$CFG" "$DEV"
  open -a VoiceOS
  sleep 5
  echo "VoiceOS mic -> $DEV"; show
  ;;

handsfree)
  # Rebind hands-free off `fn`, which is the single thing keeping a human in the
  # loop: `fn` is handled below the layer CGEvent/AppleScript can post, so no
  # script can press it. Every other chord can be synthesized, and VoiceOS
  # already ships a non-fn chord (control-left + option-left) of its own, so
  # arbitrary combos are clearly supported.
  #
  # After this, `spike.sh trigger` starts dictation with no hands.
  CHORD="${2:-control-left,option-left,h}"
  cp "$CFG" "$CFG.backup-$(date +%Y%m%d-%H%M%S)"
  osascript -e 'quit app "VoiceOS"' 2>/dev/null || true
  sleep 3
  pkill -f "VoiceOS.app/Contents/MacOS" 2>/dev/null || true
  sleep 1
  node -e '
    const fs=require("fs"), p=process.argv[1], keys=process.argv[2].split(",");
    const c=JSON.parse(fs.readFileSync(p,"utf8")), s=c.settings;
    s.handsFreeShortcut = { ...s.handsFreeShortcut, keys };
    // The bare-`fn` push-to-talk entry stays: it is the human fallback, and
    // losing it would mean a failed rebind leaves no way to talk at all.
    fs.writeFileSync(p, JSON.stringify(c,null,2));
  ' "$CFG" "$CHORD"
  open -a VoiceOS
  sleep 5
  echo "hands-free rebound to: $CHORD"
  echo "now: ./spike.sh trigger    (needs Accessibility once — see below)"
  ;;

revert)
  BK=$(ls -t "$CFG".backup-* 2>/dev/null | head -1) || { echo "no backup"; exit 1; }
  osascript -e 'quit app "VoiceOS"' 2>/dev/null || true
  sleep 3
  cp "$BK" "$CFG"
  echo "reverted from $BK"; show
  ;;

show) show ;;
*) sed -n '2,5p' "$0"; exit 1 ;;
esac

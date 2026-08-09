#!/bin/bash
# Apply the VoiceOS settings the voice loop needs. Run once the Pro trial is active.
#   ./voiceos-setup.sh apply    quits VoiceOS, patches settings, relaunches
#   ./voiceos-setup.sh revert   restores the newest backup
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

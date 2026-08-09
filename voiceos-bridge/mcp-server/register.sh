#!/bin/bash
# Register the Crew MCP server with VoiceOS — macOS side.
#
# The macOS half of B's register.ps1. Same job, same safety rule: it AUDITS and
# PRINTS, it never writes VoiceOS's config.
#
#   ./register.sh          find VoiceOS, audit its settings, print what to do
#
# SAFETY: ~/Library/Application Support/VoiceOS/config.json holds live auth
# tokens (accessToken, idToken, auth, supabase). This script reads that file but
# only ever reports named non-secret settings. It never prints the file, and it
# never writes it — VoiceOS is an electron-store and rewrites the whole file on
# its own schedule, so a hand-edit made while the app is running just vanishes.
# Do not paste the raw config into chat, the repo, or the group thread.
set -uo pipefail
cd "$(dirname "$0")"

SERVER="$(pwd)/server.js"
CONFIG="$HOME/Library/Application Support/VoiceOS/config.json"
APP="/Applications/VoiceOS.app"

bold() { printf '\n\033[1m%s\033[0m\n'   "$1"; }
ok()   { printf '  \033[32mok\033[0m    %s\n' "$1"; }
warn() { printf '  \033[33mfix\033[0m   %s\n' "$1"; }
bad()  { printf '  \033[31mno\033[0m    %s\n' "$1"; }

bold "VoiceOS install"
[ -d "$APP" ] && ok "$APP" || bad "VoiceOS.app not in /Applications — install it first"
# There is no CLI on macOS either. B checked for `voiceos add mcp` on Windows and
# found none; same here, so registration is in-app on both platforms.
command -v voiceos >/dev/null 2>&1 \
  && ok "a 'voiceos' CLI exists on PATH — try: voiceos add mcp" \
  || ok "no 'voiceos' CLI (expected) — registration is in-app, see below"

bold "Settings audit  (named keys only, never the file)"
if [ ! -f "$CONFIG" ]; then
  bad "no config.json yet — launch VoiceOS once, sign in, then re-run this"
else
  # The keys are NESTED. coordination.md and register.ps1 both describe these as
  # top-level, which is true of neither Mac we have checked: they live under
  # settings.* and onboarding.*. Reading them at the top level reports "absent"
  # for settings that are in fact set, which is worse than not checking.
  python3 - "$CONFIG" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1]))
s   = cfg.get("settings", {})   if isinstance(cfg.get("settings"), dict)   else {}
onb = cfg.get("onboarding", {}) if isinstance(cfg.get("onboarding"), dict) else {}

def ok(m):   print(f"  \033[32mok\033[0m    {m}")
def fix(m):  print(f"  \033[33mfix\033[0m   {m}")

# Pro/onboarding gate — the thing that blocked the whole team all day.
(ok if onb.get("onboardingCompleted") else fix)(
    "onboarding complete (Pro is live)" if onb.get("onboardingCompleted")
    else "onboarding NOT complete — the paywall is still in the way")

# A's finding 2: VoiceOS ducks system audio while listening. Our loop is
# `say` -> BlackHole -> VoiceOS's mic, so ducking mutes the thing it must hear.
(fix if s.get("muteWhenDictating") else ok)(
    'settings.muteWhenDictating = true  -> turn OFF, it mutes the audio the loop feeds it'
    if s.get("muteWhenDictating") else "settings.muteWhenDictating is off")

# A's finding 3: VoiceOS talks back; in a loopback rig it would hear itself.
(fix if s.get("agentVoiceEnabled") else ok)(
    'settings.agentVoiceEnabled = true  -> turn OFF, it will re-trigger on its own replies'
    if s.get("agentVoiceEnabled") else "settings.agentVoiceEnabled is off")

# `fn` cannot be synthesized on macOS, so the trigger must be a normal chord.
n = len(s.get("keyboardShortcuts") or [])
(ok if n else fix)(f"settings.keyboardShortcuts: {n} chord(s) registered"
                   if n else "no keyboard chord registered — fn cannot be synthesized, rebind it")

mcp = cfg.get("customMcpServers")
mcp = mcp if isinstance(mcp, list) else []
names = [m.get("name") for m in mcp if isinstance(m, dict)]
(ok if any(n == "crew" for n in names) else fix)(
    "customMcpServers already contains 'crew'" if any(n == "crew" for n in names)
    else f"customMcpServers has {len(mcp)} entr{'y' if len(mcp)==1 else 'ies'}, no 'crew' yet — register it below")

# B decided the MCP server owns Gmail because A's Mac had no Google integration.
# That is per-account, not per-app: report what THIS machine actually has.
print(f"  \033[36mfyi\033[0m   connectedIntegrations = {cfg.get('connectedIntegrations')}")
print(f"  \033[36mfyi\033[0m   codingAgentDangerouslyBypassPermissions = "
      f"{cfg.get('codingAgentDangerouslyBypassPermissions')}")
PY
fi

bold "Server self-test"
if [ ! -f "$SERVER" ]; then
  bad "server.js not found at $SERVER"
  exit 1
fi
# stdout is the MCP channel, so the selftest reports on stderr.
node "$SERVER" --selftest 2>&1 | grep -E "protocol|PASS|FAIL" | sed 's/^/  /'

bold "Register it (there is no CLI — this part is by hand)"
cat <<EOF
  VoiceOS window -> Settings -> MCP / custom servers -> Add, then:

      name    : crew
      command : node
      args    : $SERVER

  The absolute path is deliberate — VoiceOS's working directory is not this
  folder, so a relative path silently fails to start.

  Do NOT hand-edit config.json to add this. It is an electron-store: the app
  rewrites the whole file on its own schedule and your entry disappears. If you
  must edit it, quit VoiceOS completely first.

  Then, in order:
    1. ./run-demo.sh              (the bridge POSTs to :4001 — start it first)
    2. say "clean up my inbox and schedule everything"
    3. ask "what's the crew doing?"   -> crew_task_status answers in a sentence

  Registered and it still does nothing? tools/list is the check — if 'crew' is
  absent there, VoiceOS never started the server, and the usual cause is a
  relative path or node not being on the app's PATH.
EOF

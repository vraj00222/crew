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

bold "Node that VoiceOS can actually launch"
# VoiceOS is a GUI app: launched from Finder it never sources a shell profile,
# so its PATH is the bare /usr/bin:/bin. `command: node` therefore works only if
# node lives somewhere that PATH covers. With nvm — the common case — it does
# not, and the failure is `MCP error -32000: Connection closed`, which reads
# like a broken server rather than a missing interpreter.
NODE_BIN=""
for c in /usr/local/bin/node /opt/homebrew/bin/node /usr/bin/node; do
  [ -x "$c" ] && { NODE_BIN="$c"; break; }
done
if [ -n "$NODE_BIN" ]; then
  ok "$NODE_BIN (on the default PATH, so plain \`node\` would work too)"
else
  NODE_BIN="$(command -v node 2>/dev/null || true)"
  if [ -n "$NODE_BIN" ]; then
    warn "node is only at $NODE_BIN — not on a GUI app's PATH."
    warn "Registering that absolute path. If you switch node versions, re-run this."
  else
    bad "no node at all — the bridge cannot run"
  fi
fi

if [ "${1:-}" = "--apply" ]; then
  bold "Registering (writing config.json)"
  if [ -z "$NODE_BIN" ] || [ ! -f "$SERVER" ] || [ ! -f "$CONFIG" ]; then
    bad "need node, server.js and an existing config.json — nothing written"
    exit 1
  fi
  # electron-store rewrites the whole file on its own schedule, so an edit made
  # underneath a running app is simply lost. Quit first, always.
  if pgrep -x VoiceOS >/dev/null; then
    warn "VoiceOS is running — quitting it so the edit sticks"
    osascript -e 'tell application "VoiceOS" to quit' >/dev/null 2>&1
    for _ in $(seq 1 20); do pgrep -x VoiceOS >/dev/null || break; sleep 0.5; done
    pgrep -x VoiceOS >/dev/null && { bad "VoiceOS would not quit — refusing to edit underneath it"; exit 1; }
  fi
  BACKUP="$CONFIG.bak-$(date +%Y%m%d-%H%M%S)"
  cp -p "$CONFIG" "$BACKUP" && chmod 600 "$BACKUP"
  ok "backup: $(basename "$BACKUP")"
  # Entry shape is B's, established on Windows in register.ps1 — same app, same
  # store, so the same schema. Written with python rather than jq: no extra
  # dependency, and it round-trips every key we are not touching.
  python3 - "$CONFIG" "$NODE_BIN" "$SERVER" <<'PY'
import json, sys, uuid
cfg_path, node_bin, server = sys.argv[1], sys.argv[2], sys.argv[3]
cfg = json.load(open(cfg_path))
servers = cfg.get("customMcpServers")
servers = servers if isinstance(servers, list) else []
entry = next((s for s in servers if isinstance(s, dict) and s.get("name") == "crew"), None)
action = "updated" if entry else "added"
if entry is None:
    entry = {"id": str(uuid.uuid4()), "name": "crew"}
    servers.append(entry)
entry.update({"transport": "stdio", "command": node_bin,
              "args": [server], "enabled": True})
cfg["customMcpServers"] = servers
json.dump(cfg, open(cfg_path, "w"), indent=2)
print(f"  \033[32mok\033[0m    crew {action}: {node_bin} {server}")
PY
  ok "relaunch VoiceOS, then check Settings shows crew with run_crew_task + crew_task_status"
  echo "  (restore with: cp \"$BACKUP\" \"$CONFIG\")"
  exit 0
fi

bold "Register it  —  ./register.sh --apply  does this for you"
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

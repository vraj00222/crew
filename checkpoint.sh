#!/bin/bash
# One command all three of us run to prove we are looking at the same system.
#   ./checkpoint.sh          everything that can be checked on this machine
#   ./checkpoint.sh quick    skip the ~40s dress rehearsal
#
# Every check is local. Nothing here needs another person's process to be up,
# because "it works on mine" is only worth something if we all ran the same thing.
cd "$(dirname "$0")"
PASS=0; FAIL=0; SKIP=0
ok()   { echo "  ok    $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }
skip() { echo "  --    $1"; SKIP=$((SKIP+1)); }
have() { command -v "$1" >/dev/null 2>&1; }

echo "crew checkpoint — $(git rev-parse --short HEAD) on $(uname -s)"
echo
# Start from nothing: a dock or orchestrator left over from an earlier run owns
# the ports, and then these checks quietly report on that process instead.
./run-demo.sh stop >/dev/null 2>&1

echo "everyone:"
git fetch -q origin 2>/dev/null
BEHIND=$(git rev-list --count HEAD..origin/main 2>/dev/null || echo "?")
[ "$BEHIND" = 0 ] && ok "up to date with origin/main" \
                  || bad "$BEHIND commits behind origin/main — git pull --rebase origin main"
[ -z "$(git status --porcelain)" ] && ok "working tree clean" || skip "uncommitted changes (fine mid-work)"
have node && ok "node $(node -v)" || bad "no node — the orchestrator and MCP server both need it"

# The .sh files must be LF. A CRLF one dies as `bad interpreter: /bin/bash^M`
# on the demo Mac, and it is invisible until then. This is why .gitattributes exists.
if git ls-files --eol -- '*.sh' 2>/dev/null | grep -q 'w/crlf'; then
  bad "a .sh file has CRLF line endings — it will not run on the demo Mac"
else
  ok "shell scripts are LF"
fi
echo

echo "A — orchestrator, dock, audio:"
if have claude; then ok "claude CLI present (real agents available)"; else skip "no claude CLI — fake mode only"; fi
for m in narrate direct voice; do
  [ -f "orchestrator/prompts/execution-$m.md" ] && ok "prompt: execution-$m.md" || bad "missing execution-$m.md"
done
if [ "$(uname -s)" = Darwin ]; then
  # Existence is not enough. This checkpoint exists to prove all three of us are
  # running the *same commit*, and the dock is the only compiled artifact here —
  # a pull that brings new Swift leaves a stale binary that still passes every
  # other check, so the run below would grade code nobody has on disk.
  DOCK_BIN=crew-dock/Crew.app/Contents/MacOS/Crew
  if [ ! -x "$DOCK_BIN" ]; then
    skip "dock not built — ./crew-dock/build.sh"
  elif [ -n "$(find crew-dock/Sources crew-dock/build.sh -newer "$DOCK_BIN" 2>/dev/null)" ]; then
    bad "dock binary is OLDER than its sources — ./crew-dock/build.sh (you are testing stale code)"
  else
    ok "dock built, and newer than its sources"
  fi
  have SwitchAudioSource && ok "switchaudio-osx" || skip "no switchaudio-osx (brew install switchaudio-osx)"
  say -a '?' 2>/dev/null | grep -q "BlackHole" && ok "BlackHole present" || skip "no BlackHole — rungs 1-3 still work"
  GOOD=$(say -v '?' 2>/dev/null | grep -Eic '\((Premium|Enhanced)\)')
  [ "${GOOD:-0}" -gt 0 ] && ok "$GOOD enhanced/premium voices" \
                         || skip "no enhanced voices — see ./crew-dock/voices.sh check"
else
  skip "not macOS — dock and audio checks are A's machine only"
fi
echo

echo "B — bridge:"
# B's stdio test calls run_crew_task for real, so it needs something on :4001.
# FAKE costs nothing and makes this checkable on B's machine too.
FAKE=1 node orchestrator/server.js >/tmp/crew-chk-orch.log 2>&1 &
CHK_ORCH=$!
sleep 1
node voiceos-bridge/mcp-server/test-stdio.js >/tmp/crew-chk-mcp.log 2>&1 \
  && ok "MCP protocol (initialize, tools/list, run_crew_task, status loop)" \
  || bad "MCP stdio test — see /tmp/crew-chk-mcp.log"
# What VoiceOS reads back to the room when someone asks how it is going. Pure
# function, no orchestrator and no network — it stays checkable when :4001 is down.
node voiceos-bridge/mcp-server/test-status-speech.js >/tmp/crew-chk-speech.log 2>&1 \
  && ok "status replies are sentences, not JSON" \
  || bad "status speech — see /tmp/crew-chk-speech.log"
kill $CHK_ORCH 2>/dev/null; wait $CHK_ORCH 2>/dev/null
node voiceos-bridge/mcp-server/test-demo-flow.js >/tmp/crew-chk-flow.log 2>&1 \
  && ok "gmail/calendar tools — every spoken number true of the mailbox" \
  || bad "demo flow — see /tmp/crew-chk-flow.log"
if have uv; then
  (cd voiceos-bridge/demo-seed && uv run seed.py --dry-run >/tmp/crew-chk-seed.log 2>&1) \
    && ok "demo-seed dry run (18 emails, counts hold)" || bad "demo-seed — see /tmp/crew-chk-seed.log"
else
  skip "no uv — cannot check demo-seed (B's machine has it)"
fi
echo

echo "C — dock contract:"
./orchestrator/test.sh >/tmp/crew-chk-test.log 2>&1 \
  && ok "contract, routing, dock push" \
  || bad "orchestrator/test.sh — see /tmp/crew-chk-test.log"
echo

if [ "${1:-}" != quick ] && [ "$(uname -s)" = Darwin ] && [ -x crew-dock/Crew.app/Contents/MacOS/Crew ]; then
  echo "the whole show (canned, ~40s, no Claude spend):"
  ./run-demo.sh fake >/tmp/crew-chk-demo.log 2>&1
  RECV=$(grep -c '^DOCK <-' /tmp/crew-dock.log 2>/dev/null); RECV=${RECV:-0}
  SPOK=$(grep -c '^SAY ->'  /tmp/crew-dock.log 2>/dev/null); SPOK=${SPOK:-0}
  ./run-demo.sh stop >/dev/null 2>&1
  [ "$RECV" -ge 16 ] && ok "$RECV lines reached the dock" || bad "only $RECV lines reached the dock"
  # 10 narration lines; 16 received = 10 + 3 "waking up" + 3 done re-sends.
  [ "$SPOK" -ge 10 ] && ok "$SPOK lines spoken out loud — none dropped" \
                     || bad "only $SPOK of 10 lines spoken — pacing vs speech rate, see LINE_MS"
  echo
fi

echo "$PASS ok, $FAIL failed, $SKIP not applicable here"
[ "$FAIL" -eq 0 ] && echo "CHECKPOINT PASS — safe to build on this commit." \
                  || echo "CHECKPOINT FAIL — fix or flag in coordination.md before building on it."
exit $((FAIL > 0))

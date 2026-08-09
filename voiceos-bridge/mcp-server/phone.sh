#!/bin/bash
# The phone stack, one command — so "the crew can ring you" is not five things
# to remember at 5:55pm.
#
#   ./phone.sh up      voice server + tunnel + point the number, then prove it
#   ./phone.sh check   preflight: every condition that must hold before the show
#   ./phone.sh down    put it all away
#   ./phone.sh say "..."      ring the demo phone and speak a line   (smoke test)
#   ./phone.sh ask "...?"     ring it, ask, print what you said back  (smoke test)
#
# Why this exists: an outbound call runs the number's POINTED WEBHOOK when it is
# answered. Three things must be true at once — the webhook process is up, a
# tunnel makes it publicly reachable, and the number points at THAT tunnel. Get
# any one wrong and the failure is the worst kind: the phone rings on stage and
# then says nothing, or says the previous run's line. `check` exists to find
# that out in the green room instead of in front of the room.
set -uo pipefail
cd "$(dirname "$0")"

PORT="${CREW_VOICE_PORT:-4003}"
VOICE_LOG=/tmp/crew-voice.log
TUNNEL_LOG=/tmp/crew-tunnel.log
FAILED=0

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; FAILED=1; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
hint() { printf '      %s\n' "$1"; }

# The number's currently-pointed webhook, straight from a1mobile. Parsed
# defensively: we care that it is an https URL we can reach, not which key the
# API happened to put it under.
# http as well as https on purpose: a number pointed at a plain-http address is
# a real state we want to SEE and then fail on the reachability probe below,
# rather than one we silently report as "not pointed at anything".
pointed_url() {
  node a1mobile.js info 2>/dev/null \
    | grep -Eo 'https?://[^"[:space:],]+' | head -1
}

health_of() { curl -sf --max-time 8 "$1/health" 2>/dev/null; }

# --- bring the tunnel up and tell us its public address ---
# cloudflared needs no account and prints its hostname to the log; ngrok has a
# local API. CREW_TUNNEL_URL short-circuits both for anyone with a fixed domain.
start_tunnel() {
  if [ -n "${CREW_TUNNEL_URL:-}" ]; then echo "${CREW_TUNNEL_URL%/}"; return 0; fi

  if command -v cloudflared >/dev/null 2>&1; then
    : > "$TUNNEL_LOG"
    cloudflared tunnel --url "http://localhost:$PORT" > "$TUNNEL_LOG" 2>&1 &
    for _ in $(seq 1 80); do
      U=$(grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' "$TUNNEL_LOG" 2>/dev/null | head -1)
      [ -n "$U" ] && { echo "$U"; return 0; }
      sleep 0.5
    done
    return 1
  fi

  if command -v ngrok >/dev/null 2>&1; then
    ngrok http "$PORT" --log stdout > "$TUNNEL_LOG" 2>&1 &
    for _ in $(seq 1 80); do
      U=$(curl -sf --max-time 2 http://localhost:4040/api/tunnels 2>/dev/null \
        | node -pe 'try{const t=JSON.parse(require("fs").readFileSync(0)).tunnels||[];(t.find(x=>String(x.public_url).startsWith("https"))||{}).public_url||""}catch(e){""}' 2>/dev/null)
      [ -n "$U" ] && { echo "${U%/}"; return 0; }
      sleep 0.5
    done
    return 1
  fi

  return 2   # no tunnel binary at all
}

start_voice() {
  if health_of "http://localhost:$PORT" >/dev/null 2>&1; then
    echo "voice server already up on :$PORT"
    return 0
  fi
  : > "$VOICE_LOG"
  node voice-webhook.js > "$VOICE_LOG" 2>&1 &
  for _ in $(seq 1 40); do
    health_of "http://localhost:$PORT" >/dev/null 2>&1 && { echo "voice server up on :$PORT (log: $VOICE_LOG)"; return 0; }
    sleep 0.25
  done
  echo "voice server never answered on :$PORT:" >&2; cat "$VOICE_LOG" >&2; return 1
}

down() {
  pkill -f 'voice-webhook.js' 2>/dev/null
  pkill -f "cloudflared tunnel --url http://localhost:$PORT" 2>/dev/null
  pkill -f "ngrok http $PORT" 2>/dev/null
  # Same reason run-demo.sh waits on its ports rather than sleeping: a listener
  # takes a moment to let go, and the next `up` inside that window fails to bind.
  for _ in $(seq 1 20); do
    node -e 'const s=require("net").connect(process.argv[1],"127.0.0.1");
      s.on("connect",()=>{s.destroy();process.exit(1)});s.on("error",()=>process.exit(0))' "$PORT" && return 0
    sleep 0.25
  done
  echo "warning: :$PORT still held after 5s" >&2
}

# --- the preflight ---
# Ordered the way they fail: no key means nothing else can even be asked.
check() {
  echo
  echo "  phone preflight"
  echo "  ─────────────────────────────────────────────"

  INFO=$(node a1mobile.js info 2>&1)
  if echo "$INFO" | grep -q 'no a1mobile team key'; then
    bad "no team key on this machine"
    hint "put ai-mobile-integration.md at the repo root, or export A1MOBILE_TEAM_KEY"
    echo; return 1
  elif echo "$INFO" | grep -qi 'error\|HTTP [45]'; then
    bad "a1mobile rejected us: $(echo "$INFO" | head -1)"
  else
    ok "team key accepted, number claimed"
  fi

  if [ -n "${CREW_PHONE:-}" ]; then
    case "$CREW_PHONE" in
      +[0-9]*) ok "CREW_PHONE = $CREW_PHONE" ;;
      *) bad "CREW_PHONE='$CREW_PHONE' is not E.164 (needs the leading +)" ;;
    esac
    hint "if this number has never been OTP'd: node a1mobile.js verify $CREW_PHONE"
  else
    bad "CREW_PHONE unset — 'text me' has no phone to mean"
    hint "export CREW_PHONE=+1XXXXXXXXXX   (and verify it once, see docs/a1mobile.md)"
  fi

  if health_of "http://localhost:$PORT" >/dev/null 2>&1; then
    ok "voice server answering on :$PORT"
  else
    bad "no voice server on :$PORT — answered calls would say nothing"
    hint "./phone.sh up"
  fi

  # The check that actually matters, and the one no amount of local testing
  # covers: Telnyx dials our webhook from the open internet. Fetching our own
  # /health THROUGH the pointed URL is the only proof the whole path works.
  PUB=$(pointed_url)
  if [ -z "$PUB" ]; then
    bad "the number is not pointed at any webhook — a call would ring and stay silent"
    hint "./phone.sh up   (or: node a1mobile.js point https://YOUR-TUNNEL/voice)"
  else
    BASE="${PUB%/voice}"
    if health_of "$BASE" | grep -q '"ok":true'; then
      ok "pointed webhook is publicly reachable — $PUB"
    else
      bad "pointed at $PUB but it does not answer from outside"
      hint "the tunnel died or moved. ./phone.sh up re-points it."
    fi
  fi

  if [ -n "${OPENAI_API_KEY:-}" ] || grep -q '^OPENAI_API_KEY' ../../.env 2>/dev/null; then
    ok "transcription: OpenAI key present (~2s per answer)"
  elif command -v uvx >/dev/null 2>&1; then
    warn "transcription: no OpenAI key, falling back to local whisper via uvx"
    hint "first run downloads ~1.6GB — do it once before the show, not during it"
  else
    bad "no way to transcribe an answer — crew_ask_user would always hear silence"
    hint "put OPENAI_API_KEY in the repo-root .env, or: brew install uv"
  fi

  if [ "${CREW_PHONE_FAKE:-}" = 1 ]; then
    warn "CREW_PHONE_FAKE=1 — the phone is SIMULATED in-process, nothing here is used"
    hint "that is the deterministic route and it always works. unset it for a real call."
  fi

  if [ "${A1MOBILE_DRY:-}" = 1 ]; then
    warn "A1MOBILE_DRY=1 — texts and calls are STAGED, the phone will not ring"
    hint "right for rehearsal loops, wrong for the show. unset it before you go on."
  fi

  echo "  ─────────────────────────────────────────────"
  [ "$FAILED" = 0 ] && echo "  ready — the crew can reach you." || echo "  not ready — fix the ✗ above."
  echo
  return "$FAILED"
}

case "${1:-up}" in
  down|stop) down; echo "phone stack down."; exit 0 ;;

  check|doctor) check; exit $? ;;

  up)
    start_voice || exit 1
    URL=$(start_tunnel); RC=$?
    if [ "$RC" = 2 ]; then
      echo
      echo "no tunnel binary found — calls cannot work without one."
      echo "  brew install cloudflared      (no account needed)"
      echo "  or: brew install ngrok        (then: ngrok config add-authtoken ...)"
      echo "  or: export CREW_TUNNEL_URL=https://your-fixed-domain"
      echo
      echo "SMS still works without any of this."
      exit 1
    fi
    [ "$RC" = 0 ] && [ -n "$URL" ] || { echo "the tunnel never came up:"; tail -5 "$TUNNEL_LOG"; exit 1; }
    echo "tunnel: $URL"

    node a1mobile.js point "$URL/voice" >/dev/null 2>&1 \
      || { echo "could not point the number at $URL/voice"; exit 1; }
    echo "number pointed at $URL/voice"
    echo
    check
    ;;

  say)
    shift; MSG="${*:-Hello from your crew. Everything is on track.}"
    curl -sf -X POST "http://localhost:$PORT/say" -H 'content-type: application/json' \
      -d "$(node -pe 'JSON.stringify({message:process.argv[1]})' "$MSG")" >/dev/null \
      || { echo "voice server not up — ./phone.sh up"; exit 1; }
    node a1mobile.js call "${CREW_PHONE:-}"
    ;;

  ask)
    shift; Q="${*:-Is there anything else you want the crew to do?}"
    curl -sf -X POST "http://localhost:$PORT/ask" -H 'content-type: application/json' \
      -d "$(node -pe 'JSON.stringify({question:process.argv[1]})' "$Q")" >/dev/null \
      || { echo "voice server not up — ./phone.sh up"; exit 1; }
    node a1mobile.js call "${CREW_PHONE:-}" >/dev/null || exit 1
    echo "ringing ${CREW_PHONE:-the demo phone} — answer it and speak."
    curl -sf "http://localhost:$PORT/answer?timeout=120000" \
      | node -pe 'const a=JSON.parse(require("fs").readFileSync(0));a.text?`you said: "${a.text}"`:"no answer heard."'
    ;;

  *) echo "usage: ./phone.sh {up | check | down | say <line> | ask <question>}"; exit 2 ;;
esac

# a1mobile — the crew can really text you, really ring you, and really ASK you

Three new crew tools, live in `direct` mode:

- `crew_send_sms(body)` — a real SMS from the team's number (+1 930 213 1460)
- `crew_place_call(message)` — your phone rings, a voice speaks the message, hangs up
- `crew_ask_user(question)` — **the stuck-agent loop.** An agent hits a decision
  only a human can make → your phone rings → the voice states the blocker and
  asks → you answer in words after the beep and hang up → whisper transcribes
  it locally → the agent gets your words back as text and continues on them.

The demo lines this buys: *"…and text me when it's done"* — mid-recap, the
presenter's phone buzzes on the table. And the big one: an agent says "I need
to ask", the presenter's phone rings, they answer it *in front of the room*,
and the crew acts on what they said.

Nothing is kept as audio: the answer recording is downloaded to a temp file,
transcribed, and deleted, success or failure. Only the transcript text lands
in `call-log.jsonl` (gitignored). The call never announces recording because
no recording is kept.

## Where the credentials live

The team key is in `ai-mobile-integration.md` at the repo root — **gitignored,
never committed**, same rule as the VoiceOS tokens. `a1mobile.js` reads it from
there automatically; `A1MOBILE_TEAM_KEY` overrides for a machine without the file.

## One-time setup (once per phone, before rehearsal)

a1mobile only reaches numbers a human has OTP-verified — consent is enforced
by the API, so the blast radius is exactly the phones we verify.

```bash
cd voiceos-bridge/mcp-server

# 1. verify the phone the demo will text/call (a code arrives on it)
node a1mobile.js verify  +1XXXXXXXXXX
node a1mobile.js confirm +1XXXXXXXXXX 123456

# 2. tell the crew whose phone "text me" means — set on the orchestrator's env
export CREW_PHONE=+1XXXXXXXXXX

# 3. prove it end to end
node a1mobile.js sms +1XXXXXXXXXX "hello from the crew"
```

SMS needs nothing else. **Calls need two more pieces**, because a1mobile runs
our *pointed webhook* when the call is answered — that webhook is what the call
says:

```bash
# 4. the call-script server (what an answered call speaks) — keep it running
node voice-webhook.js                          # :4003

# 5. a tunnel so a1mobile can reach it, then point the number at it
cloudflared tunnel --url http://localhost:4003 # or: ngrok http 4003
node a1mobile.js point https://YOUR-TUNNEL/voice
node a1mobile.js call +1XXXXXXXXXX             # your phone rings and talks
```

`node a1mobile.js info` shows what the number is currently wired to.
`node a1mobile.js unpoint` reverts it to SIP if calls need to stop working.

## Rehearsal kill switch

`A1MOBILE_DRY=1` on the orchestrator's env stages texts and calls without
sending them — the tools succeed and say "rehearsal mode" instead. A rehearsal
loop that really texts a phone thirty times numbs the human and risks rate
limits; flip this on for loops, off for the run-through and the show.

`./run-demo.sh fake` never touches any of this — fake mode spawns no agents,
so no tool can fire.

## Failure modes, and what they sound like

- No team key on the machine → phone tools fail with a sentence saying to set
  `A1MOBILE_TEAM_KEY`; every other crew tool is untouched.
- `CREW_PHONE` unset and no number given → readable error, nothing sent.
- Number not verified → the API refuses; the agent narrates on without it.
- `voice-webhook.js` not running → calls refuse to dial rather than ring a
  phone that would speak the wrong script.
- `crew_ask_user` unanswered (no pickup, silence, whisper missing) → the agent
  is told "no answer, use your best judgment" as a normal result, not an error.
- Timing: an ask can take up to `CREW_ASK_WAIT_MS` (120s). The orchestrator
  kills agents at `AGENT_TIMEOUT_MS` (180s) — raise it for runs that may ask,
  or the agent dies mid-conversation.
- Transcription is ours because a1mobile does not forward Telnyx's own
  `transcribe` callback (verified live 2026-08-09): OpenAI's transcription API
  when a key exists (`OPENAI_API_KEY` env or repo-root `.env`, gitignored),
  local mlx-whisper via `uvx` otherwise. The audio lives only in a temp dir
  for the seconds it takes to transcribe, then the whole dir is deleted.

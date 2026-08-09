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

SMS needs nothing else. **Calls need three more pieces** — a call server, a
public tunnel to it, and the number pointed at that tunnel — because a1mobile
runs our *pointed webhook* when the call is answered, and that webhook is what
the call actually says. All three are one command:

```bash
# 4. call server + tunnel + point the number, then prove it from outside
./phone.sh up
```

That is the whole thing. It starts `voice-webhook.js` on :4003, opens a tunnel
(cloudflared, or ngrok, or `CREW_TUNNEL_URL` if you have a fixed domain),
points the number at it, and finishes by running the preflight below.

**Re-pointing on every start is not laziness, it is the fix.** A free tunnel's
hostname changes each run, so a number pointed by hand yesterday now aims at an
address that no longer exists — and that failure is a phone that rings on stage
and then says nothing at all, which is worse than a call that never comes.

```bash
./phone.sh check        # the preflight — run it before every rehearsal
./phone.sh down         # put it away (run-demo.sh stop does this too)
./phone.sh say "the crew is done"     # smoke test: ring and speak
./phone.sh ask "anything else?"       # smoke test: ring, ask, print your answer
```

`check` is the one that matters. It fetches **our own `/health` back through the
public tunnel**, so it is testing the path Telnyx will actually take rather than
a convenient local equivalent — a dead tunnel or a stale pointing cannot pass it.
It also checks the team key, `CREW_PHONE`, the call server, transcription, and
warns loudly if either kill switch is left on.

`node a1mobile.js info` shows what the number is currently wired to.
`node a1mobile.js unpoint` reverts it to SIP if calls need to stop working.

## Nothing external: the deterministic route

The real path needs five things up at once. This needs none of them:

```bash
./run-demo.sh phone-fake     # real agents, simulated phone
./demo phone-fake            # the same, as the stage script
```

`CREW_PHONE_FAKE=1` makes `crew_send_sms`, `crew_place_call` and `crew_ask_user`
resolve inside the bridge process — no key, no tunnel, no Telnyx, no whisper, no
network. `crew_ask_user` returns a keyword-matched canned answer (the rehearsed
"which meeting wins" question gets the rehearsed answer), so the same run
produces the same show every time. Override one with `CREW_FAKE_ANSWER`.

The dock performs it identically: the character still says it is calling you,
still says what you "said", and the crew still works from that answer. Only the
ringing is missing. The bridge log says `[PHONE FAKE — no phone will ring]` so
the operator can never be the one who is fooled.

This is to the phone what `./run-demo.sh fake` is to the agents, and it is what
you reach for when the venue's wifi decides the demo is over.

## What the room sees while you are on the phone

An agent inside `crew_ask_user` is blocked for the length of the call and writes
nothing to stdout, so the bridge announces the call to the orchestrator
(`POST :4001/agent-event`) **before it dials**, and the answer after:

- the announcement carries the question, because the room can hear the
  characters but not your earpiece — this is how the audience knows what you
  are being asked while your phone is still ringing;
- the answer is spoken by the same character, and stored **on the task**, so
  every agent that runs afterwards is handed your decision instead of
  re-guessing it. The recap closes the show knowing what you chose.

Both lines jump ahead of the character's `Done:` sign-off rather than being
dropped by the chatty-agent line budget — a phone that really rang always gets
a line on stage.

## Rehearsal kill switch

`A1MOBILE_DRY=1` on the orchestrator's env stages texts and calls without
sending them — the tools succeed and say "rehearsal mode" instead. A rehearsal
loop that really texts a phone thirty times numbs the human and risks rate
limits; flip this on for loops, off for the run-through and the show.

`./run-demo.sh fake` never touches any of this — fake mode spawns no agents,
so no tool can fire.

**Two switches, different jobs — do not confuse them:**

| | what it does | reach for it when |
|---|---|---|
| `A1MOBILE_DRY=1` | real client, real code path, send suppressed at the last step | rehearsing loops that would otherwise text a human thirty times |
| `CREW_PHONE_FAKE=1` | the whole phone is simulated in-process; nothing outside is touched | the key, tunnel, or network is gone and the show still has to happen |

`DRY` tells the agent "rehearsal mode". `FAKE` tells it the action was simulated
but to report it as done, so the narration stays intact — an agent that believes
it really texted someone will say so out loud, and that is a lie on stage.

## Proving it without a phone

```bash
node test-phone.js          # the whole loop, no key, no tunnel, no network
```

Covers the four things that fail silently: the deterministic route still
answers, `crew_ask_user` announces itself both before and after, the answer
carries the raw text for later agents, and a dead phone stack degrades instead
of killing the agent.

## Failure modes, and what they sound like

- No team key on the machine → phone tools fail with a sentence saying to set
  `A1MOBILE_TEAM_KEY`; every other crew tool is untouched.
- `CREW_PHONE` unset and no number given → readable error, nothing sent.
- Number not verified → the API refuses; the agent narrates on without it.
- `voice-webhook.js` not running → `crew_place_call` refuses to dial rather than
  ring a phone that would then speak the wrong script. `crew_ask_user` instead
  **degrades**: it comes back as a normal result saying the line is down and to
  decide alone. Being stuck is the state that agent was already in, and killing
  it would throw away the rest of its work for a phone call that never happened.
  It is told the line failed, *not* that you ignored it — we never rang, so we
  do not get to say you did not answer.
- `crew_ask_user` unanswered (no pickup, silence, whisper missing) → the agent
  is told "no answer, use your best judgment" as a normal result, not an error.
- Timing: an ask can take up to `CREW_ASK_WAIT_MS` (120s), and in `direct` mode
  the orchestrator now sizes its per-agent kill timer around that automatically
  (`ASK_WAIT_MS + 120s`) instead of the flat 180s. That flat number was a real
  bug: an agent that asked 70s into its run was SIGKILLed while the human was
  still mid-sentence, and the character then said "ran out of time" to a room
  that had just watched the presenter pick up. **If you override
  `AGENT_TIMEOUT_MS` by hand, keep it above `CREW_ASK_WAIT_MS`.**
- Transcription is ours because a1mobile does not forward Telnyx's own
  `transcribe` callback (verified live 2026-08-09): OpenAI's transcription API
  when a key exists (`OPENAI_API_KEY` env or repo-root `.env`, gitignored),
  local mlx-whisper via `uvx` otherwise. The audio lives only in a temp dir
  for the seconds it takes to transcribe, then the whole dir is deleted.

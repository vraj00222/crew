# Crew — team coordination

This file is the single source of truth for the day. Commit it to the repo root and push often — pull before you start each new chunk of work, and update your row every time you finish a milestone (not just at lunch/end of day).

**The contracts below are frozen.** All three of you build against them starting now, in parallel, without waiting on each other. If one genuinely needs to change, post in the group chat first — everyone else is already coding against the version below.

**Testing discipline:** test after every change, not at the end of the day. If you've gone more than ~20-30 minutes without actually running what you built, stop and run it. A pile of untested code the night before a demo is the thing that kills demos.

---

## Devices (this matters — see note below)

**New here? Read [`docs/onboarding.md`](docs/onboarding.md) first — 5 minutes, and it
gets you from `git clone` to a running demo in about sixty seconds.** This file is the
live state of the day; that one is the process, the file-ownership map (how we avoid
conflicts), and the merge ritual.

- **A — Vraj** — Claude Max, **Mac** — **confirmed demo machine**
- **B — Sameer** — Windows
- **C — Abhishek** — Mac
- **D — Yaseen** — character art + visual identity *(new)*
- **E — Rukaiya** — rehearsal, resilience, backup rig *(new)*

Subscriptions: A Claude Max; B OpenAI Plus + Claude Pro; C Claude Pro.
D and E — put yours in your row so we know what you can run.

**Why this matters:** the mic-loopback trick (BlackHole, `say`, switching the system audio input) is macOS-only tooling. B can't run that spike locally. But most of B's work — the MCP server, the demo-seed scripts, and testing the human→VoiceOS→orchestrator hop with VoiceOS-for-Windows and B's own voice — has zero Mac dependency. Only the inner loop (agent speaks → VoiceOS hears it) needs a Mac, and now that we know which one, no need to set it up twice.

**The live demo runs on ONE physical Mac: A's.** Dock, orchestrator, and VoiceOS all need shared local audio I/O, so everything converges there regardless of who built what. A should treat their own laptop as the integration target from today onward — install VoiceOS, BlackHole, and get the orchestrator running there directly rather than developing it somewhere else and moving it later. C keeps developing on their own Mac (normal Xcode flow, less friction), but should not wait until 5:45pm to try running the build on A's machine for the first time — get it over there and working at least once mid-afternoon, so any Xcode-version or code-signing surprise shows up with time to fix it, not during the rehearsal window.

---

## Ports (localhost — don't change these)

- **4001** — orchestrator API (owned by Person A)
- **4002** — lil-agents dock status listener (owned by Person C)

## Interface 1: VoiceOS bridge → Orchestrator

Owned by **A**, called by **B**.

```
POST http://localhost:4001/start-task
Body:     { "instructions": "clean up my inbox and schedule everything" }
Response: { "taskId": "task_123", "status": "started" }

GET http://localhost:4001/status/:taskId
Response: { "taskId": "task_123", "status": "running" | "done", "agents": [
  { "name": "triage", "state": "working" | "done", "lastMessage": "..." }
] }
```

**B builds against a fake version of this immediately** — don't wait for A's real implementation. Stub it, integrate, swap the stub for the real thing later.

## Interface 2: Orchestrator → Dock

Owned by **C**, called by **A**.

```
POST http://localhost:4002/agent-status
Body: { "character": "triage" | "scheduler" | "recap", "message": "Archived 3 newsletters", "state": "working" | "done" | "idle" }
```

**A can test this with curl before C's Swift listener exists** — and C can test the listener with curl before A's real orchestrator exists. Neither of you should be blocked on the other.

---

## Folder structure

```
crew-hackathon/
├── COORDINATION.md          <- this file
├── orchestrator/            <- Person A
│   ├── src/
│   │   ├── index.ts         (HTTP server: /start-task, /status/:id)
│   │   ├── router.ts        (hardcoded task -> agent-role mapping, NOT a general planner)
│   │   ├── claude-runner.ts (spawns headless `claude -p` sessions per role)
│   │   └── agents/{triage,scheduler,recap}.ts
│   └── prompts/              (the actual scripted role prompts)
├── voiceos-bridge/           <- Person B
│   ├── mcp-server/           (exposes run_crew_task to VoiceOS — cross-platform)
│   ├── audio-loopback/       (BlackHole spike + speak-and-route scripts — written by B, run by A)
│   └── demo-seed/            (seeds the demo Gmail/Calendar account — cross-platform)
├── lil-agents-dock/           <- Person C, separate repo, forked from
│                                 github.com/ryanstephen/lil-agents
└── docs/
    └── demo-script.md         (the exact rehearsed run — write ~5pm)
```

---

## Model / effort quick reference

| Person | Sub | CC default model | Use | Effort |
|---|---|---|---|---|
| A | Max | Opus 5 | `opusplan` for routing/architecture decisions; drop to `sonnet` for writing the role prompts and boilerplate | high, medium for repetitive bits |
| B | Plus + Pro | Sonnet 5 | Claude for MCP server + demo-seed script logic; Codex (Plus) for the mechanical Gmail/Calendar scripting | medium default, high only for tricky integration debugging |
| C | Pro | Sonnet 5 | Claude for the Swift/AppKit listener; `haiku` explicitly for pure boilerplate (JSON parsing, simple HTTP) | medium/low for boilerplate, high for AppKit changes and the audio spike |

Switch anytime with `/effort` or `/model`. If usage gets tight, add `--fallback-model sonnet,haiku` so a session degrades instead of stopping.

**Agent teams (optional, inside your own session):** Claude Code has an experimental feature for spawning multiple teammates that message each other and split work — set `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. Keep it to 2-3 teammates and pin them to Sonnet, not Opus — teams burn tokens fast, not worth it on a Pro plan.

---

## Status

| Person | Workstream | Status | Blocked on |
|---|---|---|---|
| **D — Yaseen** | character art + visual identity | **not started — read `docs/onboarding.md`, then your task block below** | nothing. Your work is new files only; you cannot be blocked by us |
| **E — Rukaiya** | rehearsal, resilience, backup rig | **not started — read `docs/onboarding.md`, then your task block below** | nothing. Needs a Mac that is not A's |
| A | orchestrator + dock + audio rig | **CHECKPOINT READY — everyone run `./checkpoint.sh`, see the Checkpoint section at the bottom.** Orchestrator done, 3 modes (`narrate`/`live`/`voice`) selected by a flag not a file edit. Audio split decided + measured. 10/10 lines spoken, 0 dropped. Three accents + written personalities. Characters no longer freeze. `docs/demo-script.md` written. Full chain with real agents: ~45s, PASS | VoiceOS Pro trial not active — still the only thing left on A's side |
| B | voiceos-bridge (mcp-server + demo-seed + Gmail/Calendar tools) | **CHECKPOINT PASS on Windows (14 ok / 0 failed).** All 8 tools built and tested; `verify.ps1` now runs **6 suites, all green**. **`crew_task_status` closes the loop: no taskId needed, and it answers in a spoken sentence instead of a JSON dump** — see below. Tool `annotations` declared on all 8 tools, honestly. Gmail decision made; A unblocked. VoiceOS installed on Windows and inspected — see the tool-naming finding. **A: two things for you in Blockers — `direct` mode has no MCP wiring, so rung 3 narrates without touching anything, and `checkpoint.sh`'s claude check is a false green. Plus one bug in `CANNED`, off the rehearsed path.** | VoiceOS Pro trial (same paywall as A, now confirmed on a 2nd machine) + a demo Google account & OAuth creds |
| C | crew-dock (took option 2) | **the dock talks, and the handover is proven.** `Narrator.swift` speaks every `/agent-status` line via `say`, per-character voices, never two at once. Re-verified this morning from a **throwaway clone of current `main`** — clone → speaking app in 13s. **A's audio split + new voices then re-verified on my Air against A's unmodified `run-demo.sh`: 16 received, 10 spoken, 0 failed.** Nothing left to hand-carry to A's Mac but two commands. **Reviewed and kept A's character fix — verified by screen capture, not by log — and fixed the stale-binary hole that let `checkpoint.sh` PASS while grading an old build** | **nothing — CHECKPOINT PASS on my Air (14 ok / 0 failed)** |

### ✅ FULL CHAIN INTEGRATED — B's MCP server → A's orchestrator → A's dock

Run on A's Mac (the demo machine), not claimed from Windows:

```
ok  initialize     -> crew v0.1.0, proto 2025-06-18
ok  tools/list     -> [run_crew_task, crew_task_status]  (survived a split frame)
ok  run_crew_task  -> "The crew is on it. Task task_1 started"
PASS — spoken phrase would reach the orchestrator.
```
…and all 16 status lines then landed on the dock in correct order, ending with
`recap [done]`. **Everything from a spoken phrase to characters talking on screen now
works.** The only untested link left in the whole system is VoiceOS itself hearing the
audio — and the audio path into it is already proven separately.

B's server also runs clean on macOS/Node 25 (it was written on Windows/Node 24), and
its `.gitattributes` LF fix is a real save — a `.sh` committed from Windows would have
landed CRLF and died as `bad interpreter: /bin/bash^M` on the demo Mac.

**Bug that integration testing caught and A fixed:** dock POSTs were fire-and-forget
`fetch()` calls, so they raced — `waking up` was arriving *after* a later line. On stage
that reads as a character going backwards. They're now serialized through one promise
chain, and re-verified in order.

### What A needs from each of you

**B —** the one decision that blocks your build: **Gmail has no path through VoiceOS**
(`connectedIntegrations` is `["applecalendar"]`, and there are no email actions in
`nativeActionToggles`). But Apple Mail *is* scriptable from inside VoiceOS. Pick one and
put it in the decisions log: MCP owns Gmail / Apple Mail carries the inbox / the inbox
half is narrated over seeded data. Until that's decided I can't write the real execution
prompt — it's stubbed to dry-run and swaps in one file (`orchestrator/prompts/execution.md`,
both options already written and commented out).
You can build and test your MCP server against `FAKE=1 node orchestrator/server.js`
right now without anything of mine being finished.

**C —** read the Xcode note below *before* you build anything, it changes your handover.
Also: **don't add your own queueing or delay** to incoming messages. I pace narration at
~1.4s/line on the orchestrator side so the characters have a readable rhythm; if you
delay on top, lines drift behind the agents. Lines arrive pre-truncated to 110 chars so
they fit a bubble. Test against `curl` or `./run-demo.sh fake` — you are not blocked on me.

### B — what VoiceOS for Windows actually looks like (installed and inspected)

VoiceOS is now installed on B's Windows box. Four findings, one of which **changes A's
prompts**.

**1. `voiceos add mcp` DOES NOT EXIST on Windows.** The install is a single
`VoiceOS.exe` (Electron) and ships no command-line interface at all. The command in the
brief and on the website is Mac-only or docs-only. **Registration is in-app**: tray icon →
window → Settings → MCP/custom servers. It writes to `customMcpServers` in
`%APPDATA%\VoiceOS\config.json` — same schema as A's Mac, different path. Don't hand-edit
that file while the app is running; it's an electron-store and the app rewrites the whole
thing on its own schedule, so the entry silently vanishes.

**2. ⚠️ A — THIS CHANGES YOUR PROMPTS. VoiceOS renames every custom MCP tool.** Its own
integrations are registered as pseudo-MCP servers, and the bundle contains
`NAME_PREFIX = "custom_mcp_voiceosapplemail_"`, plus
`custom_mcp_voiceoschatgpt_send_instruction`, `custom_mcp_voiceosspotify_`,
`custom_mcp_voiceosnotes_`. So the scheme is:

```
custom_mcp_<servername>_<toolname>
```

Our `crew_gmail_archive` is **not** callable as `crew_gmail_archive` from inside VoiceOS —
it becomes something like `custom_mcp_crew_crew_gmail_archive`.

**Narrowing my own claim, having now read A's three prompt files:** this does **not** affect
`execution-direct.md`. There the agents connect to our MCP server directly and the names are
unprefixed exactly as A wrote them — I checked all six against the built tools and they
match. And it does **not** affect `execution-voice.md` either, because in voice mode the
agent speaks English and VoiceOS picks the tool itself; there are no tool names in that
prompt at all. A's files are correct as written.

Where it *does* matter: **voice mode depends on VoiceOS choosing our tool from a spoken
sentence**, which keys off the tool *descriptions*, not the names. I wrote them for exactly
that — `crew_gmail_archive` says "archive messages out of the inbox… plain-English query
like 'newsletters'". And when we debug "why did nothing happen when the agent said it",
the name to look for in VoiceOS's logs is the prefixed one, not ours. Worth knowing before
5pm rather than during.

**3. Confirmation is per-tool, declared, not a global setting.** VoiceOS's tool
declarations carry a `requiresConfirmation` boolean (Apple Mail's read tools ship
`false`), and there's an `AGENT_CONFIRM_REQUIRED` code path. That's consistent with A's
finding 6 and with the website: **no global bypass exists**. What we don't yet know is
whether VoiceOS derives `requiresConfirmation` from the MCP spec's tool `annotations`
(`readOnlyHint` / `destructiveHint`) — the MCP SDK carrying those is bundled. **If it
does, our tools can declare themselves non-confirming and the loop is fully autonomous.**
Worth 5 minutes the moment the trial is live: register, call `tools/list`, and see whether
flipping `readOnlyHint` changes the confirmation behaviour. A's voice-answered-confirmation
path is the fallback and is already known to work.

**4. Windows has no native mail path at all** — `connectedIntegrations` is `[]`, and Apple
Mail is macOS-only, so finding 7 doesn't transfer. `nativeActionToggles` is the same list
as the Mac (editText, insertText, openApp, setVolume, controlPlayback, reminders) — **no
email, no calendar-write**. This independently confirms MCP-owns-Gmail was the right call:
on Windows there was never another option.

**Blocked the same way A is:** the app opens onto "Start your 7-day free trial"
($143.88/yr after), onboarding terminates there with no skip, and `onboardingCompleted`
stays `false`. I did not start a paid trial — **the event's free month should be redeemed
on the account instead.** Everything else is staged: `register.ps1` audits the Windows
config, prints the exact command/args, and self-tests the server before you register.

### B — what shipped this morning

**`voiceos-bridge/demo-seed/` — done, dry-run verified.** `uv run seed.py --dry-run` builds
all 18 RFC822 messages and 8 calendar events, asserts the counts, and needs **no
credentials and no network** — so it's testable now and testable on any machine.

The fixture is matched to `prompts/execution.md` **exactly**: same 6 newsletters (Verge,
Morning Brew, Substack ×2, LinkedIn, Product Hunt), David Chen on the Q3 rollout, Priya
Nair on the contract. If either file changes, change both, or triage narrates an inbox the
audience can't see. The counts are load-bearing too — 6 newsletters + 8 noise archived, 2
meeting requests to the scheduler, **exactly 2 left**, which is what makes C's spoken line
*"Done: inbox down to two real emails"* literally true on screen. `--dry-run` fails if that
drifts. Two calendar gaps are deliberately free: **tomorrow 14:00 for David Chen**,
day-after 10:00 for Priya. Fill either and the demo's best line stops being true.

It inserts rather than sends (fake `.example.com` senders), marks everything it creates so
`--wipe` can't touch real mail, and prints the target account and message count before
writing — `batchDelete` is permanent and the account is whatever `token.json` holds.
**Still needs a demo Google account + OAuth `credentials.json`; neither exists yet.**
Budget 10 minutes the first time it points at a real account.

**`mcp-server/register.ps1`** — finds VoiceOS on Windows, audits its config for the same
things A found by hand on the Mac (`muteWhenDictating`, `agentVoiceEnabled`,
`connectedIntegrations`, `onboardingCompleted`, and any confirm/trust key), and prints the
exact registration. Reads an allowlist of keys only and never dumps the file — same token
hygiene A flagged.

**Independent confirmation of A's finding 6:** VoiceOS's own site states that anything
which sends, books, or changes something stops and shows you what it will do first. So the
human-click confirmation is documented product behaviour on **both** platforms, not a Mac
quirk or a trial limitation — there is no setting we're failing to find. A's discovery that
confirmations can be answered *by voice* remains the thing that makes the loop autonomous,
and it's still the highest-value thing to test the moment the Pro trial lands.

**For the group — the Windows equivalent of the audio rig, if we ever want it:** VB-CABLE
(virtual audio device, the BlackHole analogue) + `System.Speech.Synthesis.SpeechSynthesizer`
for TTS + the `AudioDeviceCmdlets` module to switch the default input. **Not needed for
tomorrow** — the demo runs on A's Mac regardless — but if macOS's `fn` key keeps being
unsynthesizable and VoiceOS's Windows trigger turns out to be a normal chord, simulating
the trigger could be *easier* on Windows. Worth 10 minutes only if the Mac trigger blocks us.

### Read this first: `/crew` skill

There's a project skill at `.claude/skills/crew/SKILL.md`. In your Claude Code session
in this repo, type `/crew` — it loads the frozen contracts, the commands to test your
own side without waiting on anyone, the commit ritual, and the machine gotchas that
have already cost us time. Use it instead of re-reading this whole file.

### One-command demo (works right now, no VoiceOS needed)

```bash
./run-demo.sh fake     # whole pipeline, canned narration, zero Claude spend
./run-demo.sh          # whole pipeline, real headless agents, ~30s
./run-demo.sh stop
```
This starts the dock, starts the orchestrator, fires the demo phrase, and prints the
narration as it happens. **`fake` is the panic button** — if agents are failing at
5:55pm, that still puts on the entire show with no Claude calls and no network.

### A — dock app also built (crew-dock/), because of an Xcode problem

**C: read this before you hand anything over.** The demo Mac has Command Line Tools but
**no full Xcode** — `xcodebuild` does not run on it. lil-agents ships an `.xcodeproj`
plus a Sparkle dependency, so *the upstream project cannot be built on the machine we
are demoing from.* This is exactly the surprise we were trying to avoid finding at 5pm.

Two ways out, your call:
1. You keep your Xcode flow and hand over a **pre-built `Crew.app`**, not source. Bring
   it over mid-afternoon as planned and we just run it.
2. Use `crew-dock/` — I built a minimal one that compiles with `swiftc` alone in ~2s,
   no project file, no dependencies, no signing. Borderless click-through windows above
   the dock, one per agent, looping character video with a speech bubble. It already
   accepts the exact `/agent-status` payload and logs every message it receives to
   stderr. It's deliberately plain — if you want to make it good, this is the base to
   build on and you won't fight a build system on demo day.

Character art is fetched from lil-agents (MIT) at build time, not committed.

### C — took option 2, and added the missing half: the dock now speaks

Agreed, `crew-dock/` is the right base — my Mac has the same problem (Command Line
Tools, no Xcode), so option 1 was never really on the table. Confirmed `build.sh`
works from a clean clone on a second machine: ~15s, no Xcode, no signing.

**A — the handover you were expecting me to hand-carry is just this (verified, not
assumed).** I threw away my working copy and ran a fresh `git clone` of current `main`
into an empty directory, as your Mac will experience it:

```sh
git clone https://github.com/vraj00222/crew.git
cd crew && ./crew-dock/build.sh      # 13s, including fetching the art
./crew-dock/Crew.app/Contents/MacOS/Crew
```

Clone → speaking app in **13 seconds**, then the full `FAKE=1` run: 3 characters,
8 spoken lines, all three voices, correct order, dock still alive at the end.
No Xcode, no signing, no `npm install`, nothing to copy off my machine.

The one part worth knowing: **`crew-dock/Assets/` is `.gitignore`d** — it's 18MB of
video and it belongs to upstream lil-agents (MIT). It is *not* in the repo, so a clean
clone has no character art. `build.sh` shallow-clones lil-agents and copies the two
`.mov`s in on first build. That works, and I've now watched it work from empty — but
it means **the first build on your Mac needs network**. If the venue wifi is bad on the
day, build once before you leave, or copy `crew-dock/Assets/` over by hand; after that
the check is a no-op and every later build is offline and ~3s.

`crew-dock` updated bubbles but never made a sound, so the "agents narrate themselves"
half of the demo was silent. `Sources/Narrator.swift` fixes that.

**A, on "don't add your own queueing or delay" — I did not delay the bubbles.**
`dock.apply()` still fires the instant a POST lands; your 1.4s pacing is untouched and
the characters keep your rhythm. But speech can't work that way: a line takes ~2s to
*speak*, so at 1.4s/line something has to give — overlap (garbled, and unusable for
VoiceOS), queue (drifts), or skip. What it does:
- bubbles: immediate, never queued
- speech: one `say` at a time, never two characters talking over each other
- speech trails the bubbles by a few seconds and skips lines only if it falls
  more than 4 behind — reads as a character finishing its thought
- a `Done:` line is **never** dropped — the sign-off always gets said
- `"waking up"` is shown in the bubble but not spoken (it was costing a real line)

**Tuning note, worth knowing:** two agents narrating in parallel share one voice
channel, so lines arrive faster than they can physically be spoken. My first pass
dropped over half the run — including *"Booking two PM with David Chen"*, the line the
whole demo exists to produce. Raising the backlog to 4 and `say -r 200` fixed it.
Current run speaks 8 lines and this is the whole script, in order:

```
[Samantha/triage]    Scanning the inbox.
[Daniel/scheduler]   Reading the flagged emails.
[Samantha/triage]    Archiving six newsletters.
[Daniel/scheduler]   Booking two PM with David Chen.
[Samantha/triage]    Done: inbox down to two real emails.
[Daniel/scheduler]   Done: two meetings on the calendar.
[Karen/recap]        Pulling together what the crew did.
[Karen/recap]        Done: inbox cleared, two meetings booked.
```

Two lines get skipped ("Flagging two emails…", "Finding open slots tomorrow"). **A —
if you want every line spoken, drop your `LINE_MS` pacing to ~2200 and I'll raise the
backlog; the ceiling is speech rate, not the dock.**

**Stage timing — this one belongs in the demo script.** Speech trails the bubbles, so
the run is not over when the orchestrator says it's over. Measured on a `FAKE=1` run:
orchestrator reports `status: done` at **+8s**, but the last utterance —
*"Done: inbox cleared, two meetings booked."*, the closing line of the whole demo —
only *starts* at **+15s** and runs ~3s past that. **Don't cut the room, stop talking,
or hit the next slide when the terminal says done — there are ~10 more seconds of
audience-facing audio.** Whoever drives on the day should be watching the dock, not
the log.

**Rehearsing twice in a row is safe.** The narrator drops consecutive duplicate lines
per character, so I checked whether a second run on a still-running dock would go
silent — it doesn't. Ran the same task twice against one dock process: all 8 lines
spoken both times, same order. (`run-demo.sh` restarts the dock anyway, so this only
matters if you re-fire the task by hand between rehearsals.)

Knobs: `CREW_MUTE=1` silences narration entirely. `CREW_AUDIO_DEVICE="…"` picks the
output device. `CREW_RATE` sets words-per-minute (default 200).
`CREW_VOICE_TRIAGE` / `_SCHEDULER` / `_RECAP` override voices
(default Samantha / Daniel / Karen).

**Debugging on the day:** the dock logs `DOCK <- …` and `SAY -> …` to stderr, but
`open Crew.app` throws stderr away. To see it, run the binary directly:
`./crew-dock/Crew.app/Contents/MacOS/Crew` — that is the only reliable way to answer
"did it actually speak?". Anything that went wrong with the audio prints as `SAY !!`.

**A, small trap that cost me ten minutes and will cost you more at 5pm:**
`orchestrator/test.sh` starts its *own* `fake-dock.js` on :4002 and `server.js` on
:4001. Run it while the demo is up and both fail to bind, and it reports
`FAIL: nothing reached the dock` — which reads exactly like a real regression in my
listener. It isn't. `./run-demo.sh stop` first, then `test.sh`. (Clean run this
morning after the narrator change: `PASS — contract, routing, and dock push all good`.)

Three bugs found by running it, all of which would have hit on stage:

1. **The app crashed outright on a fast burst of messages.** Swift's `suffix()` returns
   a slice that keeps the parent's indices, so inserting at 0 traps. The dock died
   silently and the orchestrator's `fetch(...).catch(() => {})` swallowed the connection
   error — so the orchestrator log printed a flawless run while the screen was empty.
   Fixed, stress-tested with 13 back-to-back POSTs.
2. **The narrator wedged after one line and went silent for good.** It relied on
   `Process.terminationHandler` to advance the queue and that doesn't fire reliably;
   one missed callback silenced the dock permanently. Now it blocks on
   `waitUntilExit()` instead, with a 15s watchdog.
3. **A bad `CREW_AUDIO_DEVICE` made the dock totally silent while the log looked
   perfect — and it was sitting right on the path A is about to take.** `say -a` reports
   an unknown device on *its* stderr, which the narrator sent to `/dev/null`, and it
   never checked the exit code. So `CREW_AUDIO_DEVICE="BlackHole 2ch"` on a Mac where
   BlackHole isn't installed yet — or with the name a word off — printed a flawless
   `SAY ->` for all 8 lines and made **no sound whatsoever**. Verified:
   `say -a "BlackHole 2ch"` → `Found no Audio Output Device matching`, exit 1.
   Now the device name is resolved **once at startup** against `say -a '?'`; an unknown
   one logs `SAY !!` with the list of real devices and **falls back to the default
   output** rather than going quiet — the dock is the audience channel, so the default
   is the safe way to fail. A nonzero `say` exit is now logged per line too, so the log
   can no longer claim a line was heard when it wasn't. Tested bogus / valid / unset.

**Takeaway for everyone: the orchestrator log is not evidence that anything reached the
audience.** It reports what it *sent*. Confirm against the dock's own stderr. Bug 3 is
the same trap one layer down — even `SAY ->` only proved the dock *asked* for audio.

### A — orchestrator: ready to integrate against (Sat 23:5x)

Run it: `node orchestrator/server.js` (add `FAKE=1` for canned agents, no Claude spend).
Smoke test: `orchestrator/test.sh` → prints `PASS`. Fake dock listener: `node orchestrator/fake-dock.js`.

Verified working, not just written:
- `POST /start-task` → `{"taskId":"task_1","status":"started"}`
- `GET /status/:id` → all three agents, correct shape
- 3 real headless `claude -p` sessions (triage ‖ scheduler, then recap) — **28 seconds** wall clock
- every narration line pushed to `:4002/agent-status`

**Two clarifications to the frozen contract — no shape change, just be aware:**
1. An agent's initial `state` is `"idle"` until it wakes. So `/status` can return `idle`
   as well as `working`/`done`. `idle` is already in C's dock contract; B should treat
   anything that isn't `done` as still running.
2. The final `Done:` line is POSTed to the dock **twice** — once as `working`, then
   again as `done`. That's deliberate: the second one is the state signal that tells C's
   character to stop animating. C, dedupe on message text if it looks odd, but key the
   animation off `state`.

**C — narration pacing is mine, not yours.** Lines arrive on a steady ~1.4s beat
(`LINE_MS` env var) regardless of how fast the model actually emits them, so the
characters have a readable rhythm. Don't add your own queueing/delay on top or lines
will lag behind the agents. Max 8 lines per character, and lines are pre-truncated to
110 chars — they'll fit a speech bubble.

**B — routing is keyword-based** (`orchestrator/server.js`, `rolesFor`): `inbox|email|mail`
→ triage, `schedul|calendar|meeting|book` → scheduler, `recap` always runs last. If
nothing matches it spawns both anyway, so a garbled transcript still puts agents on
screen. Send me the raw transcript; don't try to normalize it first.

## Tonight's spike result (A runs it, on A's own Mac — the confirmed demo machine. B joins remotely to help write/debug the script. C can try the same spike independently on their own Mac as a quick parallel sanity check — not required, but a second confirmation is useful if A hits a snag.)

- BlackHole + `say` + VoiceOS mic: **BLOCKED, not failed — VoiceOS Pro trial not active on A's account yet.** All the plumbing around it is installed, scripted and dry-run verified; the moment the trial lands this is a ~5 minute test. See "How to finish the spike" below.
- **THE AUDIO PATH WORKS — measured, not assumed.** `./spike.sh verify` speaks through the
  `crew` multi-output device, records off BlackHole's input, and reads the level back:
  **peak amplitude 0.80, no clipping**, signal confined to the first ~2s matching the
  utterance. BlackHole has no microphone, so audio can only have arrived via the digital
  loopback. **`say` → BlackHole → mic input is proven.** This needed no VoiceOS and no Pro
  trial, and it was the project's single biggest unknown.
  → run `./spike.sh verify` before rehearsal; it's a 8-second self-contained check.
- What that leaves: the only untested link is now "does VoiceOS *transcribe* what it
  receives" — a far smaller risk than "does audio arrive at all", which is settled.
- BlackHole itself: **installed and working.** `blackhole-2ch` + `switchaudio-osx` in, multi-output device **`crew`** (BlackHole + MacBook Pro Speakers, drift correction on the speakers) built and switchable from the CLI. Verified routing on/off cleanly. `sox` added for the verify check.
- VoiceOS trigger key rebindable away from physical Fn: **YES — confirmed**
- VoiceOS auto-confirm / trust setting for agent actions: no on/off switch in the config, **but confirmations can be answered by voice** — see finding 6, this is better news than a trust setting
- B's Windows test: **VoiceOS IS now installed on B's machine — and it is paywalled exactly like A's.** See "B — what VoiceOS for Windows actually looks like" below. Still NOT RUN, but the reason changed from "not installed" to "same trial gate A is stuck behind, on a second machine". ~~NOT RUN — VoiceOS is not installed on B's machine~~ (superseded)
- _(historical)_ ~~VoiceOS is not installed on B's machine~~ and installing it needs a download plus an account sign-in, which isn't something B can script. Everything on B's side of that test is ready and automated (`voiceos-bridge/mcp-server/register.ps1` finds VoiceOS, audits its config, and prints the exact registration). **This never blocked the demo**: the same hop was proven on A's Mac end to end, which is the machine we're demoing from. Treat the Windows test as a nice-to-have second data point, not a gap.
- **Decision:** still pending the audio test. Nothing found so far rules the voice loop out; two settings that would have silently broken it are now known and scripted.

### What A found in VoiceOS's own config tonight

VoiceOS is an Electron app; its live settings are plain JSON at
`~/Library/Application Support/VoiceOS/config.json`. That file settled several
questions without guessing. **Do not commit or paste that file anywhere — it holds
live auth tokens.** Findings only, below.

1. **Trigger key is rebindable — and we will HAVE to rebind it.** `keyboardShortcuts`
   is a list of key-chords; there's already a non-Fn chord registered
   (`control-left + option-left`), which proves arbitrary combos work. This matters more
   than it looks: **`fn` cannot be synthesized in software** on macOS — it's handled below
   the layer that `CGEvent`/AppleScript can post. So anything that needs to trigger
   VoiceOS programmatically must use a normal chord. Rebind before rehearsal, not during.

2. **`muteWhenDictating: true` — this may kill the voice loop outright.** VoiceOS ducks
   system audio while it's listening. Our loop is: agent speaks via `say` → system audio
   out → BlackHole → VoiceOS mic. If VoiceOS mutes output the moment it starts listening,
   it mutes the very thing it's supposed to hear. **Set this to false before testing**, or
   the spike will fail for a reason that has nothing to do with BlackHole.

3. **`agentVoiceEnabled: true` — feedback loop risk.** VoiceOS talks back (voice
   `xai-ara`). In a loopback rig every sound out goes into the mic, so VoiceOS would hear
   its own replies and re-trigger itself. **Turn agent voice off for the demo.**

4. **Gmail is not connected to VoiceOS at all.** `connectedIntegrations` is
   `["applecalendar"]` — Apple Calendar only, no Google. And `nativeActionToggles` covers
   editText / insertText / openApp / setVolume / controlPlayback / reminders — **no email
   actions, no calendar-write actions**. So "clean up my inbox" has no native VoiceOS path
   today. B: this is your call to make early — either the MCP server carries Gmail
   entirely, or the demo's inbox half is narration over seeded data.
   `customMcpServers: []` is empty and is where your server registers.

5. Onboarding is not finished (`onboardingCompleted: false`, stuck at step 15). Worth
   completing tonight in case it gates Agent Mode.

6. **Confirmations look answerable by voice — which may be the whole ballgame.** There's
   no confirm-bypass setting (`nativeActionToggles` are per-action-type on/off switches,
   not a trust level). But strings inside the app include `emitVoiceConfirmation`,
   `classifyAgentConfirmationIntent`, and the log line
   `[AgentInputService] Reply is unrelated to pending confirmation` — i.e. VoiceOS listens
   for a **spoken** reply to a pending confirmation and classifies it as approve/deny.
   If that holds, an agent can approve its own action by saying "yes", and the loop stays
   autonomous without any trust setting. **This is the single highest-value thing to test
   the moment the trial is active.** If it works, the human really does speak only once.

7. **Apple Mail is scriptable from VoiceOS.** The bundle contains AppleScript over
   `applemail` (`repeat with anEmail in inviteeItems`). So the inbox half has a native path
   after all — via Apple Mail, not Gmail's API. B: worth weighing against the MCP route,
   since it needs no OAuth.

### How to finish the spike (~5 min once the Pro trial is on A's account)

```bash
voiceos-bridge/audio-loopback/voiceos-setup.sh apply   # settings; backs up + reverts cleanly
voiceos-bridge/audio-loopback/spike.sh demo            # room hears it AND VoiceOS hears it
voiceos-bridge/audio-loopback/spike.sh say "The quick brown fox jumps over the lazy dog"
sqlite3 -readonly ~/Library/Application\ Support/VoiceOS/voiceos.db \
  "SELECT created_at, final_transcription FROM dictations ORDER BY rowid DESC LIMIT 3;"
voiceos-bridge/audio-loopback/spike.sh off             # ALWAYS — else you have no mic
```

The `dictations` table is the verification hook: it is **currently empty**, so any row that
appears is unambiguously from the loopback. Use an inert phrase first — prove transcription
before proving actions, so a failed booking doesn't get blamed on the audio path.

Two gotchas already paid for:
- **`spike.sh off` is not optional.** Leaving input on BlackHole means the Mac has no
  working microphone, and it is not obvious why. A's config was restored after testing.
- **The room can't hear anything right now.** In the `crew` multi-output device, the
  MacBook Pro Speakers volume slider is near zero while BlackHole's is maxed. VoiceOS will
  hear the agents perfectly and the audience will hear silence. Raise the speakers slider
  in Audio MIDI Setup before rehearsal.

Triggering, for the demo design: `fn` **cannot** be synthesized in software, so no script
can press it. That is fine — hands-free mode (`fn`+`space`) is a single human press that
leaves VoiceOS listening, which is exactly the "human speaks once" beat we want. Design the
demo around one hands-free press at the top, not a per-utterance trigger.

### A — the audio split (C: this is your answer, nothing for you to change)

**Your proposal, taken as proposed: separate the two streams by device, not by timing.**
Then it doesn't matter if they overlap — they can't reach each other. Measured on the
demo Mac rather than assumed:

```
dock narration -> "MacBook Pro Speakers" : BlackHole heard 0.000000   <- VoiceOS deaf to it
agent command  -> "BlackHole 2ch"        : BlackHole heard 0.804261   <- VoiceOS hears it
```

`./voiceos-bridge/audio-loopback/spike.sh split` is that check — 12 seconds, no VoiceOS,
no Pro trial. Run it before rehearsal alongside `verify`.

**One correction to your note: this Mac's speakers are `MacBook Pro Speakers`, not
`MacBook Air Speakers`.** Exactly the reason your resolver fix matters — I'd have set it
wrong and, before this morning, gone silent for it. `run-demo.sh` now exports the right
name, so you don't have to set anything.

Three consequences worth knowing:

1. **The `crew` multi-output device is off the demo path.** It existed to send audio to
   BlackHole *and* the speakers at once — which is precisely what we no longer want. That
   also retires the "speakers slider is near zero so the room hears silence" gotcha, since
   we stop using the device that had the slider.
2. **`run-demo.sh` launches the dock binary directly instead of `open`.** `open` discards
   stderr, and your `DOCK <-` / `SAY ->` lines are the only evidence a line reached the
   audience. The run now ends by printing what was actually spoken, from your log, not
   mine — and says so loudly if the dock received nothing.
3. **Speech trails the orchestrator by ~10 seconds.** The run script used to print its
   summary while Karen was still mid-sentence, which means anyone hitting
   `./run-demo.sh stop` on seeing "final" cuts the recap off. It now waits for the room
   to go quiet first.

**Your pacing question, answered with a measurement.** You offered to raise the backlog if
I dropped `LINE_MS` to ~2200. At 1400 I reproduced your result exactly — 8 of 10 spoken,
same two lines dropped. **At 2200 all 10 speak and the backlog never fills**, so no dock
change is needed at all; the ceiling really was speech rate, so the pacing had to meet it.
2200 is now the default in `server.js`. The show runs ~9s longer and nothing is lost.

### C — verified A's audio split on a second Mac (and hardened where it lands)

**A: agreed on all of it, nothing changed on my side. Confirmed your run reproduces on
different hardware** — I ran your `run-demo.sh fake` unmodified on my Air: **16 lines
received, 10 spoken, 0 failed, correct order, all three new voices.** Identical to your
demo-Mac numbers, and `LINE_MS=2200` does exactly what you measured — the backlog never
fills, so the skip logic never engages.

**Your `MacBook Pro Speakers` correction is the whole point, and my Mac proved it by
accident.** `run-demo.sh` hardcodes your speaker name, which does not exist on my Air.
Before this morning that combination was a *silent dock with a perfect-looking log*.
What actually happened instead:

```
SAY !! no audio output device named "MacBook Pro Speakers" — narrating to
       "MacBook Air Speakers" instead so the dock still speaks. Available: MacBook Air Speakers
```

Warned, named the real device, and spoke all 10 lines. **Nobody needs to set anything —
the hardcoded default is correct on the demo Mac and degrades safely everywhere else.**

**One thing I tightened after reading your commit.** My fallback originally went to the
*system default output*, and your rig switches the default output around. So in the one
scenario where the name fails to resolve on the demo Mac *while* the default is pointed
at BlackHole, the dock's narration would have fallen back **into VoiceOS's ear** — the
exact collision the split exists to prevent, arriving through the safety net. It now
prefers the **built-in speakers** explicitly (`…Speakers`), which is the audience channel
by definition and which a loopback device can never match. Tested both ways:
`"MacBook Pro Speakers"` and `"BlackHole 2ch"` each land on `MacBook Air Speakers`, out loud.

**Honest limit on that test:** BlackHole isn't installed on my Mac, so the device list I
tested against never actually contained it. The discriminating case — BlackHole present
in `say -a '?'` and correctly *not* chosen — holds by construction (`BlackHole 2ch`
doesn't end in `Speakers`), but it is unverified on real hardware. **A, `say -a '?'` on
your Mac lists both; if you ever see the dock warn and land somewhere other than
`MacBook Pro Speakers`, that's the case to tell me about.**

### C — checkpoint PASS, and the one thing the checkpoint wasn't checking

**`./checkpoint.sh` → CHECKPOINT PASS on my Air** (14 ok, 0 failed, 4 N/A — no
BlackHole/switchaudio/enhanced voices here, all expected for C).

**A — your character fix is right, I'm keeping it, and I nearly reported it broken.**
Read the diff and agreed on all of it: tempo instead of pausing, bob on real lines,
mirroring the recap. `play()` before `rate` is the correct order and the reason is real.

But I checked it the way you framed it — *by watching the screen instead of the log* —
and the first check said the character was still frozen. Same region of screen captured
three times 1.3s apart, pixel-identical:

```
9917ed171aaef9f327e4679f6efb1247   <- t+0.0
9917ed171aaef9f327e4679f6efb1247   <- t+1.3   frozen
9917ed171aaef9f327e4679f6efb1247   <- t+2.6
```

**The fix wasn't in the binary I was running.** After a rebuild, same test:

```
5ed214ed9f7f8fa43618766a863fb471   <- t+0.0
003e9fa573d9c2464aa8abe7a85cc446   <- t+1.3   walking
8a91b19b5b7a41ff4f70def7ccb1b5dc   <- t+2.6
```

**Why that matters to all three of us: `checkpoint.sh` said PASS while running a dock
binary older than the source it was grading.** Both `run-demo.sh` and `checkpoint.sh`
guarded on `[ -x … ]` — *existence*, never freshness. So `git pull` brings new Swift,
every check still passes, and you are testing the previous build. My binary was 08:35;
your `AgentCharacter.swift` was 10:02. The dock is the only compiled artifact in the
repo, so it is the only place this can happen — and it defeats the exact thing the
checkpoint exists to prove, that all three of us are running the same commit.

Fixed in both, and the failure is loud rather than silent:

```
FAIL  dock binary is OLDER than its sources — ./crew-dock/build.sh (you are testing stale code)
```

- `run-demo.sh` now rebuilds when `crew-dock/Sources` or `build.sh` is newer than the
  binary (swiftc is ~3s — no reason to be clever). It printed `building dock...` on the
  next run, as it should have this morning.
- `checkpoint.sh` **fails** on a stale binary instead of reporting `ok dock built`.

**A and B: if either of you ran `./checkpoint.sh` before this commit and did not rebuild
the dock by hand after pulling, that PASS did not cover the dock — please re-run it.**
Mine now passes on a binary provably newer than its sources.

Two touched files are A's. Both are one-line guards, no contract touched, and the same
class of thing as the `test.sh` port fix — shout if you'd rather own the change.

### A — the crew has voices now, not one robot with three sprites

Two halves, and the smaller one is the accent:

- **Accent** — `CREW_VOICE_*`, exported by `run-demo.sh`: **triage = Moira (Irish),
  scheduler = Daniel (British), recap = Karen (Australian)**. Three accents, so the crew
  reads as three entities. Audition alternatives by ear with `./crew-dock/voices.sh
  audition`; the winners are three env vars, no code change.
- **Words** — the bigger half, in `prompts/{triage,scheduler,recap}.md`. Each role now has
  a *Who you are* block: triage is dry and unimpressed and says the number, scheduler is
  brisk and pleased with a slot that fits, recap is warm and closes the loop. The line
  rules (≤10 words, `Done:` last, no markdown) are untouched and marked absolute in the
  prompt, so character can't cost us the format.

**One human action, ~2 minutes, worth more than either:** this Mac has **0 Enhanced or
Premium voices installed** — every voice on it is the compact 2005-era build, which is
the actual source of the robot sound. System Settings → Accessibility → Spoken Content →
System Voice → Manage Voices → download the Enhanced build of Moira, Daniel and Karen.
They resolve under the same `-v` name, so **nothing in the code changes** — the same run
just stops sounding synthetic. `./crew-dock/voices.sh check` tells you where you stand.

No new dependency for any of this: no TTS service, no API key, no network call on stage.

## Sponsors — what we can actually use, and where

**The rule that decides all three: nothing goes on the stage path that needs the network
at 6pm.** That is not caution for its own sake, it is why `./run-demo.sh fake` exists. A
sponsor integration that can take the demo down is worth less than the prize.

**The thing that makes trying any of them cheap:** the frozen contract. Anything that can
`POST :4001/start-task` is a valid front end — VoiceOS is not special, it is just the one
we wired first. The voice layer is swappable by design.

### Lightberry — talk to them first, highest value

"Brains for robots — listen, speak, act autonomously through natural voice commands."
That is architecturally *the same machine we built*. And it lands on our one remaining
blocker: **VoiceOS is paywalled on both A's and B's accounts.** If Lightberry gives us a
listen→act loop we can drive today, it replaces the exact layer we are stuck on.

Questions for their booth, in order: is there an SDK or HTTP endpoint we can hit today;
can it call a local MCP server (B's is built and tested); can it be triggered without
their hardware. **Investigate as a parallel path, not a swap** — rung 2 stays the plan of
record until something is proven on the demo Mac.

### Convex — yes, but strictly off the stage path

Wrong tool for the critical path: we have no database problem. The entire state of a run
is one `Map` in memory for 45 seconds, and adding a hosted backend to that is pure new
risk on the one path that must not fail.

**Where it genuinely fits — a live spectator view.** The crew's status streamed to a web
page the audience and judges open on their own phones while the demo runs. That is what
reactive sync is actually for, it is visibly impressive during judging, and **if it dies
mid-demo nothing on stage notices** — it reads `/status/:taskId`, it is not in the path.
Optionally: run history across rehearsals, which we currently keep in `/tmp`.

Staged, not started — waiting on the month of premium. Whoever picks it up: it is a new
directory, so it collides with nobody.

### a1mobile — one question, then decide

"AI native carrier that talks, texts, and handles tasks." The interesting beat is
triggering the crew by **text message from outside the room** instead of speaking to a
laptop — that is a better opening than a keypress, and it is one HTTP call to
`/start-task`. Entirely contingent on whether they expose a developer API today. Ask; do
not build speculatively.

## Decisions log

- _Sat night — orchestrator is one file (`orchestrator/server.js`), Node stdlib only, not the 4-file TypeScript layout in the folder plan — A — no build step, no `npm install`, no deps to break at 5pm; the whole thing is ~170 lines and restarts instantly. The frozen bit is the HTTP contract, and that's unchanged._
- _Sat night — execution path (speech vs MCP) is isolated in ONE file, `orchestrator/prompts/execution.md` — A — when B decides, we swap that file and the three role prompts don't change. Both options are already written in it, commented out. Right now it's dry-run: agents narrate but call no tools, so tonight's testing can't touch real mail._
- _Sat night — narration is paced by the orchestrator (~1.4s/line), not by token arrival — A — the model emits all its lines in one burst, so without pacing a character jumps straight to "Done:" and the dock looks dead. Found this on the first live run._
- _Sun morning — **the two speech streams are separated by device, not by timing** (`say -a`) — A — C's proposal, taken as proposed and measured: narration on the speakers reads 0.00 on BlackHole, commands on BlackHole read 0.80. Timing-based schemes need the two processes to know about each other; device-based needs nothing. Retires the `crew` multi-output device from the demo path._
- _Sun morning — **narration pacing raised 1400 → 2200ms** — A — the dock speaks these lines now and a line takes ~2s to say; at 1400 two of ten were dropped. Pacing had to meet the speech rate, and this way C's dock needs no change. Costs ~9s of runtime._
- _Sun morning — **agent personality is macOS voices + prompt wording, no TTS dependency** — A — three built-in accents (Moira/Daniel/Karen) plus a "Who you are" block per role. An external TTS would add an API key, a network call and latency on stage to buy something the platform already does. The one real upgrade is a GUI download of the Enhanced voices, which changes no code._
- _Sun morning — **MCP owns Gmail**, exposed through the server VoiceOS already has registered — B — it is the only option that keeps the voice loop intact for the inbox half. Apple Mail was rejected: it needs a mail account configured on the demo Mac, it cannot be seeded deterministically, and B cannot test any of it from Windows. Full reasoning below._
- _Sun morning — the same Gmail tools are wired two ways from one implementation — B — VoiceOS-called keeps the loop honest; agent-called is a drop-in fallback if VoiceOS transcription fails. Choosing between them at 5pm is a one-line change to `execution.md`, not a rebuild._

### B — the Gmail decision (A: you're unblocked, write the real `execution.md`)

**MCP owns Gmail.** Not Apple Mail, not narration-only.

Why not the other two:
- **Apple Mail** needs a real mail account configured in Mail.app on the demo Mac, and
  there is no deterministic way to seed it — no `messages.insert` equivalent, so we'd be
  sending real mail and waiting for it to arrive. B cannot test one line of it from
  Windows, and it would land on A's machine untested. Wrong risk on demo day.
- **Narration-only** was the safe pick, but it makes the inbox half a lie, and the seeded
  Gmail account already exists and works. We'd be throwing away something real for nothing.

**The part that matters — the same tools get wired two ways, from one implementation:**

1. **Voice loop (primary).** Agent speaks → VoiceOS hears → **VoiceOS calls
   `crew_gmail_*` on the MCP server it already has registered** → Gmail changes. Finding 4
   said Gmail has no native path through VoiceOS, and that's true — but *we are the
   integration*. `customMcpServers` is exactly the hole this fits. The loop stays voice all
   the way through and the inbox actually changes.
2. **Direct (fallback).** The agents call the identical tools themselves, no speech. This
   is `execution.md` Option B, and it's what we fall back to if VoiceOS transcription
   isn't reliable by rehearsal.

Same tool names, same code, same tested surface. **Switching between them at 5pm is a
one-line change to `execution.md`, not a rebuild** — which is the whole reason to decide
it this way rather than picking one and hoping.

**A — what you can write against right now**, tool names frozen:
`crew_gmail_list_inbox()`, `crew_gmail_archive(query|ids)`, `crew_gmail_label(ids, label)`,
`crew_calendar_find_slot(duration_min, after)`, `crew_calendar_book(summary, start, attendee)`.
Prefix is `crew_`, not `mcp__voiceos__` — Option B in `execution.md` currently names
`mcp__voiceos__gmail_*`, so that line needs updating when you swap the file.

**Update — all six are now BUILT and tested.** Two backends behind one interface, chosen
with `CREW_BACKEND`:

- **`fake` (default)** — in-memory, seeded from `fixtures.json`. No account, no credentials,
  no network. **This is a second panic button**: the inbox half of the demo does real
  archiving and real booking, with real numbers, on any machine. If OAuth isn't sorted by
  5pm, we lose nothing an audience can see.
- **`google`** — the real demo account. Raw REST over `fetch`, still zero dependencies,
  reusing the same `token.json` that `seed.py` writes, so authorising once covers both.

`crew_calendar_book` never sets `attendees`, so **Google cannot email a real person**
mid-demo. Archiving only drops the INBOX label; nothing is ever deleted.

**A — `test-demo-flow.js` asserts your script against the mailbox** and caught two things
that would have shown on stage:
1. the newsletter matcher also caught Calendly's "your *weekly* availability" — 7 archived
   while the character says six;
2. the fixture left **1pm** free, and David Chen's email says "anytime after 1pm", so the
   scheduler correctly booked 1pm while the character says *"Booking two PM"*. There is now
   a 13:00 vendor call so 2pm is genuinely the first free slot. **Reseed** to pick it up.

Also: booking a request doesn't archive it, so the inbox ended on 4, not 2. **The scheduler
must archive the meeting requests it has actioned** — that's what makes "down to two real
emails" true. Worth a line in the scheduler prompt.

**Still needed for `google`:** a demo Google account + OAuth `credentials.json`. Neither
exists yet, and that one blocker gates both `seed.py` and the `google` backend. `fake`
needs nothing.

## Blockers

- ~~**C → A: two speech streams will collide.**~~ **DECIDED, IMPLEMENTED AND MEASURED —
  C, you are unblocked and there is nothing for you to change.** Your proposal was right.
  Numbers, device names and the check are in "A — the audio split" above. `run-demo.sh`
  exports `CREW_AUDIO_DEVICE` for you; your resolver bug-fix landed on exactly this path
  and is what makes it safe to get the name wrong.

<details><summary>original blocker, kept for the record</summary>

- ~~**C → A: two speech streams will collide.**~~ **RESOLVED by A — decided as proposed,
  implemented, and measured (`BlackHole heard 0.000000` from the dock channel). Nothing
  left for me to change; `LINE_MS=2200` means all 10 lines speak without touching the
  backlog. C has re-verified the whole thing on a second Mac — see "C — verified A's
  audio split on a second Mac" below.** Original report kept for the record:
  `prompts/execution.md` Option A has each *agent* run `say -v Samantha "<command>"`
  to drive VoiceOS. The dock now *also* speaks narration on every `/agent-status`
  POST. Both land on the same speakers and the same mic, so an overlap feeds
  VoiceOS a command mixed with unrelated narration and the loop breaks on stage.
  The dock serializes its *own* narration (never two characters at once), but it
  cannot see the agents' `say` calls — separate processes.
  Proposed split, A's call since A owns audio:
  - agent → VoiceOS commands: `say -a "BlackHole 2ch"` (VoiceOS listens there)
  - dock → audience narration: `say -a "MacBook Air Speakers"`
  Then the audience never hears the robot command voice and VoiceOS never hears
  the narration. The dock already takes `CREW_AUDIO_DEVICE` for exactly this;
  `CREW_MUTE=1` silences dock narration entirely if we'd rather not risk it.
  **Safe to just try now** — as of this morning a device name the Mac doesn't have
  no longer silences the dock (bug 3 above); it warns, lists the real device names,
  and speaks on the default output. So setting this wrong costs you a wrong speaker,
  not a silent demo. Get the exact name from `say -a '?'` on your Mac and paste it —
  it must match what BlackHole actually registers as, not what we assume.

</details>

- **A — the one real blocker: VoiceOS Pro trial is not on A's account yet** (the free month
  from the event). Until it is, the loopback test can't run. BlackHole, the `crew`
  multi-output device, both scripts and the verification query are all ready and waiting —
  it's a 5-minute test, not a workstream. Everything else on A's side is done and tested.
- ~~**Open question for B:** which path carries the inbox.~~ **DECIDED — see the decisions
  log and "B — the Gmail decision" below. A is unblocked; write the real `execution.md`.**

- **B → A, and this one is rung 3 itself: nothing gives the agents the crew tools.**
  `execution-direct.md` tells each agent to call `crew_gmail_archive(…)`, but a headless
  `claude -p` only has an MCP server if it is passed one. `server.js` spawns with
  `['-p', prompt, '--output-format', …]` and **no `--mcp-config`**; there is no `.mcp.json`
  anywhere in the repo, and `claude mcp list` on my box is empty. So in `direct` mode the
  agents have **no `crew_*` tools at all**.
  **Why this is worse than a crash:** the prompt says *"If a call returns something
  surprising, narrate what is true and carry on — never announce a failure."* An agent
  with no tools does exactly that. It narrates the numbers from the prompt's own table —
  which are correct for the seeded mailbox — so **rung 3 looks identical to rung 2 while
  claiming the mailbox really changed, and nothing in the run says otherwise.** Same shape
  as the two things that already bit us: the orchestrator log reporting what it *sent*,
  and `SAY ->` proving only that the dock *asked* for audio.
  **What I've shipped so you can fix it in one line** (`orchestrator/**` is yours, so I
  haven't touched it): `voiceos-bridge/mcp-server/mcp-config.js` prints both values with
  absolute paths — `node mcp-config.js` for the config, `--tools` for the allowlist.
  ```js
  const crew = require('../voiceos-bridge/mcp-server/mcp-config.js');
  if (MODE === 'direct') args.push('--mcp-config', crew.json(), '--strict-mcp-config',
                                   '--allowedTools', crew.allowedTools());
  ```
  It prints a JSON *string* rather than shipping a `.mcp.json` on purpose: the server path
  inside the config resolves against the spawning process's cwd, and yours is
  `orchestrator/`, so a committed relative path would be correct from exactly one
  directory. `--allowedTools` is `mcp__crew__crew_gmail_archive`-style — the **third**
  naming scheme in this project, and the one your own `ALLOWED_TOOLS` comment already uses.
  `crew_gmail_archive` is the tool, `mcp__crew__…` is Claude Code, `custom_mcp_crew_…` is
  VoiceOS. `CREW_BACKEND` is inherited, so this is `fake` unless you set it.
  **`node voiceos-bridge/mcp-server/test-direct-contract.js` now guards the seam** — it
  reads *your* prompt file, asks *my* server for its real `tools/list`, and fails if the
  six names ever stop matching. It's in `checkpoint.sh`'s B block and passes.
  **What I could not verify, and you can in two minutes:** whether the agents then really
  call the tools. `claude` on my Windows box is installed but **not logged in**, and Node's
  `spawn` can't launch the `.cmd` shim anyway (`spawn claude ENOENT`), so I have no way to
  run a real agent here. On your Mac: `./run-demo.sh live`, then check whether
  `voiceos-bridge/mcp-server/.crew-mailbox.json` actually changed. If it doesn't change,
  the tools aren't reaching them and the flags above are the fix.
  **Also `checkpoint.sh` line 39 is a false green.** `have claude && ok "claude CLI present
  (real agents available)"` tests for the binary, not for a usable agent — mine passes that
  check and cannot run one. Same class as the stale-binary hole C found. Your file; a
  `claude -p` smoke call would make it honest, or just soften the wording.

- **B → A, 2-minute fix, do this before rehearsal: the two calendars are not the same
  calendar.** `demo-seed` writes the busy blocks into **Google** Calendar, but VoiceOS's
  `connectedIntegrations` is `["applecalendar"]` — so if the scheduler books natively
  through VoiceOS, it books into **Apple** Calendar and cannot see a single one of the
  seeded commitments. The 2pm slot is only "free" in a calendar VoiceOS isn't reading.
  Fix on A's Mac: **System Settings → Internet Accounts → add the demo Google account,
  tick Calendars.** Apple Calendar then shows the Google calendar and both halves agree.
  Verify by opening Calendar.app and seeing "Design review — onboarding" at 11:00 tomorrow.
  If we skip this, the demo still *runs* — the scheduler just books over a meeting that
  the audience can see on screen, which is a bad look on the one line the demo exists for.

## Demo script

**Written: [`docs/demo-script.md`](docs/demo-script.md).** Exact trigger phrase, the four
rungs and when to drop one, the pre-flight list, the ten-line beat sheet with what to say
over it, the break-glass table, and teardown. Read it once before rehearsal.

The short version: **one sentence — "Clean up my inbox and schedule everything" — then
nobody touches the machine for 45 seconds.** Rung 2 (`./run-demo.sh`, real agents,
nothing touched) is the plan of record until the Pro trial lands; `fake` is the panic
button and needs no network, no Claude and no account.

---

# CHECKPOINT — everybody stop here and test the same thing

We have been pushing all day against each other's stubs. This is the point where all
three of us run the *same* commit and confirm it does the same thing on three machines,
before anyone builds anything else.

**Run this, then paste your output into the chat:**

```bash
git pull --rebase origin main
./checkpoint.sh          # ~60s, or `./checkpoint.sh quick` to skip the dress rehearsal
```

It checks what your machine can actually check and skips the rest — B is not expected to
have BlackHole, C is not expected to have `uv`. It ends in one line: **CHECKPOINT PASS**
or the specific thing that failed. If it fails, that failure is your next task, ahead of
anything planned.

There is also **`/crew-next`** in this repo: it pulls, runs the checkpoint, works out
which of us you are, and gives you one task with the reason and the command. Use it
instead of re-reading this file.

### What A verified on the demo Mac at this checkpoint

| | state |
|---|---|
| orchestrator, all 3 modes | PASS |
| dock receives | 16/16 lines, correct order |
| dock speaks | **10/10 lines, 0 dropped** |
| characters | walking, bobbing per line, never freezing |
| B's MCP protocol | PASS |
| B's Gmail/Calendar tools | PASS — every spoken number true of the mailbox |
| B's demo-seed dry run | PASS — 18 emails, counts hold |
| audio split | PASS — 0.00 vs 0.80, measured |
| full chain, real agents | PASS — ~45s end to end |

### A → B, on the tool-renaming finding: good catch, and it lands somewhere else

You were right to flag it and right that a bare hardcoded name would have been a silent
5pm failure. Where it actually bites is narrower than it looks, because the two modes
call the tools from different sides:

- **`execution-direct.md`** — the agents hold their *own* MCP connection to the crew
  server. VoiceOS is not in that path at all, so the names stay bare `crew_gmail_*`.
  Renaming never applies. I've written that boundary into the file so nobody "fixes" it
  later by pasting a prefixed name in.
- **`execution-voice.md`** — VoiceOS is the caller, so your prefix rule governs. But the
  agent there speaks *English* (`say -a "BlackHole 2ch" "Archive all the newsletters"`)
  and never names a tool. There is no name in that prompt to get wrong.

So no prompt currently hardcodes a VoiceOS-side name, and none should. The one place the
prefix will matter is `ALLOWED_TOOLS` in `server.js` if we ever let the agents call the
crew tools *through* VoiceOS's own MCP connection rather than their own — that is the
combination your finding kills, and we are not using it.

**Your `readOnlyHint` question is the highest-value 5 minutes left in the project.** If
VoiceOS derives `requiresConfirmation` from MCP annotations, the loop is fully autonomous
with no voice-answered confirmation at all. Both of us are behind the same trial gate;
whoever gets Pro first should run that check and post the `tools/list` output.

### A — the crew can have more than three members now, and they carry an `activity`

**C: this is a spec for you, not a change to your files. Nothing here breaks the dock as
it stands** — I verified that first, by POSTing an unknown character to your current
build: HTTP 200, no crash, `(no character named 'researcher')` in the log. So this is safe
to land before you do anything.

**What changed on my side.** The three roles were hardcoded in three places. They are now
one table in `server.js`, and adding a crew member is one row plus a prompt file:

```js
const CREW = {
  triage:     { activity: 'sorting',  match: /inbox|email|mail/ },
  scheduler:  { activity: 'booking',  match: /schedul|calendar|meeting|book/ },
  researcher: { activity: 'research', match: /research|look up|find out|investigate/ },
  analyst:    { activity: 'analysis', match: /analy|compare|report|numbers/ },
  recap:      { activity: 'summary',  match: null },   // always last, always alone
};
```

**The new field, additive to the frozen contract — nothing is renamed or removed:**

```
POST :4002/agent-status
{ "character": "researcher", "message": "...", "state": "working",
  "activity": "sorting" | "booking" | "research" | "analysis" | "summary" }
```

`activity` is what the character is *doing*; `character` is who it is. Keying look and
motion off `activity` means two different agents doing research move alike, and you never
have to know their names — **a new crew member costs you nothing.** Ignore the field and
everything works exactly as it does today.

Suggested, entirely your call: research reads as *reading* (slower walk, head-down),
analysis as *comparing* (a pause-and-look beat), booking as brisk, summary as the unhurried
one you already have on `done`. Two clips is not a limit on this — tempo, mirroring, a hue
shift on the layer and scale give you distinct-looking agents from the same asset, which is
what the mirroring on recap already does.

**Two things on your side that this exposes, both small:**
1. `Narrator.defaultVoices` has three keys, and the `CREW_VOICE_*` override loop iterates
   those keys — so `CREW_VOICE_RESEARCHER` is silently ignored and new members all fall
   back to Samantha. Worth reading the env directly per character.
2. An unknown character is currently **spoken but not seen** — your narrator says the line
   with the fallback voice while nothing appears on screen. That is a defensible failure
   mode and better than silence; just know it is what happens until a name has a slot.

**The demo run is deliberately unchanged.** "Clean up my inbox and schedule everything"
still routes to exactly triage + scheduler + recap, and I re-ran it after all of this:
10/10 lines spoken, numbers correct. The new members only appear if someone asks for
research or analysis, so none of this is on the rehearsed path.

**One bug this surfaced and I fixed:** the closer had the old three-agent crew written
into its prompt, so with a research crew it cheerfully reported an inbox nobody had
touched. It is now handed the actual roster and each member's real `Done:` line
(`{{CREW}}` in `recap.md`), and reports only what ran.

### B — the loop stays alive now: `crew_task_status` answers out loud, with no taskId

**A: this is your "make the loop continuous" task, done.** Two things stopped it being a
loop, and neither was the contract — `/status/:taskId` is untouched.

**1. Nobody says "task underscore one" out loud.** `taskId` was required, so the only
question a human would actually ask — *"what's the crew doing?"* — had nothing to put in
it. It is **optional** now: the bridge remembers the task it started, and if VoiceOS
respawns the server between the two questions it reads the last started task back out of
`crew-bridge.log`. Asked with nothing running, it says so in a sentence rather than
erroring, because that is a normal conversational turn.

**2. VoiceOS reads a tool's reply back verbatim, and the old reply was a struct:**

```
Task task_1 is running.              ->  "task underscore one is running,
triage (working): Archiving six…          triage open paren working close paren colon…"
```

`mcp-server/status-speech.js` is that translation and nothing else — no I/O, so every
branch is testable with `node test-status-speech.js` on any machine. A whole run, from
your real orchestrator, asked with **no taskId**:

```
Triage and Scheduler are both waking up. Recap hasn't started yet.
Triage is archiving six newsletters and Scheduler is booking two PM with David Chen. Recap hasn't started yet.
Scheduler is booking two PM with David Chen. Triage is already finished and Recap hasn't started yet.
The crew is finished. Inbox cleared, two meetings booked.
```

**Three things testing changed my mind about:**

- **Your double-post is load-bearing here, and I had it wrong first.** You POST the final
  `Done:` line twice — once `working`, then `done`. Caught against your real orchestrator,
  not the stub: in that window the crew said *"Recap reports inbox cleared, two meetings
  booked"* — present tense about an agent that had gone home. The **text** wins over the
  state there, because `push()` stops queueing after the first `Done:`, so that prefix is
  terminal by construction. (C: this is the opposite of your advice, and both are right —
  you key animation off `state`, I key tense off the line.)
- **"Only `done` means finished"** is now enforced rather than assumed: the split is on
  whether an agent has *said* anything, not on the spelling of its state, so a state we
  have never seen is reported as still running and never as the end of the run.
- **Your closer is positional, not named.** `order` is `[...roles, CLOSER]`, so I read the
  last agent rather than matching `'recap'` — rename the closer or add members in front of
  it and this side needs no edit.

**Your new roster cost the bridge nothing, and I checked rather than assuming.**
`research the Q3 rollout and analyse the numbers` through the real orchestrator:
*"Researcher is reading what the thread actually says and Analyst is lining the numbers up
side by side. Recap hasn't started yet."* No name table, no edit. One wording bug your
analyst found for me: `One of these is not like the others.` is not a gerund, so
`"<Name> is …"` doesn't fit it — that path reads `Analyst reports: …` now.

**A — one bug in your `CANNED` table, and it is the one you just fixed one layer up.**
You fixed the closer's *prompt* so it reports the actual roster. `CANNED.recap` is still
hardcoded to `'Done: inbox cleared, two meetings booked.'`, so in **`FAKE` mode** a
research crew signs off by claiming it cleared an inbox nobody touched — reproduced above,
end to end. **Not a blocker and not on the rehearsed path** (the demo phrase routes to
triage + scheduler, where the line is true), but `fake` is the panic button, so if we ever
fall back to it on a non-inbox phrase the closer lies out loud. Your file and your call on
the wording — a canned line per roster, or a generic closer for anything that isn't the
demo phrase. Shout if you'd rather I did it.

**What's checkable, and where.** `verify.ps1` is 5 suites now; `stub-orchestrator.js` walks
a whole scripted run (one phase per `/status` call, waking up → finished) so the loop is
provable end to end on Windows with no Mac, no Claude and no account. `REQUIRE_DONE=1`
makes reaching *"the crew is finished"* a hard assertion against the stub — against a real
orchestrator it can't, because you pace at `LINE_MS`, and the test says so rather than
failing. I added one line to the B block of `checkpoint.sh` for the speech test (no
orchestrator needed, so it stays green when `:4001` is down).

**The `readOnlyHint` question — half of it is done, and it did not need the trial.** All 8
tools now declare MCP `annotations`, exactly as they behave, not as flatteringly as
possible: `crew_task_status`, `crew_gmail_list_inbox`, `crew_calendar_find_slot` and
`crew_calendar_list` are `readOnlyHint: true`; `crew_gmail_archive` and `crew_gmail_label`
are writes with `destructiveHint: false`, because archiving only drops the INBOX label and
nothing is ever deleted; `crew_calendar_book` adds an event and is explicitly **not**
idempotent. So if VoiceOS does derive `requiresConfirmation` from annotations, four tools
go through without a click and we claimed nothing false to get there. **Whether it reads
them is still the 5-minute check the moment either of us has Pro** — register, `tools/list`,
see whether the read-only ones stop asking. Table's in `mcp-server/README.md`.

---

# D — Yaseen: the crew only has two costumes

**Start:** `git clone` → `./run-demo.sh fake`. You will see three characters. Two of them
are the *same clip* — recap is triage mirrored, because upstream lil-agents ships exactly
two `.mov` files and we have five roles. That is your problem to solve.

**Why it matters:** A just made the crew a table that grows by one row —
`researcher` and `analyst` already exist and already talk. They have no face at all right
now: an unknown character is *spoken* by the fallback voice while nothing appears on
screen. The system outgrew its art.

**Your deliverable — new files only, so you cannot collide with anyone:**

1. **`crew-dock/Assets/`** — art for at least `researcher` and `analyst`, ideally a
   distinct one per role. Transparent-background HEVC `.mov`, portrait, looping walk
   cycle, matching the two that are there (1080×1920). Upstream is MIT — matching its
   style is fine, and so is commissioning/generating something better. **Do not commit
   anything you don't have the rights to.**
2. **`crew-dock/characters.json`** — the manifest, so adding a character never means
   editing Swift again:

```json
{
  "triage":     { "clip": "walk-bruce-01", "tint": null,   "scale": 1.0, "mirrored": false },
  "researcher": { "clip": "walk-reader-01","tint": "#7FB5FF","scale": 0.95,"mirrored": false },
  "analyst":    { "clip": "walk-jazz-01",  "tint": "#FFC46B","scale": 1.0, "mirrored": true }
}
```

3. **A per-activity motion note** (a paragraph in this file, not code): what should
   `research` look like versus `booking` versus `analysis`? A activity on every status
   POST already — `sorting`/`booking`/`research`/`analysis`/`summary` — so the dock can
   drive motion from it without knowing any character's name.

**Constraints that are not negotiable:** no Xcode (the demo Mac has Command Line Tools
only), no new dependencies, assets stay under ~20MB total, and `crew-dock/build.sh` must
still work from a clean clone. Art is fetched at build time today, not committed — talk to
C before changing that.

**Test it yourself, no one else needed:**
```bash
./crew-dock/build.sh && ./crew-dock/Crew.app/Contents/MacOS/Crew &
curl -X POST localhost:4002/agent-status -H 'content-type: application/json' \
  -d '{"character":"researcher","message":"Reading the thread.","state":"working","activity":"research"}'
```

**C (Abhishek) owns `crew-dock/Sources/**` and wires the manifest up.** Agree the JSON
shape with them before you fill it in — that five-minute conversation is cheaper than
either of you guessing. Ship the art first; it is the part nobody else can do.

---

# E — Rukaiya: everything runs on exactly one laptop

**Start:** `git clone` → `./run-demo.sh fake` → `./checkpoint.sh`. Paste your checkpoint
output into the chat — you are the fourth machine this has ever run on, and each new one
has found something.

**Why it matters:** the demo runs on A's Mac. If it dies, is left at home, or its
audio config drifts, we have no demo and no plan. Nobody owns that risk, and everyone
else is deep in their own component. It is the largest unowned risk in the project.

**Three deliverables, in this order:**

1. **A second machine that can run the whole show.** Clean clone → `./run-demo.sh fake`
   → `./checkpoint.sh` on a Mac that is not A's. Write down every step that was not in
   `docs/onboarding.md` — missing tool, permission prompt, anything. If it works
   first try, say so; that is a real result and we currently only assume it.
2. **Run the break-glass table in `docs/demo-script.md` and check it is true.** Every row
   is a claim nobody has actually tested: kill the dock mid-run, kill the orchestrator,
   pull the network, let an agent hang past 180s. Does what is written actually happen?
   Where it doesn't, fix the doc — it is the thing someone will read while panicking.
3. **`docs/runbook.md` — the one page for stage.** Pre-flight checklist, the trigger
   phrase, what to say over each beat, break-glass, teardown. `demo-script.md` is the
   detail; this is the version you can hold while standing up. **Plus a screen recording
   of a clean `./run-demo.sh fake` run** — if the room's wifi or Claude is having a bad
   evening, a recorded good run is still a demo.

**You own `docs/**`, so nothing you write conflicts with anyone's code.**

Two things you'll want early: `spike.sh off` after any audio work or the Mac has no
microphone, and `/tmp/crew-dock.log` is what the audience actually got — the orchestrator
log only proves what was *sent*.

---

### Then: one task each, in priority order

**A (me) — next:** finish the voice loop the moment the Pro trial lands
(`spike.sh demo` → `spike.sh test` → check the `dictations` table). That is the last
untested link in the system and it is a 5-minute test, not a workstream. Rung 4
(`./run-demo.sh voice`) is written and waiting for it.

**B — your `verify.ps1` is the Windows half of `checkpoint.sh`.** Run `./checkpoint.sh`
too (it skips what your box can't do) so we have one shared PASS line, and if the two ever
disagree, `checkpoint.sh` is the one that runs on the demo machine.

**B — next: `crew_task_status` needs to make the loop *continuous*.** Right now the
human says one sentence, the crew runs, and it ends. What the demo is really about is
the loop staying alive: VoiceOS should be able to ask "what's the crew doing?" and get a
spoken answer mid-run, and know when it is finished. You have `crew_task_status` built
against the frozen `/status/:taskId` contract — make its reply a *sentence a person would
say out loud*, not a JSON dump ("Triage is archiving, scheduler is booking two o'clock"),
because VoiceOS speaks it verbatim. Everything you need is testable with
`FAKE=1 node orchestrator/server.js` on your own machine, no Mac required.
Second: the `readOnlyHint` / `requiresConfirmation` check from your finding 3 — five
minutes the moment either of us has Pro, and it decides whether the loop is autonomous
without the voice-answered-confirmation fallback.

**C — next: the agents can get stuck, and the dock is where that shows.** Two cases
neither of us has covered: an agent that hangs (the orchestrator kills it at 180s and the
character says "ran out of time") and an agent whose state stays `working` while nothing
new arrives for 30+ seconds. Both currently look identical to a healthy character. A
visible "still thinking" behaviour — the walk slowing, or the bubble showing an ellipsis
after ~10s of silence — turns a hang into something the audience reads as thinking rather
than as a crash. **You own `AgentCharacter.swift`**; I edited it at this checkpoint to
stop the characters freezing on `done` (they now express state as tempo, bob on each
line, and the recap is mirrored since it reuses triage's clip) — review that and take it
back, it is your file and your call.
Test it with `curl` alone: POST `working` and then simply stop posting.
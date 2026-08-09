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

**Four Macs and one Windows box.** That ratio is the reason `run-demo.sh` was never the
whole story: it builds and launches the Swift dock, so it is macOS-only and always will
be, and B could not run the thing B was building against.

- **A — Vraj** — Claude Max, **Mac** — **confirmed demo machine**
- **B — Sameer** — **Windows** — the only non-Mac. Runs `run-demo.ps1`
- **C — Abhishek** — Mac
- **D — Yaseen** — Mac — character art + visual identity
- **E — Rukaiya** — Mac — rehearsal, resilience, backup rig

Subscriptions: A Claude Max; B OpenAI Plus + Claude Pro; C Claude Pro.
D and E — put yours in your row so we know what you can run.

**`run-demo.ps1` is the Windows half of `run-demo.sh`** — same pipeline, same ports, same
entry point, with fake-dock printing what it received in place of characters and speech.
Verified on B's box: **16 lines reached the dock, which is A's exact Mac number.** Four of
you will never need it; the fifth could not rehearse without it.

```powershell
.\run-demo.ps1           # canned agents, whole pipeline, zero Claude spend
.\run-demo.ps1 -Talk     # the demo as a conversation -- this is the pitch
.\run-demo.ps1 -Voice    # orchestrator up, then you SPEAK into VoiceOS
.\run-demo.ps1 -Stop
```

**Windows gotcha, and it cost me a parse error before I spotted the pattern: every `.ps1`
in this repo is strictly ASCII, and that is load-bearing.** Windows PowerShell 5.1 reads a
BOM-less script as cp1252, and an em dash (`—`, `E2 80 94`) ends in byte `0x94` — which
cp1252 maps to a **right double quotation mark, and PowerShell treats that as a string
delimiter.** So one em dash in a comment silently opens a string and the whole file stops
parsing. `verify.ps1`, `register.ps1` and `test.ps1` are all ASCII-only for this reason;
keep it that way. Use `--`.

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
| **D — Yaseen** | character art + visual identity | **fifth machine, FULL CHECKPOINT PASS on `b51e3dc` — 15 ok / 0 failed / 5 N/A, dress rehearsal included (16 received, 10 spoken, 0 dropped).** Art itself not started yet. Clean setup needed `node`; getting there found **a hang in `checkpoint.sh` on any machine without node — see Blockers, it's A's file.** C's stale-binary check also caught me for real after a pull — worked exactly as intended. **Gitignore blocker RESOLVED by A in `4e8d202` and verified here — original art is committable, 4MB/clip, and `recap` is the agreed priority. Nothing of mine is open.** Next and only: the `recap` clip | nothing. Your work is new files only; you cannot be blocked by us |
| **E — Rukaiya** | rehearsal, resilience, backup rig | **backup rig PROVEN — clean clone → full show → CHECKPOINT PASS (17 ok / 0 failed) on a second MacBook Air.** Clone to spoken demo in 72s, 16 lines received, 10 spoken, 0 dropped. C's speaker fallback fired for real here (no `MacBook Pro Speakers` on an Air) and saved the run — see my section at the bottom. Onboarding fixed where my run disproved it. **Break-glass table now TESTED, row by row — one row was half-true: a hung agent can wedge the whole run after saying "ran out of time" (A: repro + fix in my section and Blockers).** **All three deliverables done: `docs/runbook.md` written (one page, folds in the voice-only rule + Dictation hedge + tested break-glass), and a clean 10/10 run recorded with audio — 75s, 11MB, on my Desktop, posting to the chat.** **Rung 2 now also proven here — first real-agent run on a Mac that isn't A's: 10/10 spoken, beat-sheet numbers exact (18 in, 14 archived, 2 booked, 2 left). The backup rig covers rungs 1 and 2.** | nothing |
| A | orchestrator + dock + audio rig | **CHECKPOINT READY — everyone run `./checkpoint.sh`, see the Checkpoint section at the bottom.** Orchestrator done, 3 modes (`narrate`/`live`/`voice`) selected by a flag not a file edit. Audio split decided + measured. 10/10 lines spoken, 0 dropped. Three accents + written personalities. Characters no longer freeze. `docs/demo-script.md` written. Full chain with real agents: ~45s, PASS | VoiceOS Pro trial not active — still the only thing left on A's side |
| B | voiceos-bridge (mcp-server + demo-seed + Gmail/Calendar tools) | **VoiceOS Pro is LIVE on Windows and Gmail is connected — but `customMcpServers` is empty, so VoiceOS still cannot reach the crew. That GUI step is the last thing between us and the voice loop; see my section below.** `run-demo.ps1` now runs the whole pipeline on Windows (16 lines to the dock, A's exact number), so the one non-Mac can finally rehearse. `verify.ps1` 6 suites all green. Checkpoint 13 ok / 1 failed — and the 1 is A's new check working correctly: `claude` on this box is logged out, which the old `have claude` test called a PASS. All 8 tools built and tested. **`crew_task_status` closes the loop: no taskId needed, and it answers in a spoken sentence instead of a JSON dump** — see below. Tool `annotations` declared on all 8 tools, honestly. Gmail decision made; A unblocked. VoiceOS installed on Windows and inspected — see the tool-naming finding. **A — both of my findings are fixed by you and confirmed: rung 3 really calls the tools, and the claude check now catches a logged-out box (mine). `CANNED.recap` still lies for a research crew, off the rehearsed path.** **README brought up to date with the proven voice loop, and `VOICEOS-FEEDBACK.md` corrected where today disproved it — the `dictations` finding is now its headline item.** | **Pro is live. Two left, neither blocking a rung we'd show: `customMcpServers` still 0 on my box (GUI step), and no Google OAuth for the `google` backend — `fake` needs neither.** |
| C | crew-dock (took option 2) | **the dock talks, and the handover is proven.** `Narrator.swift` speaks every `/agent-status` line via `say`, per-character voices, never two at once. Re-verified this morning from a **throwaway clone of current `main`** — clone → speaking app in 13s. **A's audio split + new voices then re-verified on my Air against A's unmodified `run-demo.sh`: 16 received, 10 spoken, 0 failed.** Nothing left to hand-carry to A's Mac but two commands. **Stall indication shipped: a `working` agent gone quiet for 10s now slows and trails an ellipsis instead of looking identical to a healthy one. Roster moved to `crew-dock/characters.json` — D, the shape is agreed and working, adding a character is a row plus a .mov.** **Reviewed and kept A's character fix — verified by screen capture, not by log — and fixed the stale-binary hole that let `checkpoint.sh` PASS while grading an old build** | **nothing — CHECKPOINT PASS (17 ok / 0 failed)** |

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
  "SELECT created_at, transcription FROM voice_sessions ORDER BY rowid DESC LIMIT 3;"
voiceos-bridge/audio-loopback/spike.sh off             # ALWAYS — else you have no mic
```

⚠️ **`voice_sessions`, NOT `dictations`** — corrected by B after A proved the loop. This
block said `dictations` all day, and that table is empty and legacy in VoiceOS 0.1.21: it
returns 0 rows for a run that worked perfectly, which is exactly how we spent a day
believing the loopback was broken. Anyone following these steps from the top would have
repeated it, so the query is fixed here rather than only noted 500 lines below. Use an
inert phrase first — prove transcription before proving actions, so a failed booking
doesn't get blamed on the audio path.

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

### C — macOS setup script for VoiceOS, and three corrections to our own notes

**There was no macOS setup code.** `register.ps1` is Windows-only, so every Mac — the
demo Mac included — had "register the MCP server" as folklore in a commit message.
**`voiceos-bridge/mcp-server/register.sh` is the macOS half now.** Same contract as B's:
it audits and prints, it **never writes** VoiceOS's config, and it never prints the file
(that thing holds `accessToken`, `idToken`, `auth`, `supabase`).

```
./voiceos-bridge/mcp-server/register.sh
```

It reports the install, audits the settings that decide whether the voice loop can work,
runs `server.js --selftest`, and prints the exact name/command/args to paste. Run on my
Mac just now, against a real VoiceOS install with Pro live.

**Correction 1 — the config keys are NESTED, and our notes say they are top-level.**
They live under `settings.*` and `onboarding.*`:

```
onboarding.onboardingCompleted     settings.muteWhenDictating
settings.agentVoiceEnabled         settings.keyboardShortcuts
```

**B — this is a real bug in `register.ps1`, not a cosmetic one.** It reads these at the
top level, so on this schema it reports *absent* for settings that are in fact set to
`true` — and `muteWhenDictating` / `agentVoiceEnabled` being silently reported as
"not set" is exactly how the voice loop fails for a reason nobody can find. It's your
file so I haven't touched it; `register.sh` shows the nesting if you want the shape.

**Correction 2 — `connectedIntegrations = ["gmail"]` on my Mac.** A's note says
`["applecalendar"]`, and B chose "MCP owns Gmail" partly because VoiceOS had no Google
path. That finding is **per-account, not per-app** — this account has Gmail connected.
**It does not change the decision** (our own tools are still more predictable than
VoiceOS's, and the seeded mailbox is what the demo asserts numbers about), but nobody
should be surprised on stage to see VoiceOS offer a Gmail action of its own.

**Correction 3 — `codingAgentDangerouslyBypassPermissions` exists and is `false`.**
B, this is adjacent to your `readOnlyHint` / `requiresConfirmation` question and it is
in the config today, so the answer may be a settings flag rather than an MCP annotation.

**Two settings still need flipping before anyone runs the voice loop** — both `true` on
my Mac right now, and both are A's findings 2 and 3 from last night:

| setting | now | needs to be | why |
|---|---|---|---|
| `settings.muteWhenDictating` | `true` | **false** | VoiceOS ducks system audio while listening — it would mute the `say` output the loop feeds it |
| `settings.agentVoiceEnabled` | `true` | **false** | VoiceOS talks back; in a loopback rig it hears itself and re-triggers |

`register.sh` flags both as `fix` until they're off, so nobody has to remember them.

**Still unproven, and it is the last thing:** whether VoiceOS actually *transcribes* the
loopback audio. The rig is configured and the bridge passes its self-test, but no spoken
phrase has yet reached the orchestrator on any machine.

### C — A's hang fix and my stall indicator, run together for the first time (A + E)

A fixed the wedge at the orchestrator; I made a stalled character legible at the dock.
Both were tested alone and **never against each other**, so I ran E's scenario through
the whole chain: a shim `claude` that prints one line, backgrounds an orphan holding
stdout, then hangs. Real orchestrator, real agent path, `AGENT_TIMEOUT_MS=15000` so the
10s stall threshold fires first.

They compose exactly as intended:

```
DOCK <- triage [working] {sorting} Scanning the inbox.
THINK -> scheduler — no line for 10s     <- both characters slow, ellipsis appears
THINK -> triage — no line for 10s
DOCK <- triage [working] Done: ran out of time.
THINK <- triage resumed                  <- ellipsis clears the instant a line lands
DOCK <- triage [done]    Done: ran out of time.
… recap hangs too, same pattern, run reaches done
```

**Zero orphans left behind** — A's group-kill holds against a process that deliberately
outlives its parent. And the audience-facing behaviour through a hang is now: character
slows and thinks → says "ran out of time" → settles at `done`. No frozen sprite, no
statue, nothing that reads as a crashed app.

**One thing this surfaced that is worth a break-glass row, E.** The recap's timeout is
**serial** after the agents' — `await Promise.all(roles)` then `await runRole(CLOSER)`
(`server.js:244-245`). So a fully hung crew is not one timeout, it is **two**: at the
real `TIMEOUT_MS` of 180s that is **~6 minutes** of stage time before the run reports
done. My 15s run took 39s, which is the same shape scaled down.

Nobody should ever sit through that, and now nobody has to guess:

> **If a character is slowed with an ellipsis for more than ~15 seconds, it is not
> thinking — it is hung. Hit `./run-demo.sh fake`.** Before the ellipsis existed there
> was no visible difference between a working agent and a dead one, so the panic button
> had no cue. This is that cue.

A — nothing for you here, your fix is good and I changed nothing on your side. E — that
quoted line is the row I would add to the break-glass table; it is yours to word.

### C — a stuck agent now reads as thinking, and the roster is data (D: read this)

Both of the things A left me at the checkpoint. Checkpoint after: **17 ok, 0 failed.**

**1. Stall indication — the assigned one.** A `working` character whose lines stopped
arriving looked *identical* to a healthy one: same brisk walk, same caption sitting
there. So a hang and a pause were indistinguishable, and an audience resolves that
ambiguity as "it crashed". After **10s of silence** the character slows to 0.40 and
trails an animated ellipsis on the line it already has. It invents no new text — the
dock genuinely knows nothing new, and making it say "still working…" would be the dock
asserting something it can't see. A new line clears it instantly.

10s is deliberately between the two numbers that matter: well past the ~2.2s line beat
(so a healthy run never triggers it) and well short of A's 180s kill (so a real hang is
visible for ~170s before the orchestrator gives up). Logged `THINK ->` / `THINK <-`, so
it's checkable without watching the screen.

Tested by curl and by pixel, per A's instruction to POST `working` and then stop:

```
t+6s  : 0 think events        <- healthy, no false positive
t+10s : THINK -> triage — no line for 10s
        bubble: "Reading the flagged emails. .."     <- ellipsis animating
        legs:   af0d42… / 71ce29… / 41fe34…          <- still walking, just slower
        new line -> THINK <- triage resumed, ellipsis gone
healthy full run: 0 THINK events, and still 0 after 15s of everyone sitting `done`
```

**2. `crew-dock/characters.json` — D, this is the shape, and it already works.**
A said we should agree it rather than both guessing, so rather than write a spec I built
the loader and shipped a manifest that describes *exactly today's reality* — three roles,
two clips, recap mirrored. Behaviour is unchanged; the file just moved the roster out of
Swift.

```json
"characters": [                                  // order = left-to-right on screen
  { "role": "triage", "asset": "walk-bruce-01", "mirrored": false }
],
"activities": { "research": { "rate": 0.90 } }   // rate while `working`
```

- `role` must match the `character` the orchestrator POSTs. `asset` is `Assets/<asset>.mov`,
  no extension. `mirrored` flips it — only needed while two roles share one clip.
- **`activities` is keyed on A's new `activity` field, not on the role** — so two agents
  doing research move alike and this file never has to learn the roster. That was A's
  design intent and it's now wired: the POST's `activity` picks the rate.
- **Adding researcher/analyst is a row each plus a `.mov`. No Swift, no rebuild of
  anything but the app.** Your art gap and my loader meet exactly here.
- Change the shape if it doesn't suit the art — you own the file, I'll move the loader.

**Every failure mode falls back to the built-in three, so a bad edit cannot break the
rehearsed run:** missing file (silent, it's the normal case), unreadable JSON, or no
usable rows. All three tested. The unreadable case now names the offending path —
it fell back *silently* at first, which would have had you editing the file, seeing no
change, and concluding the loader ignores you.

**Two smaller things while I was in there:**
- `activity` was being **dropped on the floor** by my listener — it's parsed and logged
  now (`DOCK <- triage [working] {sorting} …`). A, that field was arriving nowhere.
- An unknown character now logs `spoken but NOT shown`. A verified this returns 200 and
  doesn't crash — correct — but the narrator still *speaks* the line, so today a
  researcher line is heard with nothing on screen. That is the one failure the audience
  notices and the log didn't mention. It's D's gap; the dock now says so out loud.

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
we wired first.

**Ranked after actually reading their docs rather than their taglines:**

| | verdict | needs |
|---|---|---|
| **a1mobile** | the only one that could improve the demo — one booth question decides it | them to expose a webhook |
| **Lightberry** | opportunistic only — it is robot hardware, not a laptop voice layer | a robot on the floor and their say-so |
| **Convex** | **no** — we have no problem it solves. Reasoning below | a real reason, which we do not have |

**None of these is on the critical path, and if none of them happens we lose nothing.**
The demo works today. A sponsor integration is only worth doing if it makes the demo
better — not because the sponsor is in the room. The voice layer is swappable by design.

### Lightberry — I had this ranked first. That was wrong; it is hardware-bound

**Correction, so nobody spends a day on this.** I originally called Lightberry the
highest-value sponsor because "listen, speak, act via natural voice" reads like the exact
layer VoiceOS occupies. I ranked it off a one-line description. Having actually looked:

- It is a **social brain for physical humanoid robots** — the listed platforms are Unitree
  G1, Fourier GR-2/N1, Booster T1/K1, High Torque Mini-Pi. **We own none of these.**
- **No public SDK, API, docs, GitHub or PyPI package** under any obvious name. Their site
  and YC page both route developers to `founders@lightberry.com`. There is no "install it
  and drive it from a laptop" path we can find.
- It does not solve the VoiceOS paywall, because it is not a laptop voice layer.

**The one real integration, and it is opportunistic rather than plannable:** if they bring
a robot to the venue and let us drive it. Then the good version is obvious and very
strong — **the robot becomes a crew member.** It speaks the recap out loud in the room
while the other characters run on screen, or you talk to *it* instead of a laptop and it
POSTs `/start-task`. Physical + on-screen agents in one demo is a better picture than
either alone.

That depends entirely on hardware access on the day. **Ask if there's a robot on the floor
and whether it can hit an HTTP endpoint. Do not plan around a yes.**

### Convex — not unless it earns a place. Right now it doesn't

I pitched a spectator view: crew status streamed to a page the audience opens on their
phones. **Talked out of it, correctly.** Look at what that actually is — asking a room to
look down at their phones during a 45-second demo whose entire point is characters
walking around a screen and talking out loud. It competes with the thing we built. That
is a sponsor integration wearing a feature's clothes.

**We have no problem Convex solves.** One run is a `Map` in memory for 45 seconds on one
machine, with one user, and no state that outlives the demo. No database problem, no sync
problem, no multi-user problem. Adding a hosted backend buys a dependency and a network
call and returns nothing an audience can see.

**Do not build it for the prize.** It would be the only thing in this repo that exists for
a reason other than the demo working, and this whole build has gone well because that has
never been true.

**What would change my mind** — a real problem it is the right answer to:
- the dock becomes a web app rather than Swift (it isn't, and shouldn't become one today)
- we need run history across rehearsals for something other than curiosity
- a second device genuinely has to see live state — a phone as the trigger *and* display
- a judge asks for it, which is a business reason and Vraj's call, not a technical one

Until one of those is true this stays unbuilt. If someone wants the sponsor prize anyway,
say so out loud as a *business* decision and time-box it — but it goes in its own
directory, off the demo path, and nobody touches `run-demo.sh` for it.

### a1mobile — what changes if you *phone* the crew (A investigated)

**Findings first: there is no public developer API.** Neither `a1mobile.com` nor the
business dashboard documents an API, webhook, custom action, or MCP surface. The product
is an AI receptionist you buy, not a platform you build on — as far as anything public
shows. **So this is a booth question, and it is a single one:**

> *"Can your AI call an HTTP endpoint we host, and read our reply back to the caller?"*

Yes → we can do this in an afternoon. No → it is not possible at all, and no amount of
our work changes that. Do not build anything before that answer.

**What the architecture would actually become:**

```
today  human speaks -> VoiceOS -> MCP run_crew_task -> POST :4001/start-task -> agents -> dock
phone  human CALLS  -> a1 AI   -> webhook           -> POST :4001/start-task -> agents -> dock
                     ^                                                                     |
                     +----- crew_task_status sentence read back down the call <-------------+
```

**Almost nothing changes, and that is the point of the frozen contract.** The trigger side
needs *no new code*: `/start-task` already takes `{instructions}` as plain text, so a
webhook body is the same thing VoiceOS sends. The read-back already exists too — B's
`crew_task_status` returns a spoken sentence, which is exactly what you want a phone to
say while a 45-second run is happening.

**Two things genuinely do change, and one of them is a real problem:**

1. **The orchestrator would have to be reachable from the internet.** A carrier's cloud
   cannot reach `localhost:4001`, so it needs a tunnel — and that puts **the public
   internet on the stage path**, which is the one thing every other decision here has
   avoided. It also exposes an endpoint that spawns Claude sessions, unauthenticated,
   on the demo machine. If we do this it needs a shared secret and it must be a *rung
   above* the local path, never a replacement.
2. **A 45-second silence on a phone call is a long time.** The status sentence has to be
   read back periodically, not once at the end.

**Verdict: additive trigger, never the critical path.** If a1mobile can hit a webhook, it
is the best opening beat we could have — texting the crew from outside the room beats a
keypress. If they can't, we lose nothing, because the local path was always the plan.

**What this investigation was worth on its own — a real bug on the demo phrase.** Testing
routing against *transcript*-shaped input rather than typed input:

```
"Clean up my in box and schedule everything."   -> scheduler + recap     <- TRIAGE MISSING
```

A speech-to-text pass writes "in box" as two words and half the demo silently vanished —
no error, just one character that never wakes. That is reachable from VoiceOS today, not
only from a phone. `rolesFor` now matches how a transcriber spells things rather than how
a person types them (`in box`, `in-box`, `e-mail`, `e mail` all covered). Nine transcript
variants now route correctly; `hi` still falls back to the full crew.

### a1mobile — one question, then decide

"AI native carrier that talks, texts, and handles tasks." The interesting beat is
triggering the crew by **text message from outside the room** instead of speaking to a
laptop — that is a better opening than a keypress, and it is one HTTP call to
`/start-task`. Entirely contingent on whether they expose a developer API today. Ask; do
not build speculatively.

## A — VoiceOS Pro is live. What is done, and the one thing still to prove

**Settings applied and verified** (`voiceos-setup.sh apply`, backs up first):
`muteWhenDictating` was **true** — it would have muted the very audio we feed it.
`agentVoiceEnabled` was **true** — its replies would have looped back into the mic.
Both off now, mic on `BlackHole 2ch`, onboarding complete. The `dictations` table is
**empty**, so any row that appears is unambiguously from the loopback.

**Audio rig re-verified after the settings change:** `verify` 0.804261, `split` PASS
(0.000000 to the room / 0.804261 to VoiceOS).

**STILL UNPROVEN: does VoiceOS transcribe it.** First run of `spike.sh test` produced
**0 dictations** — the hands-free trigger (`fn`+`space`) was never pressed, which is the
one step no script can do. The rig is correct and the test is a 60-second retry.

### B — your `readOnlyHint` question, answered as far as static analysis can take it

**VoiceOS does read MCP annotations.** Its bundle contains a `readOnlyHint == false`
branch and validates the field with zod (`readOnlyHint: z.boolean().optional()`),
alongside the `requiresConfirmation` plumbing you found. So the two sides are already
wired to each other, and **your tools already declare honestly** — `crew_gmail_list_inbox`
and `crew_task_status` are `readOnlyHint: true`, the writes are `false`.

That means the confirmation behaviour should follow the annotations we already ship,
with no change on your side. It still needs the live confirm (register, `tools/list`,
watch whether a read-only tool skips the prompt) — but it is no longer a guess about
whether the mechanism exists.

**Also in the bundle: `codingAgentDangerouslyBypassPermissions`.** A boolean in the same
settings object as `nativeActionToggles`. That may be the global bypass we both concluded
did not exist. Worth five minutes once the loop runs — but note the name is a warning, and
it is not something to flip on a machine holding real mail without understanding it.

## ✅ A — THE VOICE LOOP IS PROVEN. Last untested link in the system, tested.

VoiceOS transcribed audio it never heard through a microphone:

```
created_at                app_name   window_title          transcript
2026-08-09T18:58:19.992Z  TextEdit   crew-dictation.txt    "Log"    (2.4s)
```

`crew-dictation.txt` is the scratch file `spike.sh test` opens, and BlackHole has no
microphone — so that audio can only have arrived through the digital loopback. **`say` ->
BlackHole -> VoiceOS -> transcribed text in a real app works.** Every hop in the system is
now individually proven.

### The reason we thought it had failed: we were reading the wrong table

`spike.sh` and every note in this file verified against **`dictations`**, which in VoiceOS
0.1.21 is **empty and legacy** — it has 0 rows and always will. Transcripts land in
**`voice_sessions`** (14 rows, with `transcript`, `app_name`, `window_title`,
`duration_seconds`). Our first run reported "0 dictations, the trigger was never pressed"
when it had in fact worked. Fixed in `spike.sh`; the query to use is:

```bash
sqlite3 -readonly ~/Library/Application\ Support/VoiceOS/voiceos.db \
  "SELECT created_at, app_name, transcript FROM voice_sessions ORDER BY rowid DESC LIMIT 3;"
```

**This is the fourth time on this project that a check reported failure or success while
looking at the wrong thing.** It is worth assuming the instrument is wrong before the code.

### Two things that are NOT solved, stated plainly

1. **The trigger still needs a human press.** `fn` cannot be synthesized, so I rebound
   hands-free to `control-left+option-left+h` and posted it with AppleScript. The chord
   posts successfully — and VoiceOS never starts a session from it. It almost certainly
   watches keys with a low-level event tap that `System Events` keystrokes do not feed.
   **Rebinding is not the way out.** `voiceos-setup.sh handsfree <chord>` and
   `spike.sh trigger` are committed for anyone who wants another go, and hands-free is
   **restored to `fn+space`** because that is the combination the demo has actually
   rehearsed. One human press at the top of the demo, exactly as originally designed.
2. **Transcription quality on the loopback is poor.** The one captured session heard "Log"
   out of a full sentence, over 2.4 seconds. Could be trigger timing (the window opened
   late), rate, or level. It needs a couple of clean runs to characterise before we rely
   on the spoken path on stage. **Rungs 1-3 do not depend on it.**

## A — the crew sounds like people now, using open source and no subscription

**`crew-dock/crew-say`** — a drop-in replacement for `say`, identical flags, backed by
**Piper** (MIT, on-device neural TTS). No account, no subscription, no network at run
time, no per-word cost. The macOS voices we had are the 2005-era *compact* builds, which
is exactly why the crew sounded like a screen reader.

```bash
./crew-dock/voices.sh piper-install      # ~63MB per voice, one time
./run-demo.sh fake                        # picks it up automatically
```

Cast: **triage = alba (Scottish, dry)**, **scheduler = northern english male (brisk)**,
**recap = amy (warm)**. Three accents, three actual humans rather than one synth with
three pitches.

**It cannot make the dock silent.** `crew-say` falls back to `/usr/bin/say` on its own if
Piper, `uvx`, `sox` or a model file is missing — and the models are gitignored, so a fresh
clone gets the old voices and a working demo rather than an error. The only thing this
change can affect is how the dock *sounds*.

**Cost, measured:** a Piper line is ~1.1s to synthesise on top of speaking it — 5.1s
total against `say`'s ~3.8s. Same rule as before applies (pacing must be >= how long a
line really takes), so `run-demo.sh` raises `LINE_MS` to 5500 when the models are present.
Full run re-verified: **10 lines, 0 dropped**. The show runs ~15s longer and sounds
completely different.

**C —** one line in your file: `speak()` takes its binary from `CREW_SAY` now, defaulting
to `/usr/bin/say`. Nothing else changed, and unset behaves exactly as today.

**D —** if you want the characters to *look* as different as they now sound, alba /
northern male / amy is the casting the art should match.

## A — answers for D, and the MCP call

### D — your gitignore blocker is FIXED, and there is a simpler fix than the one you found

You were right about the cause and right that `!` cannot work — git never descends into an
excluded directory, so the negation is never consulted. But `/*` plus negations is not the
smallest fix. **Ignore the two upstream files by name instead:**

```
crew-dock/Assets/walk-bruce-01.mov
crew-dock/Assets/walk-jazz-01.mov
```

No directory is excluded, so there is no descent problem to work around, and **anything
you draw is committable with no further edits to `.gitignore` ever again.** Pushed and
verified both directions: upstream still ignored, a new `walk-reader-01.mov` shows up in
`git status`.

### D — your size number: **4MB per clip, 20MB total committed art**

Upstream's ~18MB does **not** count against it — `build.sh` fetches those, they are never
committed, and they are not ours to ship. The 20MB is yours alone.

The constraint behind the number is clone time, not disk: E measured **clone → running
demo in 72s** on a fresh machine, and that number is the backup rig's whole value. 20MB
adds a few seconds to it. If a clip needs to be bigger to look right, say so and we will
trade — the number exists to be argued with, not obeyed.

Match upstream's format so nothing else has to change: **HEVC with alpha, portrait
1080×1920, looping walk cycle.** `AgentCharacter` scales to 170pt tall, so detail beyond
that is wasted bytes.

### D — art priority, since you asked. Recap first, and you are right that it matters

1. **`recap` — first, and alone if you only do one.** It is on stage in the rehearsed run,
   it speaks the closing line, and it is currently `triage` flipped horizontally. Two of
   the three characters the audience sees are the same drawing.
2. **`triage` / `scheduler`** — a second pass only if recap lands early. They are at least
   already different from each other.
3. **`researcher` / `analyst` — last.** They are real and they talk, but they are **not in
   the rehearsed run**; they only appear if someone asks for research or analysis. Nice to
   have, not on the demo path.

They now have voices you can cast against: **triage = alba (Scottish, dry), scheduler =
northern english male (brisk), recap = amy (warm)**.

### Should we register an MCP named `crew`? — Yes. Name it exactly `crew`

It is the last thing between us and the voice loop, and **the name is load-bearing**:
VoiceOS renames every custom tool to `custom_mcp_<servername>_<tool>`, so `crew` is what
makes them `custom_mcp_crew_crew_gmail_archive` rather than something we have to rediscover
on stage. C's `register.sh` prints the exact values and audits the config first.

**One correction to what it prints:** use the **absolute** node path, not bare `node` —
VoiceOS is a GUI app and does not inherit a shell PATH, so Homebrew's node is not on it.
`node voiceos-bridge/mcp-server/mcp-config.js` prints the right one. On this Mac:

```
name    : crew
command : /opt/homebrew/Cellar/node/25.6.1/bin/node
args    : /Users/vrajpatel/Developer/crew/voiceos-bridge/mcp-server/server.js
```

Registering is GUI-only — there is no CLI — and **do not hand-edit `config.json` while
VoiceOS is running**; it is an electron-store and rewrites the whole file on its own
schedule. `tools/list` showing `crew` is the check that it took.

## A — STATUS RIGHT NOW: what is connected, and the one thing that is not

Checked, not assumed, at this moment on the demo Mac:

| | state |
|---|---|
| VoiceOS Pro | **live** |
| mic -> BlackHole 2ch | **set** |
| `muteWhenDictating` / `agentVoiceEnabled` | **off** (both were on by default and both break the loop) |
| hands-free | `fn`+`space` |
| audio loopback -> VoiceOS transcription | **PROVEN** |
| **`customMcpServers`** | **0 — the crew is NOT connected to VoiceOS** |

**That last row is the only thing between us and the full voice loop, and it is a GUI
step no script can do.** Two minutes, on the demo Mac:

```
VoiceOS window -> Settings -> MCP / custom servers -> Add

  name    : crew
  command : /opt/homebrew/Cellar/node/25.6.1/bin/node
  args    : /Users/vrajpatel/Developer/crew/voiceos-bridge/mcp-server/server.js
```

**Absolute node path, not bare `node`** — VoiceOS is a GUI app and does not inherit a
shell PATH, so Homebrew's node is invisible to it. That is the single most likely way this
silently fails. Do not hand-edit `config.json` instead; it is an electron-store and
rewrites the whole file on its own schedule. `./voiceos-bridge/mcp-server/register.sh`
re-prints these values and audits everything else.

Then: `./run-demo.sh` first (the bridge POSTs to :4001), press `fn`+`space`, say
*"clean up my inbox and schedule everything"*.

### What already works without any of that — run it right now

```bash
./run-demo.sh            # real agents, real reasoning, three human voices  <- THE DEMO
./run-demo.sh live       # the mailbox really changes (15 tool calls, 18 -> 2)
./run-demo.sh fake       # canned, no Claude, no network  <- PANIC BUTTON
```

Last run, just now: **10 lines, 0 dropped**, in alba / northern-english / amy.

### And the crew now hands work to itself

```
researcher  Done: Staging is down; thread says Thursday, notes say Friday.
[crew] wave 2: analyst (has researcher)
analyst     Lining the two Thursday dates up side by side.
analyst     Done: Staging outage is what puts Thursday at risk.
```

The analyst opened on the contradiction the researcher found. It did not go looking for
it and could not have — it was handed it. Try it with:
`"research what is putting Thursday at risk and analyse the numbers"`.

**The rehearsed run is unaffected** — triage and scheduler declare no dependency, so they
still start together, and the demo phrase logs zero waves.

## A — VoiceOS is BUILDING the Crew integration. What happens next, in order

It is not a plain MCP entry — VoiceOS is generating a custom integration around our
server: notch cards, argument controls, and **confirmation cards**. It reasons out loud
while building, and it is reasoning about exactly the thing B has been chasing: which
tools require confirmation, and how `confirmation_cards_json` relates to the manifest.
**Our `annotations` are what it is reading.** B declared them honestly on all 8 tools,
so this should land in our favour without anyone touching code.

Takes a few minutes and keeps building if the window is closed.

### Pre-flighted while it built — the two ways this usually fails, both cleared

1. **VoiceOS spawns our server with no shell, no cwd, no PATH.** Simulated it exactly
   (`env -i`, cwd `/`, absolute node): **initialize OK, all 8 tools listed, stdout clean.**
   This is the failure `register.sh` warns about and it does not apply to us.
2. **It does not hang when the orchestrator is down** — `run_crew_task` returns a reply
   rather than blocking, so a spoken command before `./run-demo.sh` fails fast.

**B — one wording thing, your file, small but it is a stage moment.** With :4001 down the
reply is *"Could not reach the orchestrator at http://localhost:4001 — is it running?
(node orchestrator/server.js)"* — and VoiceOS reads tool replies **aloud, verbatim**. A
character saying "http colon slash slash localhost four thousand one" is a bad ten
seconds. Something like *"The crew isn't awake yet — start it and ask me again"* says the
same thing to a human. Only fires on an error path, so it is polish, not a blocker.

### The order to do things in once the build finishes

1. **`tools/list` must show `crew`.** If it does not, VoiceOS never started the server,
   and the cause is almost always the node path. `./voiceos-bridge/mcp-server/register.sh`
   re-audits.
2. **Note the real tool names.** They will be prefixed — `custom_mcp_crew_*` per B's
   finding. Nothing in our prompts hardcodes them, and nothing should.
3. **Start the orchestrator FIRST**: `./run-demo.sh`. The bridge POSTs to :4001; speaking
   before it is up is the one self-inflicted failure available here.
4. **Press `fn`+`space`, say the phrase.** "Clean up my inbox and schedule everything."
5. **Then ask "what's the crew doing?"** — `crew_task_status` answers in a spoken
   sentence, and that is the beat that makes the loop feel alive rather than one-shot.
6. **Watch for the confirmation card.** If a read-only tool skips it and a write does not,
   annotations are driving it and the loop is autonomous. That is B's question, answered
   live.

### If the spoken path is not reliable by rehearsal

Nothing is lost. **Rungs 1-3 need none of this** and all three work today. The decision to
keep the voice layer swappable behind one HTTP contract is what makes that true.

## ➡️ B (Sameer) — the VoiceOS↔MCP integration is YOURS. A is handing it over

**Why you and not me:** it is your server, your annotations, and your finding that VoiceOS
renames tools. I have the Mac the demo runs on, so I will run whatever you need run — but
the decisions here are yours to make and I should stop making them.

VoiceOS is **building a custom Crew integration** on A's Mac right now (not a plain
`customMcpServers` entry — it generates notch cards, argument controls and **confirmation
cards** around our server). It reasons while it builds, and it is reasoning about
`confirmation_cards_json`, the manifest, and which tools require confirmation. **It is
reading your `annotations`.**

### 1. Confirm the wiring the moment the build finishes (A will run it, you call it)

- `tools/list` shows `crew`. If not, VoiceOS never started the server — the cause is
  almost always the node path, and it must be **absolute**, not bare `node`.
- **Write down the real tool names.** They will be prefixed. Your `custom_mcp_<server>_<tool>`
  finding predicted this; now we get to see it and record the actual strings. Nothing in
  A's prompts hardcodes them, and nothing should start.
- Already cleared on A's side so you do not have to chase them: the server survives being
  spawned with **no shell, no cwd, no PATH** (`env -i`, cwd `/`, absolute node → init OK,
  8 tools, clean stdout), and it does **not hang** when :4001 is down.

### 2. Your `readOnlyHint` question — this is the moment it gets answered

Watch which tools produce a confirmation card:

- read-only tools (`crew_gmail_list_inbox`, `crew_task_status`) skip it, writes
  (`crew_gmail_archive`, `crew_calendar_book`) show it → **annotations drive it, we already
  declare honestly, and the loop is autonomous with no workaround.**
- everything confirms regardless → the voice-answered-confirmation path is the fallback,
  and it is A's finding 6, already known to exist.

Record the answer either way. It is the last unknown in the whole system.

### 3. One wording fix, your file, ~2 minutes — and it is a stage moment

With :4001 down, `run_crew_task` replies:

> "Could not reach the orchestrator at http://localhost:4001 — is it running? (node orchestrator/server.js)"

**VoiceOS reads tool replies aloud, verbatim.** A character saying "http colon slash slash
localhost four thousand one, is it running, node orchestrator dot server dot js" is ten
bad seconds in front of a room. Something a person would say — *"The crew isn't awake yet.
Start it and ask me again."* — carries the same information. Error path only, so it is
polish rather than a blocker, but it is the kind of polish that is only cheap now.

Worth a pass over **every** tool's reply text with the same lens: not "is this correct?"
but "is this a sentence a person would say out loud?" You already did exactly this for
`crew_task_status` and it is the reason that one lands.

### 4. Your own box, when convenient

`customMcpServers` is still 0 on Windows. Not blocking anything — the demo runs on A's
Mac — but a second registration is the only way we would catch a Mac-only assumption
before it matters.

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

- ~~**E → A: a hung agent wedges the run after its timeout.**~~ **FIXED — reproduced with
  your shim, then fixed at both ends.** You were exactly right, including that it is worse
  than a crash: the character says "ran out of time" so it reads as a slow run, and nobody
  reaches for the panic button.
  Repro first, with a shimmed `claude` that prints one line, backgrounds an orphan holding
  stdout, then hangs: 4s timeout, **still `running` at 24s**, recap never ran.
  Two fixes, because the cause and the consequence are different bugs:
  - **cause** — agents now spawn `detached`, so the timeout kills the process *group*
    (`process.kill(-child.pid)`), not just the agent. The orphan dies and the pipe closes.
  - **consequence** — finishing no longer depends on `close` alone. `close` waits on every
    inherited stdio pipe; `exit` waits only on the process. Normal runs still finish on
    `close` with all output drained, and `exit` finishes anyway after a 1.5s grace, so a
    pipe held by something we could not kill can no longer wedge the run.
  Same shim after the fix: **`done` at t+10s, recap ran, zero orphans left behind.** Real
  agents re-run afterwards: 10/10 lines spoken, nothing truncated. Checkpoint 18 ok.
  Thank you for testing rows nobody had tested — you can put the break-glass row back to
  what it originally claimed, and "ran out of time" is a slow agent again rather than a
  dead run.
  **E — re-verified independently on my Mac:** the original wedging shim (child holding
  stdout) against `e87f5c0`: task `done` in ~19s, all three agents flipped, lines spoken,
  **zero orphaned processes**. Break-glass row restored in `demo-script.md`. Closed.

<details><summary>original report (resolved)</summary>

- **E → A: a hung agent wedges the run after its timeout — on rung 2, the plan of
  record.** `child.kill('SIGKILL')` + `child.on('close')` in `server.js`: if the
  hung `claude` spawned a subprocess (it does, for tools), the orphan holds the
  stdout pipe, `close` never fires, and the task never reaches `done` — recap
  never appears. Character still says "ran out of time", so on stage it looks like
  a slow run, not a dead one. Repro + fix options in my section at the bottom;
  `demo-script.md` break-glass row updated in the meantime (treat "ran out of
  time" as the cue to `stop && fake`). Your file, your call — shout if you want
  me to take it.

</details>

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

- **EVERYONE — the Pro trial is now an ELIGIBILITY issue, not just a feature gap.**
  The event rules say: *"This is a voice-only hackathon. All submitted products must be
  built to be controlled and operated primarily using voice commands."* Rungs 1–3 are all
  **typed** — `./run-demo.sh` is a command line. **Rung 4 is the only rung where a human
  controls anything by voice**, and it is the only one we cannot currently run. As it
  stands we would demo a voice-first product using a keyboard, in front of the people who
  make the voice layer.
  **This is unblocked today and nobody has done it:** every participant gets a free month
  of VoiceOS. It is on the event page, and it is the same free month coordination.md has
  been waiting on since last night. Redeeming it is not a workstream — it is a sign-in.
  Whoever gets it first should post `tools/list` output so B can finish the annotations
  check, and A can run `spike.sh demo` in the same five minutes.
  **The hedge, if the trial is somehow still not live by ~16:00:** the human's *opening
  sentence* is the part that has to be spoken. It does not have to be VoiceOS that hears
  it — macOS Dictation types into any focused field, including a terminal, and that alone
  restores "the human spoke, nobody typed". Ugly, but it is the difference between a
  voice-first demo and a disqualified one. A/E's call; flagging it now so it is not a 17:45
  discovery.
  **Nothing about the build changes either way** — `run_crew_task` is already the entry
  point and B's bridge is tested against it. This is purely about who says the sentence.

- **A — the one real blocker: VoiceOS Pro trial is not on A's account yet** (the free month
  from the event). Until it is, the loopback test can't run. BlackHole, the `crew`
  multi-output device, both scripts and the verification query are all ready and waiting —
  it's a 5-minute test, not a workstream. Everything else on A's side is done and tested.
- ~~**Open question for B:** which path carries the inbox.~~ **DECIDED — see the decisions
  log and "B — the Gmail decision" below. A is unblocked; write the real `execution.md`.**

- ~~**B → A: nothing gives the agents the crew tools.**~~ **FIXED AND PROVEN ON THE DEMO
  MAC — rung 3 is real.** Wired with exactly the two values `mcp-config.js` prints,
  generated at spawn rather than committed, and only for `direct` (narrate stays toolless,
  which is why it is the safe rung; voice gets Bash). Tool calls are counted and logged —
  never narrated, since the dock speaks these lines and a character reading a function
  name to the room is worse than no line. A `direct` run ends by stating which happened.
  **Your `.crew-mailbox.json` check, run:** `"clean up my inbox and schedule everything"`,
  15 tool calls, and the mailbox afterwards — **inbox 2 of 18, the two left are Marcus
  Webb and Sandra Okonkwo, Q3 rollout booked Mon 2:00 PM.** The line the whole demo exists
  for is now literally true of a real mailbox rather than narrated over one.
  Two notes back: your `checkpoint.sh` false-green is fixed — it runs a real one-turn
  `claude -p` instead of testing for the binary, and it would fail on your box, which is
  the point. And Priya landed 9:30 rather than the 10:00 the prompt suggests, because the
  agent trusted `crew_calendar_find_slot` over the prompt — correct behaviour for direct
  mode, and it conflicts with nothing on the seeded calendar.

<details><summary>original report, kept for the record</summary>

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

</details>

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

- **D → A: on a machine without `node`, `./checkpoint.sh` hangs forever instead of
  failing.** Found on the fifth machine (mine, a clean setup) — the tradition holds.
  `checkpoint.sh` correctly prints `FAIL no node` in the `everyone:` block, then keeps
  going and **never returns**. I left it 8 minutes before killing it.
  The hang is [`orchestrator/test.sh`](orchestrator/test.sh) line 23:
  ```sh
  until curl -sf localhost:4001/status/nope -o /dev/null || [ $? -eq 22 ]; do sleep 0.2; done
  ```
  It waits for `server.js` to bind `:4001`. With no node, nothing ever binds, so `curl`
  exits **7** (couldn't connect) on every pass and never **22** (the HTTP-error code that
  means the server answered). The loop has no attempt cap and no timeout, so it spins
  until someone kills it. `checkpoint.sh` line 99 calls it with no timeout either.
  **Why it's worth a fix and not just a note:** this is the same family as the stale
  binary and the `SAY ->` false green — *the check cannot report the failure it has
  already detected*. A new machine gets a hang with no message rather than the one line
  that tells them what to install. E's row says each new machine finds something; this is
  what the fifth one found, and it costs a newcomer their first ten minutes.
  Suggested one-liner, your file so I haven't touched it — bound the wait and say why:
  ```sh
  for _ in $(seq 1 100); do curl -sf localhost:4001/status/nope -o /dev/null || [ $? -eq 22 ] && break; sleep 0.2; done
  [ $? -eq 0 ] || fail "server never came up on :4001 (is node installed?)"
  ```
  Unblocked myself by installing node; **CHECKPOINT PASS on `6255b5d` (12 ok, 0 failed,
  6 N/A)** — no BlackHole/switchaudio/enhanced voices/claude CLI/uv here, all expected
  for the art role. Nothing about this blocks my own work.

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

**C (Abhishek) owns `crew-dock/Sources/**` and wires the manifest up.** ~~Agree the JSON
shape with them before you fill it in.~~ **Already done — don't wait for me.**
`crew-dock/characters.json` and its loader are on `main` (commit `3b82021`), so the
conversation you were told to have has happened and **the only thing missing is the art**:

```json
{ "role": "researcher", "asset": "walk-researcher-01", "mirrored": false }
```

Drop the `.mov` in `Assets/`, add that row, `./crew-dock/build.sh`. No Swift, and you
never need to touch `Sources/**`.

**I tested your exact path before handing it to you** — added a `researcher` row against
an existing clip and ran the curl from your task block above. The dock logged
`roster: triage, scheduler, researcher, recap (from characters.json)` and the character
appeared on screen in slot 3 with its bubble. Then I reverted it, because the art is
yours and a duplicated sprite is the thing you're here to fix. **So the wiring is proven
and waiting; the row works the moment the file exists.**

Two things worth knowing before you start:
- **`rate` is keyed on `activity`, not on the role** (`"activities": {"research": {"rate": 0.90}}`)
  — so two agents doing research move alike and the manifest never learns the roster.
  That was A's design intent; it's wired.
- **A bad edit here cannot break the rehearsed run.** Missing, unreadable, or empty
  manifests all fall back to the built-in three and say so in the log — all three tested.
  If you edit the file and see no change, check stderr: it names the path it rejected.

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

### B — the conversation demo, the env inventory, and the feedback prize

**`node voiceos-bridge/mcp-server/demo-conversation.js` — the demo as a dialogue.**
Every way we run this project shows the machinery: narration lines, dock logs, PASS.
None of them show the *product*, which is a person talking to a crew and being answered.
This drives the real MCP server over real stdio — the exact calls VoiceOS makes — and
prints it as a conversation. Against `FAKE=1 node orchestrator/server.js`, unedited:

```
  you  >  "Clean up my inbox and schedule everything"
  crew >  The crew is on it. Task task_1 started — the agents are waking up on the dock now.
  you  >  "What's the crew doing?"
  crew >  Triage is scanning the inbox and Scheduler is reading the flagged emails. Recap hasn't started yet.
  you  >  "How is it going?"
  crew >  Triage is archiving six newsletters and Scheduler is finding open slots tomorrow. Recap hasn't started yet.
  you  >  "Are they done yet?"
  crew >  The crew is finished. Inbox cleared, two meetings booked.
```

**It is the demo minus the microphone.** When the trial lands, VoiceOS replaces the
left-hand column and nothing else changes. Runs on any machine — no account, no Mac, no
network, no Claude spend. `SPEAK=1` reads the crew's replies aloud on macOS.
**E — this is your screen recording.** The dock is the show, but this is the pitch, and
it records cleanly in a terminal without needing the rig up. It exits 2 with a readable
sentence if nothing is on `:4001`, so it cannot fail confusingly on stage.

**`.env.example` at the repo root — every credential and knob in one place.** Built by
grepping what the code actually reads, not from memory: 24 variables, grouped by which
rung needs them, with the two Google files and the VoiceOS config called out as the only
real secrets. **Note: nothing in this repo loads `.env` automatically** — we are Node
stdlib only on purpose — so it documents `set -a; . ./.env; set +a`, which I verified
works. `.env` is now gitignored, `.env.example` is not.

**`voiceos-bridge/VOICEOS-FEEDBACK.md` — submission-ready for the $100 feedback prize.**
Judged on quality and usefulness, not upvotes, and we have done more VoiceOS
archaeology than anyone here: no CLI on Windows while the docs say otherwise, the
`custom_mcp_` renaming that fails silently, `muteWhenDictating`/`agentVoiceEnabled`
killing loopback rigs, `fn` being unsynthesizable, and the concrete ask — **derive
`requiresConfirmation` from MCP annotations**, which is the single change that would let
agent products run unattended on VoiceOS. Findings only; no config contents, no tokens.
**Someone with a Product Hunt account made before the event needs to post it** — that is
a rule we cannot retrofit, so check now whether any of the five of us qualifies.

### B — VoiceOS is ACTIVE on Windows. Audited it. One gap, and it is the important one

Pro is live, onboarding is finished, **and Gmail is connected.** Read with `register.ps1`,
which prints an allowlist of keys and never dumps the file:

```
onboarding.onboardingCompleted   True     <- the paywall is behind us
connectedIntegrations            gmail    <- NEW. finding 4 said "no Gmail path at all"
customMcpServers                 0        <- *** VoiceOS CANNOT REACH THE CREW ***
settings.muteWhenDictating       True     <- still on; kills a loopback rig
settings.agentVoiceEnabled       True     <- still on; VoiceOS hears its own replies
```

**The gap: `customMcpServers` is empty, so `run_crew_task` does not exist as far as VoiceOS
is concerned.** Everything either side of that hop is tested — VoiceOS hears you, our
server answers, the crew runs — but nothing connects them yet. **There is no CLI on
Windows, so this is a GUI step somebody has to do:** tray icon → Settings → MCP / custom
servers → Add, with the command and args that `.\voiceos-bridge\mcp-server\register.ps1`
prints. Thirty seconds. Until it is done, `run-demo.ps1 -Voice` will tell you so rather
than waiting three minutes for a call that cannot come.

**A — two of your findings are now stale on Windows, and one may be stale on your Mac.**
1. **Finding 4 ("Gmail is not connected to VoiceOS at all") no longer holds here** —
   `connectedIntegrations` is `gmail`. It does **not** change the Gmail decision: we chose
   MCP because the mailbox has to be *seeded deterministically* and VoiceOS's own Gmail
   integration cannot do that. The decision stands on its original reasoning, not on
   Gmail being unreachable. Worth knowing before someone re-opens it at 5pm.
2. **The config schema is nested now** — `muteWhenDictating` and `agentVoiceEnabled` live
   under `settings`, `onboardingCompleted` under `onboarding`. **Your `voiceos-setup.sh`
   already reads them that way, so you are fine** — I checked before flagging it. But the
   Findings section higher up in this file still describes them as top-level, so anyone
   grepping the config by hand will look in the wrong place.
3. **New key nobody has seen: `codingAgentDangerouslyBypassPermissions` (currently
   `False`).** We have all been saying "no confirm bypass exists". A key with that name
   says one exists for at least one path. It is not obviously ours — it reads like it is
   for VoiceOS's coding-agent feature, not for custom MCP tools — but it is the first
   evidence in either direction, and it is worth five minutes from whoever tests
   confirmations first. **Do not flip it blind on the demo machine**; find out what it
   governs first.

**Still missing on my box, and it cannot come through git:** `credentials.json` and
`token.json` for the `google` backend. Both are gitignored on purpose and must stay that
way — **credentials are not a thing the repo can "have".** `CREW_BACKEND=fake` needs
neither and does real archiving and real booking with real numbers, so nothing an audience
sees depends on them. VoiceOS having Gmail connected is a *different* link from ours and
does not substitute for these.

### Where everyone is, and the ONE task each that is actually left

Nothing here reassigns work anybody is mid-way through. Four of five workstreams are
done; this is what is genuinely still open.

| | state | the one thing left |
|---|---|---|
| **A — Vraj** | voice loop proven, Piper voices in, rungs 1-3 real | **the long-task feedback loop** (below) — the only unbuilt feature |
| **B — Sameer** | 8 tools, both platforms, `run-demo.ps1` | **OWNS the VoiceOS↔MCP integration** — see the handover section: confirm `tools/list`, record the real prefixed names, answer `readOnlyHint` from the confirmation cards, and make the tool replies sound like sentences |
| **C — Abhishek** | dock done, stall indicator, `register.sh` | **nothing.** Take `crew-say`/`Narrator` back if you want it; it is one line |
| **D — Yaseen** | unblocked, art not started | **`recap` art.** It is the only workstream nobody else can do |
| **E — Rukaiya** | all three deliverables done, rung 2 proven on the backup rig | ~~re-record~~ **done — re-cut with the Piper voices, 95s, 10/10.** Next: deliver the talk out loud over a run |

**E — the recording is stale and that is my fault, not yours.** The crew sounded like a
screen reader when you recorded it and it does not any more. `./crew-dock/voices.sh
piper-install` then `./run-demo.sh fake` and the same 10 lines come out in three human
voices. Worth re-cutting because the safety video is the thing we fall back to, and it
should not be the worst-sounding version of the demo. Second, if you have time after: the
live talk has never been said out loud over a run — the beats are written, nobody has
stood up and delivered them.

**A — what I am building next, and the honest trade.** Vraj wants a live talk where one
long spoken task gets divided, agents spawn, and a feedback loop runs. Today routing is
keyword-based against a fixed crew and agents never see each other's output — the closer
gets the roster, nothing else does. Two ways:

- **scripted division** — a known long task maps to a known hand-off chain
  (researcher → analyst → recap), each agent seeing the previous one's result. Rehearsable,
  and it is what an audience experiences as decomposition anyway.
- **real planner** — an agent reads the task and decides the crew. Genuinely better, and
  it is the thing that can be wrong in front of a room, which is exactly why routing was
  hardcoded in the first place.

Building the scripted one unless told otherwise. **Neither touches the rehearsed run** —
"clean up my inbox and schedule everything" keeps routing to triage + scheduler + recap.

### Then: one task each, in priority order

**A (me) — next:** ~~finish the voice loop the moment the Pro trial lands~~ **DONE — the
loop is proven** (`say` → BlackHole → VoiceOS → text in a real app). It was never the
`dictations` table; transcripts are in `voice_sessions`. What's left of it is quality, not
existence: a full sentence came back as `"Log"`. Rung 4 (`./run-demo.sh voice`) is written
and now has a working path under it.

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

---

### E — the backup rig exists: fourth machine, clean clone, CHECKPOINT PASS

Deliverable 1 done, the way C did it — a throwaway clone into an empty directory,
not my working copy. **Clone → built dock → full `fake` show in 72 seconds**, then
`./checkpoint.sh`: **17 ok, 0 failed, 3 N/A** (no switchaudio-osx / BlackHole /
enhanced voices — expected for the backup role). 16 lines reached the dock, 10 spoken
out loud, none dropped, correct order, all three voices.

What the fourth machine found — the tradition holds:

1. **C's speaker fallback fired for real, and it saved the run.** This is an Air, so
   the hardcoded `MacBook Pro Speakers` doesn't exist. The dock warned
   (`SAY !! no audio output device named "MacBook Pro Speakers"`), named the real
   device, and spoke all 10 lines on `MacBook Air Speakers`. That's the second
   hardware confirmation of C's resolver — though still not the discriminating case
   (no BlackHole installed here either, same honest limit C noted).
2. **Onboarding's "no network" claim was false on first run** — `build.sh` fetches
   ~18MB of character art from lil-agents. C documented this; onboarding still said
   "no network". Fixed in `docs/onboarding.md`: first build needs network once,
   offline after.
3. **The documented clone command assumes SSH keys.** `git@github.com:` fails on a
   machine without them — exactly the machine a backup rig might be. Onboarding now
   uses the HTTPS URL.
4. **Checkpoint FAILed twice for a good reason: origin moved while it ran.** The
   team pushed 5 commits during my ~3-minute run. Not a machine problem — but worth
   knowing that on a busy afternoon "pull, then checkpoint" can lose the race, so on
   stage day freeze pushes before the pre-flight check.

Next, in order: the break-glass table in `docs/demo-script.md` (every row is an
untested claim), then `docs/runbook.md` plus a recorded clean run.

### E — the break-glass table is now tested, and one row was hiding a real bug

Deliverable 2 done. Every testable row of the "When it breaks" table, exercised for
real on this Mac, zero Claude spend. What holds exactly as written:

- **`stop && fake` mid-run** — killed a run at +8s; the second show came up clean,
  10/10 lines spoken, 27s total.
- **Dead dock** — killed the dock at +6s; the orchestrator finished the whole task
  against nothing, no crash, POSTs failed silently as designed.
- **Dead orchestrator** — killed it at +6s; the dock stayed up with its 6 received
  lines. (C's stall indication will make this state visible.)
- **CREW_MUTE=1** — 16 received, 0 spoken, and the run summary says so honestly.
  One wart: `run-demo.sh` then waits ~60s for a spoken recap line that can never
  come. Harmless, just slow — A, a `CREW_MUTE` check before that wait loop would
  save a confused minute.
- **Bad voice name** — `say -v NoSuchVoice` exits **0** and speaks in the system
  default voice (verified by rendering to file: ~1.2s of real audio). So a voice
  typo costs an accent, not a line — and C's per-line exit check *cannot* catch it,
  because `say` doesn't fail. The preflight `voices.sh check` is the only guard.

**A — the one that matters: the 180s timeout can wedge the run, and it's on the
rehearsed rung.** Repro with a shimmed `claude` and `AGENT_TIMEOUT_MS=5000`:

- shim = `bash` that runs `sleep 600` as a *child* → SIGKILL kills the shim, the
  orphaned child keeps the stdout pipe open, `child.on('close')` never fires, so
  `finish()` never runs: the agent says "Done: ran out of time" (spoken and
  bubbled — that half is true) but stays `working` forever, **recap never starts,
  `/status` never says `done`**, and `run-demo.sh` polls its full 120s in silence.
- shim = `exec sleep 600` (no grandchild) → everything works: all three agents
  flip to `done`, task completes in ~19s.

The real `claude` CLI spawns subprocesses for tools, so a genuine hang is likely
the *first* shape, not the second. Fix is one of: key `finish()` off `exit`
instead of `close`, or spawn detached and kill the process group. `server.js` is
your file — shout if you'd rather I did it.

Not tested, honestly labeled: "pull the network" (fake mode makes no network
calls by construction, and the only network dependency — first-build art fetch —
is now documented in onboarding); "a character freezes" (no way to induce it
deliberately). The table in `demo-script.md` now records all of this next to the
rows it corrects.

### E — Piper works on the backup rig, and its installer asks for one thing it doesn't need

**A: the voices are lovely and they run here — 10/10 spoken, 0 dropped, one
expected `MacBook Pro Speakers` warning.** Verified on the fourth machine the way
you'd want: models fetched from nothing, then a full `fake` run with
`run-demo.sh` auto-detecting them and pacing at `LINE_MS=5500`.

**One finding, and it's a 5pm-shaped one: `./crew-dock/voices.sh piper-install`
refuses to run without `sox`, but nothing at run time needs it.** On this Mac
(uv yes, sox no) the installer stops at `needs sox: brew install sox` and fetches
nothing. Yet `crew-say`'s own playback line is
`play -q … || afplay … || say_fallback`, and **`afplay` is on every Mac** — I
downloaded the three models by hand, ran `CREW_TTS=piper` (which fails loudly
rather than falling back), and all three voices played through `afplay`: real
Piper audio, 22050 Hz, 1.4s for "Scanning the inbox.". So the gate sends someone
to Homebrew — network, a minute or two, possibly during pre-flight — to install
something the demo never calls. Suggest the check becomes
`command -v play || command -v afplay`, or drops to a warning. `voices.sh` is
yours, so flagging rather than editing.

**Second, smaller: this pull is a stale-binary trap for everyone.** It brings new
Swift, so `./checkpoint.sh` **FAILed** for me immediately after `git pull` —
`dock binary is OLDER than its sources`. C's guard caught it exactly as designed;
`./crew-dock/build.sh` then PASS, 15 ok / 0 failed. Anyone who pulls this and
doesn't rebuild is grading the old voices.

Worth knowing for the rig: models are gitignored (~63MB each), so **the backup
Mac needs a network pass of its own** before it can sound like the demo Mac —
`voices.sh piper-install` is not something to discover at 5:50pm on venue wifi.
Fresh clone still gets the 2005 voices and a working show, which is the right
default.

**A — the safety video is re-cut with your voices.** 95 seconds, 10/10 lines,
three human accents, 19MB. The old screen-reader one is kept alongside it as
`crew-clean-run-OLD-voices.m4v` and should not be the one that gets played.

**One thing to check before trusting any of these recordings, ours or yours:**
my first attempt looked like a success and wasn't. `screencapture` wrote a 4MB
file that played as **8 seconds** of a 95-second run — no error, exit 0, a real
`.mov` on disk. Same trap as the orchestrator log and `SAY ->`: the artefact
existing is not evidence the artefact is right. `afinfo <file> | grep duration`
is the 1-second check, and a good capture of this run is ~90MB raw, not 4MB.

### E — I ran the research crew with real agents: the loop works, the stage doesn't

**A — the feedback loop is real, and it is the best thing in the project.** I ran
`"research the Q3 rollout and analyse the numbers"` against real agents (narrate,
not fake): **done in 69s**, researcher → analyst → recap, and the analyst
provably read the researcher's output rather than re-deriving it —

```
researcher  Done: Rollout date conflicts; only two o'clock tomorrow is open.
analyst     Done: Staging is down; that blocks the rollout, not the calendar.
recap       Done: only tomorrow at two is free, and staging being down blocks it.
```

The analyst's answer *changes the question* — the meeting isn't the problem — and
the closer reported only what ran, no phantom inbox. That is a much better story
than the inbox demo, and it is working today.

**But on screen it is currently a blank wall and one voice.** Two gaps, both
already known, both now measured rather than predicted:

1. **D — 12 of the 16 messages hit nothing.** The dock logged
   `roster: triage, scheduler, recap (from characters.json)` and then
   `(no character named 'researcher')` twelve times. Researcher and analyst spoke
   to an empty screen for the entire run. **This is the whole cost of the missing
   art in one number** — if the long-task talk features research and analysis
   live, three quarters of it is invisible. The wiring is done and waiting; only
   the `.mov`s are missing.
2. **A — every new-role line came out as Samantha, the fallback voice.**
   `CREW_VOICE_*` defines triage/scheduler/recap only, so researcher and analyst
   share one default — a two-agent conversation in a single voice, talking to
   itself. With Piper this is worse than before, because `crew-say` maps its
   models off those same three names (`Moira|triage`, `Daniel|scheduler`,
   `Karen|recap`), so the new roles miss the good voices *and* each other's
   distinctness. C flagged this shape early (the override loop iterates the three
   known keys); it now has a run behind it.

**Nothing here touches the rehearsed demo** — "clean up my inbox and schedule
everything" still routes to triage + scheduler + recap and I re-verified that
separately. This only matters if the long-task talk goes on stage.

---

### D — I own a folder git is told to ignore, and the obvious fix silently fails

`docs/onboarding.md` gives me `crew-dock/Assets/**`. `.gitignore` line 15 ignores it.
So **there is currently no route for original character art to reach the demo Mac** —
the folder only ever held clips `build.sh` downloads from upstream lil-agents, and
upstream has exactly the two we're trying to get away from. Nobody hit this before
because I'm the first person to make an asset instead of fetching one.

**The trap: adding a `!` exception does not work, and fails quietly.** Git never
descends into an excluded *directory*, so the negation is never even consulted.
Verified in a scratch repo rather than assumed:

```
crew-dock/Assets/     + !crew-dock/Assets/walk-recap-01.mov   -> STILL IGNORED
crew-dock/Assets/*    + !crew-dock/Assets/walk-recap-01.mov   -> commits correctly
```

The fix is the trailing `/` becoming `/*`:

```diff
-crew-dock/Assets/
+crew-dock/Assets/*
+!crew-dock/Assets/walk-recap-01.mov
```

Upstream's `walk-bruce-01.mov` / `walk-jazz-01.mov` stay ignored, so the repo does not
gain 18MB of someone else's MIT art and the README's "fetched at build time, not
committed" stays true of everything except what I drew.

~~**A/C — flagging rather than landing it, because the ~20MB cap needs a number.**~~
~~**Priority note, A's call not mine:** recap or researcher/analyst first?~~

**BOTH ANSWERED BY A in `4e8d202` — nothing open here, don't re-read the above.**

- **The ignore rule is fixed, and A found a smaller fix than mine.** Ignoring the two
  upstream files *by name* means no directory is excluded, so the descent trap never
  applies and anything I draw is committable **without another `.gitignore` edit ever**.
  Mine needed a new `!` line per clip; this needs none. Verified on my machine:
  `walk-recap-01.mov` and `walk-researcher-01.mov` committable, both upstream clips
  still ignored.
- **Size: 4MB per clip, 20MB total committed, upstream's 18MB doesn't count.** Constraint
  is clone time (E's 72s), not disk. Format: HEVC+alpha, 1080×1920 — and `AgentCharacter`
  scales to 170pt, so detail past that is wasted bytes.
- **Priority: `recap` first and alone if only one.** Then triage/scheduler; researcher
  and analyst last, off the rehearsed path.

Casting against the Piper voices: recap = amy (warm), triage = alba (Scottish, dry),
scheduler = northern english male (brisk).

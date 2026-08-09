# Crew — team coordination

This file is the single source of truth for the day. Commit it to the repo root and push often — pull before you start each new chunk of work, and update your row every time you finish a milestone (not just at lunch/end of day).

**The contracts below are frozen.** All three of you build against them starting now, in parallel, without waiting on each other. If one genuinely needs to change, post in the group chat first — everyone else is already coding against the version below.

**Testing discipline:** test after every change, not at the end of the day. If you've gone more than ~20-30 minutes without actually running what you built, stop and run it. A pile of untested code the night before a demo is the thing that kills demos.

---

## Devices (this matters — see note below)

- **A** — Claude Max, **Mac** — **confirmed demo machine**
- **B** — **Windows**, OpenAI Plus + Claude Pro
- **C** — Mac, Claude Pro — builds here, brings the build over to A's Mac for integration

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
| A | orchestrator | **both endpoints live + full 3-agent run works end to end (28s), real `claude -p`** | audio spike needs `brew install` (needs A at keyboard) |
| B | voiceos-bridge | not started | — |
| C | lil-agents-dock | not started | — |

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
- BlackHole itself: **installed and working.** `blackhole-2ch` + `switchaudio-osx` in, multi-output device **`crew`** (BlackHole + MacBook Pro Speakers, drift correction on the speakers) built and switchable from the CLI. Verified routing on/off cleanly.
- VoiceOS trigger key rebindable away from physical Fn: **YES — confirmed**
- VoiceOS auto-confirm / trust setting for agent actions: no on/off switch in the config, **but confirmations can be answered by voice** — see finding 6, this is better news than a trust setting
- B's Windows test: does VoiceOS-for-Windows correctly call `run_crew_task` from a normal spoken command? untested
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

## Decisions log

- _Sat night — orchestrator is one file (`orchestrator/server.js`), Node stdlib only, not the 4-file TypeScript layout in the folder plan — A — no build step, no `npm install`, no deps to break at 5pm; the whole thing is ~170 lines and restarts instantly. The frozen bit is the HTTP contract, and that's unchanged._
- _Sat night — execution path (speech vs MCP) is isolated in ONE file, `orchestrator/prompts/execution.md` — A — when B decides, we swap that file and the three role prompts don't change. Both options are already written in it, commented out. Right now it's dry-run: agents narrate but call no tools, so tonight's testing can't touch real mail._
- _Sat night — narration is paced by the orchestrator (~1.4s/line), not by token arrival — A — the model emits all its lines in one burst, so without pacing a character jumps straight to "Done:" and the dock looks dead. Found this on the first live run._

## Blockers

- **A — the one real blocker: VoiceOS Pro trial is not on A's account yet** (the free month
  from the event). Until it is, the loopback test can't run. BlackHole, the `crew`
  multi-output device, both scripts and the verification query are all ready and waiting —
  it's a 5-minute test, not a workstream. Everything else on A's side is done and tested.
- **Open question for B, needed early:** Gmail has no path through VoiceOS today (finding
  4). But Apple Mail is scriptable from inside VoiceOS (finding 7). Pick one: MCP owns
  Gmail, Apple Mail carries the inbox natively, or the inbox half is narrated over seeded
  data. This changes what your MCP server needs to expose, so decide before building it.

## Demo script

_(write this ~5pm once the run is rehearsed — exact trigger phrase, exact seeded emails, exact expected outputs, timing)_
---
name: crew
description: Use when working on the Crew hackathon repo - the frozen interface contracts between the three workstreams, how to test your own side in isolation without waiting on anyone, and the sync ritual for coordination.md. Invoke before building anything that crosses a workstream boundary.
---

# Crew — working across three machines on one demo

Demo: Sunday 6pm, Frontier Tower SF. One rehearsed run beats a general solution.
**Hardcode things. Script things.** A narrow thing that works reliably wins.

## The frozen contracts

Do not change these shapes. If one genuinely must change, post in the group chat
BEFORE editing — the other two are already coding against it.

```
POST http://localhost:4001/start-task     (A owns, B calls)
  ->  { "instructions": string }
  <-  { "taskId": string, "status": "started" }

GET  http://localhost:4001/status/:taskId (A owns, B calls)
  <-  { "taskId": string, "status": "running"|"done",
        "agents": [ { "name": string, "state": "idle"|"working"|"done",
                      "lastMessage": string } ] }

POST http://localhost:4002/agent-status   (C owns, A calls)
  ->  { "character": "triage"|"scheduler"|"recap",
        "message": string, "state": "working"|"done"|"idle" }
```

Two things that surprise people:
- `state` can be `idle` before an agent wakes. Treat anything not `done` as running.
- The final `Done:` line is POSTed **twice** — once `working`, then `done`. The second
  is the signal to stop animating. Key animation off `state`, not off the text.

## Test your own side without waiting on anyone

Nobody should ever be blocked on someone else's process being up.

```bash
./run-demo.sh fake        # whole pipeline, canned narration, no Claude spend
./run-demo.sh             # whole pipeline, real headless agents (~30s)
./run-demo.sh stop        # kill everything

node orchestrator/fake-dock.js       # stand-in for C's listener, prints what it gets
FAKE=1 node orchestrator/server.js   # stand-in for A's brain, canned agents

curl -X POST localhost:4002/agent-status -H 'content-type: application/json' \
  -d '{"character":"triage","message":"Scanning the inbox.","state":"working"}'
curl -X POST localhost:4001/start-task -H 'content-type: application/json' \
  -d '{"instructions":"clean up my inbox and schedule everything"}'
```

## Before you commit

1. `git pull --rebase origin main` — always rebase, the three of us touch
   coordination.md constantly and merge commits make it unreadable.
2. Run the thing you changed. `orchestrator/test.sh` must still print PASS.
3. Update **your row** in `coordination.md` — status and what you're blocked on.
   Update it when you hit a milestone, not at the end of the day.
4. Push to `main`. Small commits, pushed often, beat one big one at 5pm.

## Machine constraints that have already bitten us

- **The demo Mac (A's) has Command Line Tools but no full Xcode.** `xcodebuild` does
  not run there. Anything with an `.xcodeproj` or a package graph cannot be built on
  the machine that matters. `crew-dock/build.sh` uses `swiftc` alone for this reason.
  If you build Swift in Xcode, hand over a **pre-built `.app`**, not source.
- **`fn` cannot be synthesized in software** on macOS. No script can press it. Design
  around one human press of hands-free mode, not a per-utterance trigger.
- **Audio loopback leaves the Mac with no working microphone** until it's undone.
  `voiceos-bridge/audio-loopback/spike.sh off` — always, every time.
- `~/Library/Application Support/VoiceOS/config.json` holds **live auth tokens**.
  Never commit, paste, or screenshot it.

## Demo-day panic buttons

- Agents failing or slow → `./run-demo.sh fake`. Canned narration, no Claude calls,
  no network. The dock still performs the full show.
- Dock not up → orchestrator keeps running; its POSTs fail silently by design.
- An agent hangs → 180s hard timeout kills it and the character says "ran out of time".

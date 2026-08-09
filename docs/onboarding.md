# Start here — you have a demo on Sunday at 6pm

Five people, one Mac on stage, one rehearsed run. Read this once (5 minutes),
then work. `coordination.md` is the live state; this file is the process.

---

## 1. Sixty seconds to a running demo

```bash
git clone git@github.com:vraj00222/crew.git && cd crew
./run-demo.sh fake
```

That's it. No `npm install`, no build step, no accounts, no API keys, no
network. Three characters walk onto your dock, talk out loud, and finish. If
that worked, you have the whole system running and you can start.

```bash
./checkpoint.sh      # ~60s — proves your machine matches everyone else's
```

It ends in one line: `CHECKPOINT PASS` or the exact thing that failed. It skips
what your machine can't do (no BlackHole on Windows, no `uv` on some Macs) —
that's expected, not a failure. **If it fails, that failure is your first task.**

---

## 2. Who owns which files

**This table is how we avoid merge conflicts.** Edit inside your own rows
freely. To change someone else's file: do it, then say so in your commit
message and tag them in `coordination.md` — don't do it quietly.

| area | owner | files |
|---|---|---|
| orchestrator, prompts, audio rig | **A — Vraj** | `orchestrator/**`, `run-demo.sh`, `checkpoint.sh`, `voiceos-bridge/audio-loopback/**` |
| VoiceOS bridge, Gmail/Calendar tools, seeding | **B — Sameer** | `voiceos-bridge/mcp-server/**`, `voiceos-bridge/demo-seed/**`, `voiceos-bridge/verify.ps1` |
| the dock: characters, bubbles, narration | **C — Abhishek** | `crew-dock/Sources/**`, `crew-dock/build.sh` |
| character art + visual identity | **D — Yaseen** | `crew-dock/Assets/**`, `crew-dock/characters.json` |
| rehearsal, resilience, backup rig | **E — Rukaiya** | `docs/**`, `docs/runbook.md` |
| everyone, constantly | all | `coordination.md` |

`coordination.md` is the one file we all edit. **Only ever touch your own row**
in the Status table, and add new sections at the bottom rather than rewriting
someone else's.

---

## 3. The merge ritual — four commands, every time

```bash
git pull --rebase origin main     # ALWAYS rebase. never merge.
# ... work ...
./checkpoint.sh                   # must PASS before you push
git add -A && git commit
git pull --rebase origin main && git push origin main
```

**Rebase, never merge.** Five people touch `coordination.md` constantly and
merge commits make its history unreadable.

**Push small and often.** Four small pushes beat one big one at 5pm — with five
people, a large diff that has sat for three hours is guaranteed to conflict.

### When `coordination.md` conflicts (it will)

Almost always two people edited the Status table. Keep **both** rows — yours and
theirs — and delete only the `<<<<<<<`/`=======`/`>>>>>>>` markers.

```bash
git add coordination.md && git rebase --continue
```

If a conflict is in code rather than prose and you didn't write either side,
stop and ask the owner in the table above. Don't guess at someone's intent the
day of a demo.

---

## 4. How we write code here

The repo is deliberately boring, because it has to work at 6pm on a Sunday in a
room full of people.

- **No dependencies.** The orchestrator and the MCP server are Node stdlib only.
  The dock is `swiftc` alone — no Xcode, no package graph, no signing. Nothing
  in this repo needs `npm install`. Keep it that way; a dependency that resolves
  today can fail to resolve on stage.
- **Hardcode the demo.** We know Sunday's phrase. A narrow thing that works
  every time beats a general thing that works most times. There is no planner,
  just keyword routing, on purpose.
- **Every change gets run.** Not "it compiles" — run it. If you have gone 30
  minutes without executing what you wrote, stop and execute it.
- **A log is not evidence.** This has cost us three separate bugs: a process
  that reports success while doing nothing. The orchestrator log says what it
  *sent*. What the audience got is in `/tmp/crew-dock.log`. If your claim is
  about the screen, check the screen — C caught a "fixed" frozen character by
  hashing screenshots after the log said everything was fine.
- **Fail loudly.** If a port is taken or a file is missing, print why and exit
  non-zero. Silent degradation is the failure mode that kills demos, because it
  looks exactly like success until the room is watching.
- **Leave one runnable check** behind any non-trivial logic. Not a framework —
  the smallest thing that fails if the logic breaks.

---

## 5. Test your own side without waiting for anyone

Nobody should ever be blocked on someone else's process being up.

```bash
./run-demo.sh fake                   # whole pipeline, canned, no Claude spend
./run-demo.sh                        # whole pipeline, real agents (~45s)
./run-demo.sh stop                   # kill everything

FAKE=1 node orchestrator/server.js   # A's brain, canned agents
DOCK_PORT=4102 node orchestrator/fake-dock.js   # stand-in for C's dock

curl -X POST localhost:4002/agent-status -H 'content-type: application/json' \
  -d '{"character":"triage","message":"Scanning the inbox.","state":"working"}'
curl -X POST localhost:4001/start-task -H 'content-type: application/json' \
  -d '{"instructions":"clean up my inbox and schedule everything"}'
```

Full contracts and gotchas: type `/crew` in a Claude Code session in this repo.
For your next task: `/crew-next`.

---

## 6. The frozen contracts

Do not change these shapes. If one genuinely must change, post in the group chat
**before** editing — four other people are already coding against them.

```
POST :4001/start-task     -> {instructions}  <- {taskId, status}
GET  :4001/status/:taskId <- {taskId, status, agents:[{name,state,lastMessage}]}
POST :4002/agent-status   -> {character, message, state, activity}
```

Two things that surprise people:
- `state` can be `idle` before an agent wakes. Treat anything not `done` as running.
- The final `Done:` line is POSTed **twice** — once `working`, then `done`. Key
  animation off `state`, not off the text.
- `activity` is additive and safe to ignore: `sorting`/`booking`/`research`/
  `analysis`/`summary`. It's what the agent is *doing*, vs `character` = who it is.

---

## 7. Machine gotchas that have already cost us time

- **The demo Mac has no full Xcode** — `xcodebuild` does not run there. Anything
  with an `.xcodeproj` cannot be built on the machine that matters.
- **`fn` cannot be synthesized in software** on macOS. No script can press it.
  Design around one human press, not a per-utterance trigger.
- **Audio loopback leaves the Mac with no microphone** until undone.
  `voiceos-bridge/audio-loopback/spike.sh off` — always, every time.
- **`~/Library/Application Support/VoiceOS/config.json` holds live auth tokens.**
  Never commit, paste or screenshot it.
- **Windows commits must be LF.** `.gitattributes` enforces it; a `.sh` with
  CRLF dies as `bad interpreter: /bin/bash^M` on the demo Mac.

---

## 8. Panic buttons

| when | do |
|---|---|
| agents slow, erroring, or expensive | `./run-demo.sh fake` — full show, no Claude, no network |
| something is stuck on a port | `./run-demo.sh stop` |
| "is my build current?" | `./checkpoint.sh` — it fails if the dock is older than its sources |
| lost | `/crew-next` |

`docs/demo-script.md` is the run itself — the four rungs, the pre-flight list,
the beat sheet, and what to do when something breaks on stage.

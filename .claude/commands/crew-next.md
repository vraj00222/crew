---
description: Sync with the team, verify this machine, and show me my next task
---

You are helping one member of a five-person hackathon crew pick up their next
piece of work. **Do the sync before you say anything.**

If this person has clearly never run the project before (no local commits, or
they say so), point them at `docs/onboarding.md` and `./run-demo.sh fake`
first — sixty seconds to a running demo beats any task list.

## 1. Sync and verify — always, before answering

```bash
git pull --rebase origin main && ./checkpoint.sh quick
```

If `checkpoint.sh` reports a FAIL, that failure **is** the next task. Say so and
stop; do not hand out planned work on top of a broken checkout.

## 2. Work out who is asking

`$ARGUMENTS` may name the person (`A`–`E`, or their name). If it doesn't, infer
from `git config user.name` and recent commits, and say which you assumed.

- **A — Vraj** — orchestrator, prompts, `run-demo.sh`, the audio rig. Owns the demo Mac.
- **B — Sameer** — voiceos-bridge: MCP server, Gmail/Calendar tools, demo-seed. Windows.
- **C — Abhishek** — crew-dock `Sources/**`: characters, bubbles, narration.
- **D — Yaseen** — character art, `crew-dock/Assets/**`, `characters.json`.
- **E — Rukiya** — `docs/**`: rehearsal, resilience, the backup rig.

The full file-ownership map is in `docs/onboarding.md` — use it to check a task
doesn't have someone else's name on it.

## 3. Read the current state

Read `coordination.md` — the **Status** table, **Blockers**, and the
**Checkpoint** section. Read `docs/demo-script.md` for what the run needs.
These are the source of truth; this file is not. Never invent a task that
isn't grounded in something you just read.

## 4. Answer in this shape, and keep it short

```
you are <person>. checkpoint: <PASS | the failing check>.
blocking someone else: <what, or nothing>
next: <one task, one sentence>
why: <the demo consequence if it's skipped>
how: <the exact command or file to start from>
```

**Anything that unblocks another person outranks everything else**, including
work that is more interesting. Two people idle beats one person polishing.

## 5. Rules that keep the three of us in sync

- Prefer a task that is *testable on this machine alone*. Nobody should sit
  waiting for someone else's process to be up.
- Before proposing anything on the demo path, check it isn't already done —
  three people have been pushing all day and `coordination.md` moves fast.
- When the work is finished: run `./checkpoint.sh`, update **your own row** in
  the Status table, `git pull --rebase origin main`, push. Small and often.
- If the task turns out to be someone else's, say so plainly and write it into
  Blockers rather than doing it quietly across a boundary.

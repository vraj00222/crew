# Stage runbook — hold this page, nothing else

One page for 6pm. `demo-script.md` is the detail; this is what you read standing
up. Every claim here has been run, not assumed (break-glass tested by E on a
second Mac, Sun morning).

---

## 1. Pick the rung — before you walk up

| rung | command | needs | note |
|---|---|---|---|
| 4 | `./run-demo.sh voice` | Pro trial + mic rig | the human **speaks** — the only fully voice-controlled rung |
| 3 | `./run-demo.sh live` | seeded mailbox | **proven on the demo Mac** — inbox 18→2 for real |
| 2 | `./run-demo.sh` | logged-in `claude` | real agents, nothing touched |
| 1 | `./run-demo.sh fake` | nothing | panic button — no network, no Claude, full show |

**The event is voice-only — the opening sentence must be SPOKEN, not typed.**
On rung 4, VoiceOS hears it. On rungs 1–3, use the hedge: enable macOS
Dictation (System Settings → Keyboard → Dictation), focus the terminal with the
command pre-typed up to the quote, and dictate the phrase. Ugly beats
disqualified. Decide which *before* 5pm, not on stage.

## 2. Pre-flight — 5:15, not 5:55

```bash
git pull --rebase origin main && ./checkpoint.sh    # must end CHECKPOINT PASS
./run-demo.sh fake                                  # full dress rehearsal, zero spend
./voiceos-bridge/audio-loopback/spike.sh off        # ALWAYS — or the Mac has no mic
```

- [ ] Volume up; dock narrates to `MacBook Pro Speakers` and nowhere else
- [ ] Do Not Disturb on (a banner lands on top of a character)
- [ ] Screen recording running — a good run must survive a bad room
- [ ] Rung 3: **reseed first** (`uv run seed.py`) — the previous live run already
      emptied the inbox, and every spoken number goes false without it
- [ ] Rung 4 only: `spike.sh verify`, `spike.sh split`, `voiceos-setup.sh apply`
- [ ] `./run-demo.sh stop` — walk up from nothing

## 3. The run — one sentence, then hands off

> **"Clean up my inbox and schedule everything."**

Say it, then nobody touches the machine for ~45 seconds. Talk over it:

- characters appear → *"Nobody typed anything. That was one sentence."*
- triage's archive line → *"That's a real inbox — it knows which fourteen don't need me."*
- "Done: inbox down to two real emails" → *"Two left. Both actually need a human."*
- close → *"One sentence in, an inbox and a calendar out."*

**Watch the dock, not the terminal.** Speech trails the log by ~10 seconds — when
the terminal says done, the last character is still mid-sentence. Don't stop
talking, don't touch anything, until Karen finishes out loud.

## 4. When it breaks — never debug on stage

| you see | you do |
|---|---|
| agents slow, erroring, anything weird | `./run-demo.sh stop && ./run-demo.sh fake` — tested: full show, 27s |
| a character goes quiet | keep going — bubbles don't need speech |
| "ran out of time" from any character | that run may never finish (known bug) — `stop && fake`, keep talking |
| dock vanishes / never appears | orchestrator finishes anyway; narrate the terminal, then `stop && fake` |
| everything silent | volume, then `/tmp/crew-dock.log` — `SAY ->` lines are what the room got |

The recovery command is always the same two words: **`stop`, then `fake`**.

## 5. Teardown

```bash
./run-demo.sh stop
./voiceos-bridge/audio-loopback/spike.sh off   # not optional — restores the mic
```

**Backup of last resort:** a recorded clean run lives on E's machine and in the
group chat — if the Mac itself dies, play the recording and narrate over it.

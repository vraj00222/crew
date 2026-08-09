# Stage runbook — hold this page, nothing else

One page for 6pm. `demo-script.md` is the detail; this is what you read standing
up. Every claim here has been run, not assumed (break-glass tested by E on a
second Mac, Sun morning).

---

## 1. Pick the rung — before you walk up

| rung | command | needs | note |
|---|---|---|---|
| 4 | `./run-demo.sh wait` | VoiceOS + mic rig | **the spoken demo.** Comes up and asks for *nothing* — VoiceOS starts the task |
| 4b | `./run-demo.sh voice` | VoiceOS ready + mic rig | agents drive VoiceOS by speaking; the older voice path |
| 3 | `./run-demo.sh live` | seeded mailbox | **proven on the demo Mac** — inbox 18→2 for real |
| 2 | `./run-demo.sh` | logged-in `claude` | real agents, nothing touched |
| 1 | `./run-demo.sh fake` | nothing | panic button — no network, no Claude, full show |

**`wait` is the mode to walk up with if the voice path is on.** Every other mode
fires the task itself — which is exactly what a spoken demo must not do, because
then the sentence is theatre. `wait` prints:

```
READY — nothing has been asked for yet.

  1. press fn+space
  2. say: "clean up my inbox and schedule everything"

waiting for VoiceOS to call run_crew_task (ctrl-C to give up)...
```

…and blocks, for up to 10 minutes, until a task actually appears. When it does it
prints `VoiceOS started task_1 — the crew is live` and the run proceeds normally.
**That line is the proof:** the bridge log only shows a tool was *called*; this
shows a task *exists because of it*. If it never prints, nothing reached the
orchestrator — drop to rung 2 or 1 rather than debugging.

**The event is voice-only — the opening sentence must be SPOKEN, not typed.**
On rung 4, VoiceOS hears it. On rungs 1–3, use the hedge: enable macOS
Dictation (System Settings → Keyboard → Dictation), focus the terminal with the
command pre-typed up to the quote, and dictate the phrase. Ugly beats
disqualified. Decide which *before* 5pm, not on stage.
**The hedge is tested, not assumed** (E's Mac): Dictation types a full spoken
sentence into a terminal accurately, punctuation and all. Two cautions: dictate
the exact demo phrase once at pre-flight to confirm "schedule" survives on the
demo Mac's ears, and don't leave Dictation armed in a terminal between tests —
anything you say that ends in Enter runs.

## 2. Pre-flight — 5:15, not 5:55

```bash
git pull --rebase origin main && ./crew-dock/build.sh   # pull THEN rebuild, in that order
./checkpoint.sh                                     # must end CHECKPOINT PASS
./run-demo.sh fake                                  # full dress rehearsal, zero spend
./voiceos-bridge/audio-loopback/spike.sh off        # ALWAYS — or the Mac has no mic
```

**Why the explicit rebuild:** the dock is the one compiled thing here, and a pull
while it is running leaves you watching the old app. `run-demo.sh` rebuilds for
you, but launching the binary directly — which is what you do to read its
stderr — does not. This has caught us four times in one day, always as a feature
that "isn't working" and is simply not in the build.

- [ ] Volume up; dock narrates to `MacBook Pro Speakers` and nowhere else
- [ ] Do Not Disturb on (a banner lands on top of a character)
- [ ] Screen recording running — a good run must survive a bad room
- [ ] Rung 3: **reseed first** (`uv run seed.py`) — the previous live run already
      emptied the inbox, and every spoken number goes false without it
- [ ] Rung 4 only: `spike.sh verify`, `spike.sh split`, `voiceos-setup.sh apply`
- [ ] Rung 4 only: say **"Is Crew ready?"** once now — if the card doesn't say
      Ready at 5:15 it will not say Ready at 6:00, and beat 1 is the opener
- [ ] `./run-demo.sh stop` — walk up from nothing

## 3. The opening beat — prove it is really connected (rung 4 only)

**Do this before any agent runs. It is the nothing-up-my-sleeve moment**, and it
costs ~20 seconds. Say each phrase to VoiceOS:

| you say | the room sees | you say over it |
|---|---|---|
| **"Is Crew ready?"** | a card: **Ready**, Node version, our script path, MCP version | *"That's our server, on this laptop. Nothing pre-recorded."* |
| **"What tools does Crew have?"** | all 8 `crew_*` tools, discovered live | *"It found those itself — we didn't hand it a list."* |

Then start the crew. Three ways, and **know which one you are using before you
walk up**:

- **Press ⌃⌥C** — no VoiceOS, no helper, no terminal in the shot. The crew walks
  down from the top of the screen and starts. **Tested by a real press on a
  second Mac**; a synthesised keystroke does *not* work, so this is a human
  beat. Two conditions, learned the hard way:
  **(a)** Accessibility must be granted to the app that *launches* the dock
  (Terminal, VS Code — whichever), and **(b)** restart that app after granting,
  then press once to confirm — `hotkey ready` in the log is not proof on its own.
- **⌃⌥L** is the *long* five-agent run that shows agents handing findings to each
  other. **Do not put it on stage** unless you have rehearsed it: A's call is
  that ⌃⌥C is the 45-second run that has been said out loud dozens of times.
  Know which key you are pressing — they are one letter apart.

- **`run-demo.sh wait` + the natural sentence** — the real beat, if B's helper
  action is live.
- **"Invoke run_crew_task with instructions clean up my inbox and schedule
  everything"** — the fallback that works today. It names the tool out loud and
  the approval card shows **raw JSON**, not a tidy form. Say what it is:
  *"That's the permission prompt — it will not touch my mail without me."* Then
  approve, and the dock comes alive.

Mid-run, if you want one more beat: **"What is the crew doing?"** — the crew
answers in a spoken sentence, which is the loop staying alive rather than a
one-shot command.

**The seam to know about:** approving *Invoke tool* is a click. It can be removed
in the VoiceOS app — Invoke tool → **Don't ask** — which makes the loop fully
autonomous. Decide before 5pm whether you want the click (honest, shows the
guardrail) or not (smoother). Either is defensible; deciding on stage is not.

## 4. The run — one sentence, then hands off

> **"Clean up my inbox and schedule everything."**

Say it, then nobody touches the machine for ~45 seconds. Talk over it:

- characters appear → *"Nobody typed anything. That was one sentence."*
- triage's archive line → *"That's a real inbox — it knows which fourteen don't need me."*
- "Done: inbox down to two real emails" → *"Two left. Both actually need a human."*
- close → *"One sentence in, an inbox and a calendar out."*

**Watch the dock, not the terminal.** Speech trails the log by ~10 seconds — when
the terminal says done, the last character is still mid-sentence. Don't stop
talking, don't touch anything, until the last voice finishes.

**The show ends itself — let it.** About 7 seconds after everyone has signed off,
the crew walks back off the top of the screen and **one character is left alone
with the closing summary** (whoever finished last, not always recap). Measured at
8s from the final `done`. That is your closing image and the line the room should
be reading while you land the last sentence — so stop talking *into* it rather
than over it, and don't hit `stop` until it has played.

**Rehearsing twice in a row is safe.** After the curtain, characters reset and a
second trigger gets a clean entrance — they walk down again rather than sliding
in from wherever they stood. Verified end to end. (If you re-trigger *before* the
curtain has played, the crew is still on screen and there is no entrance to see —
that reads as a dead hotkey and isn't one.)

## 5. When it breaks — never debug on stage

| you see | you do |
|---|---|
| agents slow, erroring, anything weird | `./run-demo.sh stop && ./run-demo.sh fake` — tested: full show, 27s |
| a character goes quiet | keep going — bubbles don't need speech |
| "ran out of time" from any character | one agent timed out; the rest carry on and the run still ends (fixed and re-verified) |
| `READY` never becomes `VoiceOS started task_…` | nothing reached the orchestrator — ctrl-C, drop to rung 2 or 1, keep talking |
| dock vanishes / never appears | orchestrator finishes anyway; narrate the terminal, then `stop && fake` |
| everything silent | volume, then `/tmp/crew-dock.log` — `SAY ->` lines are what the room got |
| crew never walks off at the end | you are on a stale build — `./crew-dock/build.sh`. Cosmetic; keep going |
| characters don't walk down on a re-press | they never left; the curtain hadn't played. Not a broken hotkey |

The recovery command is always the same two words: **`stop`, then `fake`**.

## 6. Teardown

```bash
./run-demo.sh stop
./voiceos-bridge/audio-loopback/spike.sh off   # not optional — restores the mic
```

**Backup of last resort:** `crew-demo-recording.m4v` — a clean 95-second run with
the Piper voices, on E's machine and in the group chat. If the Mac itself dies,
play it and narrate over it. (Ignore `crew-clean-run-OLD-voices.m4v`; that one
predates the voices and sounds like a screen reader.)

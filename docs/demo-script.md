# The demo, exactly as it runs

Sunday 6pm, Frontier Tower SF. One rehearsed run. **~2 minutes on stage.**

The whole show is one command. Everything below is either preparation for it or
a way to drop down a rung if something breaks.

---

## The four rungs

Every rung is a complete show. They differ only in how much is real, and each
one is a known-good prompt file — **switching is a different word on the command
line, never an edit under pressure.**

| | command | what is real | needs |
|---|---|---|---|
| 4 | `./run-demo.sh voice` | everything — agents speak, VoiceOS acts | Pro trial, mic rig |
| 3 | `./run-demo.sh live` | the mailbox really changes | Google account + OAuth |
| 2 | `./run-demo.sh` | real agents, real reasoning, nothing touched | `claude` CLI only |
| 1 | `./run-demo.sh fake` | nothing — canned narration | **nothing at all** |

**Rung 2 is the plan of record until the Pro trial lands.** It is the highest
rung with no external dependency: three real headless agents reasoning about a
real inbox, on screen, talking. Rung 1 is the panic button — no Claude spend, no
network, and it still puts on the entire show.

Decide the rung *before* you walk up, not on stage.

---

## Pre-flight (do this at 5:15, not 5:55)

```bash
git pull --rebase origin main
./orchestrator/test.sh                              # must print PASS
./voiceos-bridge/audio-loopback/spike.sh verify     # audio reaches the virtual mic
./voiceos-bridge/audio-loopback/spike.sh split      # narration and commands stay apart
./crew-dock/voices.sh check                         # are the good voices installed?
./run-demo.sh fake                                  # full dress rehearsal, zero spend
./voiceos-bridge/audio-loopback/spike.sh off        # ALWAYS — or the Mac has no mic
```

Then the things no script can check:

- [ ] **Speaker volume up.** The dock narrates to `MacBook Pro Speakers`. The
      room hears the crew from there and nowhere else.
- [ ] **Enhanced voices downloaded.** System Settings → Accessibility → Spoken
      Content → System Voice → Manage Voices → Moira, Daniel, Karen. This is the
      difference between "a crew" and "a 2005 screen reader". No code changes.
- [ ] **Notifications off.** `Do Not Disturb` — the dock windows are `.floating`
      and a banner lands on top of a character.
- [ ] **Screen recording on**, so a good run survives a bad room.
- [ ] `./run-demo.sh stop` — start from nothing.

For rung 3 or 4 additionally:

- [ ] `cd voiceos-bridge/demo-seed && uv run seed.py` — 18 emails, 2 free slots.
- [ ] `node voiceos-bridge/mcp-server/test-demo-flow.js` — must print PASS.
- [ ] Google account added in **System Settings → Internet Accounts** with
      Calendars ticked, so Apple Calendar and Google Calendar are the same
      calendar. Verify: Calendar.app shows "Design review — onboarding" at 11:00
      tomorrow.
- [ ] For rung 4 only: `spike.sh demo`, `voiceos-setup.sh apply`,
      `muteWhenDictating: false`, `agentVoiceEnabled: false`.

---

## The run

**One human sentence. That is the entire human contribution.**

> **"Clean up my inbox and schedule everything."**

Say it once, into VoiceOS (rung 4) or type the command (rungs 1–3). From that
moment nobody touches the machine.

```
you speak once
   -> VoiceOS transcribes
   -> calls run_crew_task on the MCP server
   -> POST :4001/start-task
   -> three headless agents, triage ‖ scheduler, then recap
   -> every line POSTs to :4002
   -> a character walks up, says it out loud, and the bubble follows
```

### The beat sheet

Ten lines, ~4 seconds apart, **~45 seconds** end to end. Triage (Irish) and
Scheduler (British) overlap; Recap (Australian) closes alone.

| # | who | roughly |
|---|---|---|
| 1 | triage | Scanning the inbox for newsletters and noise. |
| 2 | scheduler | Two o'clock tomorrow is open — David Chen, that's yours. |
| 3 | triage | **Archiving fourteen — six newsletters, eight receipts and alerts.** |
| 4 | scheduler | An hour blocked, clear of the standup and the design review. |
| 5 | triage | Two meeting requests going over to be booked. |
| 6 | scheduler | Priya Nair takes ten AM the following day, thirty minutes. |
| 7 | triage | **Done: inbox down to two real emails.** |
| 8 | scheduler | **Done: both booked, calendar holds together.** |
| 9 | recap | That's the lot. Your morning is yours again. |
| 10 | recap | **Done: inbox cleared, meetings booked, nothing left for you.** |

The exact words vary — they are three real agents, not a script. **The numbers
do not vary**, because they are pinned in the prompts and true of the seeded
mailbox: 18 in, 14 archived, 2 booked, **2 left**.

Line 3 and line 7 are the demo. If you only get two lines out, get those.

### What to say over it

- As the characters appear: *"Nobody typed anything. That was one sentence."*
- On line 3: *"That's a real inbox — eighteen emails, and it knows which
  fourteen don't need me."*
- On line 7: *"Two left. Both actually need a human."*
- At the end: *"One sentence in, an inbox and a calendar out. The only thing
  between the agents and the mailbox was a speaker and a microphone."*

---

## When it breaks

**The rule: never debug on stage.** Drop a rung and keep talking.

| symptom | do this |
|---|---|
| agents slow or erroring | `./run-demo.sh stop && ./run-demo.sh fake` — same show, no Claude |
| VoiceOS mishears | you type the phrase instead; rungs 1–3 do not need it |
| a character is silent | keep going — bubbles are independent of speech, and a mistyped voice name speaks in the default voice rather than going quiet |
| **all** characters silent | `CREW_MUTE=1` was set, or check `/tmp/crew-dock.log` |
| dock never appears | orchestrator runs regardless; its POSTs fail silently by design |
| an agent hangs | 180s timeout kills it and the character says "ran out of time" |
| a character freezes | it shouldn't any more — but it is cosmetic, keep going |

**This table has been tested, not assumed** (E, Sun morning, second Mac, fake
pipeline): `stop && fake` recovers cleanly from a mid-run interrupt (full second
show, 10/10 spoken); a dead dock doesn't stop the orchestrator; a dead
orchestrator doesn't kill the dock; a bad voice name speaks anyway. The
agent-hang row earned its keep: testing found a hung `claude` with a subprocess
holding its pipe wedged the run forever after the character spoke. A fixed it
(`e87f5c0` — process-group kill + finish on `exit`), and the same repro now
completes with recap running and zero orphans. The row above is true again as
written. Also: a `CREW_MUTE=1` run makes `run-demo.sh` sit ~60s at the end
waiting for speech that never comes — harmless, just slow.

Two commands worth having in muscle memory:

```bash
./run-demo.sh stop        # everything down
./run-demo.sh fake        # everything up, guaranteed
```

**The orchestrator log is not evidence.** It reports what it *sent*. What the
room got is in `/tmp/crew-dock.log` (`DOCK <-` received, `SAY ->` spoken), and
`run-demo.sh` prints that at the end of every run.

---

## Teardown

```bash
./run-demo.sh stop
./voiceos-bridge/audio-loopback/spike.sh off    # or the Mac has no microphone
```

`spike.sh off` is not optional and the failure is not obvious — the Mac simply
has no working mic until someone runs it.

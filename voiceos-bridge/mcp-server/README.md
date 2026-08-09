# voiceos-bridge / mcp-server

The **human → VoiceOS → orchestrator** hop. VoiceOS hears a spoken command, resolves it
to `run_crew_task`, and this server POSTs it to A's orchestrator on `:4001`.

Node stdlib only — no `npm install`, no build step, nothing to break at 5pm.
Requires Node 18+ (uses global `fetch`). Verified on Node 24, Windows 11.

## Tools exposed

**Trigger** — how a spoken phrase starts the swarm:

| tool | args | does |
|---|---|---|
| `run_crew_task` | `instructions: string` | `POST :4001/start-task` → wakes the swarm |
| `crew_task_status` | `taskId?: string` | `GET :4001/status/:id` → one spoken sentence about the run |

`run_crew_task` passes the transcript through **verbatim** — no normalising. A's router is
keyword-based (`inbox|email|mail` → triage, `schedul|calendar|meeting|book` → scheduler) and
falls back to spawning both, so a garbled transcript still puts characters on stage.

### `crew_task_status` — the half that makes it a loop

Nobody says "task underscore one" out loud, so **`taskId` is optional**: the bridge
remembers the task it started and reports on that one. `run_crew_task` sets it in memory,
and if VoiceOS respawns the server in between, `crew-bridge.log` is read back for the last
started task — the follow-up question works either way.

VoiceOS reads a tool's reply back **verbatim**, so the reply is a sentence, not a struct.
`status-speech.js` is that translation and nothing else; it has no I/O so every branch is
testable with `node test-status-speech.js`.

```
Triage and Scheduler are both waking up. Recap hasn't started yet.
Triage is archiving six newsletters and Scheduler is booking two PM with David Chen. Recap hasn't started yet.
Scheduler is booking two PM with David Chen. Triage is already finished and Recap hasn't started yet.
The crew is finished. Inbox cleared, two meetings booked.
```

Three things it gets right that are easy to get wrong:

- **Only `done` means finished** (A's clarification to the contract). An unfamiliar state is
  reported as still running, never as the end of the run.
- **A's final `Done:` line is POSTed twice**, once as `working` and then as `done`. In that
  window the agent has plainly said its last word, so the text wins over the state —
  otherwise the crew says "Recap reports inbox cleared" about an agent that has gone home.
- **Recap's sign-off is the summary**, by design, so it becomes the closing sentence. If
  recap never got a line out, everyone else's last line is read instead.

**Work** — how the agents actually change the mailbox (names frozen in `coordination.md`):

| tool | args | does |
|---|---|---|
| `crew_gmail_list_inbox` | `query?`, `limit?` | what's in the inbox |
| `crew_gmail_archive` | `query?` \| `ids?` | drops the INBOX label — nothing is deleted |
| `crew_gmail_label` | `label`, `query?` \| `ids?` | applies a label, creating it if new |
| `crew_calendar_find_slot` | `durationMin?`, `dayOffset?`, `afterISO?` | first free gap |
| `crew_calendar_book` | `summary`, `startISO`, `durationMin?`, `attendee?` | books it |
| `crew_calendar_list` | `dayOffset?` | a day's events |

Queries are **plain English** (`"newsletters"`, `"meeting requests"`), not Gmail search
syntax — the agents speak, they don't compose queries. A real Gmail query still passes
through if one shows up.

`crew_calendar_book` never sets `attendees`, so **Google never emails a real person**. The
requester goes in the description instead.

## Two backends, one interface

```
CREW_BACKEND=fake     # default — in-memory, seeded from demo-seed/fixtures.json
CREW_BACKEND=google   # the real demo account, via demo-seed's token.json
```

`fake` needs no account, no credentials and no network, so the inbox half of the demo works
on any machine — it's a genuine panic button, not just a test fixture. State persists to
`.crew-mailbox.json` because VoiceOS respawns the server between calls; in memory alone,
an archive would silently undo itself between two agent steps.

`google` talks raw REST over `fetch` — still no `npm install` — and reuses the exact
`token.json` that `demo-seed/seed.py` writes, so authorising once covers both.

## Register with the agents (`direct` mode)

In `direct` mode the agents call these tools themselves, which means each headless
`claude -p` session needs **its own** MCP connection to this server. Claude Code does not
find it by magic — without `--mcp-config` there is no crew tool in the session at all, and
`execution-direct.md` tells the agent to narrate and carry on, so **a run with no tools
looks exactly like a healthy one.**

```bash
node mcp-config.js            # the --mcp-config JSON, absolute paths
node mcp-config.js --tools    # the --allowedTools list
node test-direct-contract.js  # every tool the prompt names is really served
```

It prints a JSON *string* rather than shipping a `.mcp.json` because the server path inside
the config resolves against the spawning process's cwd, so a committed relative path is
correct from exactly one directory.

**Three naming schemes, all different, all live in this repo:**

| | example | who uses it |
|---|---|---|
| the tool | `crew_gmail_archive` | the tool definition, and `execution-direct.md` |
| Claude Code | `mcp__crew__crew_gmail_archive` | `--allowedTools` |
| VoiceOS | `custom_mcp_crew_crew_gmail_archive` | VoiceOS's own logs |

## Register with VoiceOS

```
voiceos add mcp
```

- **command:** `node`
- **args:** `["C:\\Users\\nagar\\Downloads\\CrewOS\\voiceos-bridge\\mcp-server\\server.js"]`

Use an **absolute path** — VoiceOS's working directory is not this folder.
On A's Mac the path is wherever the repo is cloned; the server itself is platform-agnostic.

## Test it

```powershell
.\test.ps1                  # stub orchestrator + full stdio handshake, self-contained
.\test.ps1 -Real            # against A's orchestrator (start it yourself first)
.\test.ps1 -Phrase "sort my email out"     # check routing on a different phrase
```

```bash
node server.js --selftest      # protocol only, no transport, no orchestrator needed
node test-status-speech.js     # what the crew says out loud — no network at all
node test-stdio.js             # real subprocess + pipes (this is the honest one)
node test-demo-flow.js         # the whole demo, asserted against the mailbox
CREW_BACKEND=google node test-demo-flow.js   # same, against the real account
```

`stub-orchestrator.js` walks a whole scripted run — one phase per `/status` call, from
waking up to finished — so the follow-up loop is testable end to end on a Windows box with
no Mac, no Claude and no account. `REQUIRE_DONE=1 node test-stdio.js` against the stub
insists the loop actually reaches "the crew is finished"; against a real orchestrator it
won't inside one test, because A paces narration at `LINE_MS`.

`test-demo-flow.js` is the one that matters most. It runs the actual demo through the tools
and asserts that **the numbers the characters say out loud are true of the mailbox**: six
newsletters archived, 2pm booked and genuinely free beforehand, exactly two emails left. It
has already caught two bugs that would have shown on stage — a newsletter matcher that also
caught Calendly's "your *weekly* availability" (7, not 6), and a 1pm gap that made the
scheduler book 1pm while the character said two.

`--selftest` calls the handler in-process, so it **cannot** catch line-buffering or
stdout-pollution bugs. `test-stdio.js` spawns the server for real and deliberately sends
two messages glued into one write and one message split across two writes, because that is
what a real client does. Prefer it.

Exit codes: `0` PASS · `2` transport fine but nothing on `:4001` · `1` real failure.

## Env

| var | default | |
|---|---|---|
| `ORCH_URL` | `http://localhost:4001` | A's orchestrator |
| `CREW_LOG` | `./crew-bridge.log` | append-only JSONL of every call |
| `TIMEOUT_MS` | `8000` | orchestrator fetch cap |

## The log is the evidence

Every `run_crew_task` is written to `crew-bridge.log` **before** the orchestrator is called,
so if `:4001` is down you still have proof of exactly what VoiceOS heard:

```
{"ts":"...","event":"run_crew_task","instructions":"clean up my inbox and schedule everything"}
{"ts":"...","event":"orchestrator_ok","taskId":"task_1","status":"started"}
```

That file is the answer to "did VoiceOS transcribe it right?". Tail it while speaking.

## Gotchas paid for already

- **stdout is the protocol channel.** Never `console.log` in `server.js` — it corrupts the
  stream and the client drops the server with no error. All logging goes to stderr.
  `test-stdio.js` fails the build if anything non-JSON appears on stdout.
- **Notifications get no reply.** `notifications/initialized` has no `id`; answering it is a
  protocol violation. The test asserts exactly 3 responses to 4 messages.
- Failures come back as readable sentences (`isError: true`), not stack traces — VoiceOS
  reads the text out loud, so it should say *which hop* broke.
- **VoiceOS renames every custom MCP tool** to `custom_mcp_<server>_<tool>`, so
  `crew_gmail_archive` is `custom_mcp_crew_crew_gmail_archive` from inside VoiceOS. Nothing
  in this repo hardcodes a VoiceOS-side name, and nothing should — but that is the name to
  grep for in VoiceOS's own logs when a spoken command appears to do nothing.

## Tool annotations, and why they are not flattering

Every tool declares MCP `annotations`. VoiceOS confirms anything that "sends, books, or
changes something", and its own tool declarations carry a `requiresConfirmation` boolean —
**if it derives that from these hints, the three read-only tools go through without a human
click**, which is the difference between an autonomous loop and one that stops dead with
nobody at the keyboard. That makes it tempting to declare everything harmless. They are
declared exactly as the tools behave instead:

| tool | `readOnlyHint` | `destructiveHint` | why |
|---|---|---|---|
| `crew_task_status`, `crew_gmail_list_inbox`, `crew_calendar_find_slot`, `crew_calendar_list` | `true` | — | pure reads |
| `crew_gmail_archive`, `crew_gmail_label` | `false` | `false` | writes, but archiving only drops the INBOX label — reversible, nothing deleted |
| `crew_calendar_book` | `false` | `false` | adds an event; never overwrites or cancels one. Not idempotent — booking twice books twice |
| `run_crew_task` | `false` | `false` | starts work that changes mail and calendar |

**Whether VoiceOS reads any of this is still unverified** — it needs a live Pro trial:
register, call `tools/list`, and see whether the read-only tools stop asking.

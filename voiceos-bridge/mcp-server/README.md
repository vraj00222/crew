# voiceos-bridge / mcp-server

The **human → VoiceOS → orchestrator** hop. VoiceOS hears a spoken command, resolves it
to `run_crew_task`, and this server POSTs it to A's orchestrator on `:4001`.

Node stdlib only — no `npm install`, no build step, nothing to break at 5pm.
Requires Node 18+ (uses global `fetch`). Verified on Node 24, Windows 11.

## Tools exposed

| tool | args | does |
|---|---|---|
| `run_crew_task` | `instructions: string` | `POST :4001/start-task` → wakes the swarm |
| `crew_task_status` | `taskId: string` | `GET :4001/status/:id` → what each agent last did |

`run_crew_task` passes the transcript through **verbatim** — no normalising. A's router is
keyword-based (`inbox|email|mail` → triage, `schedul|calendar|meeting|book` → scheduler) and
falls back to spawning both, so a garbled transcript still puts characters on stage.

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
node server.js --selftest   # protocol only, no transport, no orchestrator needed
node test-stdio.js          # real subprocess + pipes (this is the honest one)
```

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

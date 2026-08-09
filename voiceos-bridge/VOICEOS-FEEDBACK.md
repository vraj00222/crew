# VoiceOS feedback — from building a custom MCP integration against it

Written while building CrewOS at Hack with VoiceOS (9 Aug 2026). Everything below
comes from installing VoiceOS on **two machines — macOS and Windows 11** — reading
its shipped config and bundle, and building an MCP server against it. Findings are
what we observed, with what we did about it. Nothing here is a guess about intent.

**Short version of the most useful three:** the Windows install ships no CLI but
the docs say it does; custom MCP tools are silently renamed, which breaks any
prompt that hardcodes a tool name; and confirmation-on-every-action is the single
biggest limit on autonomous agent use — with a concrete suggestion for it below.

---

## 1. `voiceos add mcp` does not exist on Windows, and the docs say it does

The Windows install is a single `VoiceOS.exe` (Electron) and ships **no
command-line interface at all**. The `voiceos add mcp` command in the getting-started
material is macOS-only or docs-only. Registration on Windows is in-app: tray → window
→ Settings → MCP/custom servers, which writes `customMcpServers` in
`%APPDATA%\VoiceOS\config.json`.

**Why it cost us time:** we scripted registration against the documented CLI before
discovering it wasn't there, then had to write a config auditor instead.

**Suggestion:** either ship the CLI on Windows or mark the command macOS-only in the
docs. A one-line platform note would have saved us an hour.

**Related, and a real footgun:** hand-editing `config.json` while the app is running
silently loses the edit — it's an electron-store and the app rewrites the whole file
on its own schedule. Worth a warning in the docs, since editing that file is the
obvious workaround when there's no CLI.

## 2. Custom MCP tools are renamed, and nothing tells you

VoiceOS registers its own integrations as pseudo-MCP servers, and the bundle
contains `NAME_PREFIX = "custom_mcp_voiceosapplemail_"`, alongside
`custom_mcp_voiceoschatgpt_send_instruction`, `custom_mcp_voiceosspotify_`,
`custom_mcp_voiceosnotes_`. So the scheme is:

```
custom_mcp_<servername>_<toolname>
```

Our `crew_gmail_archive` is not callable as `crew_gmail_archive` from inside
VoiceOS — it becomes `custom_mcp_crew_crew_gmail_archive`.

**Why this matters more than it looks:** any prompt, allowlist, or log-grep that
hardcodes the bare tool name is silently wrong, and the failure mode is "the user
spoke and nothing happened" — no error, nothing to search for. We only found it by
reading the bundle.

**Suggestion:** surface the effective (prefixed) tool name in the MCP settings UI
next to each registered tool. One line of text turns a silent failure into an
obvious one. Documenting the prefix scheme would be the cheaper half of that.

## 3. Per-tool confirmation is the main limit on autonomous agents — and MCP already has the vocabulary for it

VoiceOS's tool declarations carry a `requiresConfirmation` boolean, there's an
`AGENT_CONFIRM_REQUIRED` code path, and your site states that anything which sends,
books, or changes something stops and shows the user first. There is no *global* bypass
in settings, which we read as deliberate, and we think it's the right default.

There is, however, a top-level config key named
**`codingAgentDangerouslyBypassPermissions`** (`false` on our install). We haven't worked
out what it governs — the name suggests the coding-agent feature rather than custom MCP
tools — but it means a bypass exists for at least one path. **If something like it is
intended to be reachable for MCP tools, it isn't discoverable**: it's in neither the UI
nor the docs we could find, and the only reason we know it exists is that we read the
config. Either document it or surface it in settings; a `Dangerously` prefix in a JSON
file is a thing people will find and flip without knowing what it does.

The problem it creates for agent-shaped products: our crew runs unattended for ~45
seconds and performs a dozen mailbox actions. A confirmation on each one means a
human at the keyboard, which is the exact thing the product is supposed to remove.

**The suggestion, and it costs you nothing to adopt:** the MCP spec already has
[tool annotations](https://modelcontextprotocol.io/) — `readOnlyHint`,
`destructiveHint`, `idempotentHint`. **Derive `requiresConfirmation` from them.**
A tool that declares `readOnlyHint: true` cannot change anything by definition, so
confirming it buys the user nothing and costs the interaction its flow. We annotated
all eight of our tools honestly on that bet:

| our tool | `readOnlyHint` | `destructiveHint` |
|---|---|---|
| `crew_task_status`, `crew_gmail_list_inbox`, `crew_calendar_find_slot`, `crew_calendar_list` | `true` | — |
| `crew_gmail_archive`, `crew_gmail_label` | `false` | `false` — only drops a label, nothing deleted |
| `crew_calendar_book` | `false` | `false` — adds an event, never overwrites |
| `run_crew_task` | `false` | `false` |

A middle tier would be even better than a binary: confirm destructive things, allow
reversible writes, never confirm reads. Archiving mail is reversible; deleting it
isn't; and today they're treated identically.

**What we could not test, and would like to:** whether VoiceOS currently reads those
annotations at all. That check needs a live Pro session and `tools/list`. If it
already does, say so in the docs — it's a strong reason to build on VoiceOS rather
than around it.

**Genuinely good discovery in the same area:** confirmations appear to be answerable
**by voice** — the bundle has `emitVoiceConfirmation`, `classifyAgentConfirmationIntent`,
and the log line `[AgentInputService] Reply is unrelated to pending confirmation`.
That's a better answer than a trust setting, because it keeps the human in the loop
without keeping them at the keyboard. **It is also not documented anywhere we could
find, and it is the single most important thing about VoiceOS for anyone building an
agent on it.** Put it in the getting-started guide.

## 4. Two default settings silently break any audio-loopback rig

Both of these are sensible defaults for a human user and fatal for a machine-driven
one, and neither announces itself:

- **`muteWhenDictating: true`** — VoiceOS ducks system audio while listening. If your
  agent speaks *to* VoiceOS through a virtual audio device, VoiceOS mutes the very
  thing it is supposed to hear. The rig fails with no error and looks like a
  transcription problem.
- **`agentVoiceEnabled: true`** — VoiceOS talks back. In a loopback rig every sound
  out goes into the mic, so VoiceOS hears its own replies and re-triggers itself.

**Suggestion:** a "developer / loopback" toggle that sets both, or a warning when the
selected input device is a known virtual one (BlackHole, VB-CABLE). We lost real time
to the first one before finding it in the config.

## 5. `fn` cannot be synthesized in software, which shapes what can be built

The default trigger is the `fn` key, and on macOS `fn` is handled below the layer
`CGEvent` and AppleScript can post — **no script can press it.** The trigger is
rebindable to a normal chord (there's already a `control-left + option-left` chord
registered), and that works, but it took reading `keyboardShortcuts` in the config to
find out.

**Suggestion:** one line in the docs — "the `fn` trigger cannot be invoked
programmatically; rebind to a chord if you need to script it." Anyone building a
hands-free or automated flow hits this.

## 6. The config schema moved, and anything scripted against the old shape breaks silently

Between our morning inspection and the afternoon, `muteWhenDictating` and
`agentVoiceEnabled` moved from the top level into `settings`, and `onboardingCompleted`
into `onboarding`. Our setup script happened to read the nested shape and was fine; one
written against the earlier shape would have written a top-level key the app ignores, and
the loopback rig would then fail with **no error and nothing to search for.**

**Suggestion:** if `config.json` is something integrators are expected to read — and with
no CLI on Windows it effectively is — give it a `schemaVersion`. `appliedMigrations` is
already in the file, so the concept exists internally; exposing a version would let anyone
scripting against it fail loudly instead of silently.

## 7. Onboarding terminates at the paywall with no way past it

Until we redeemed the event's free month, onboarding stopped at "Start your 7-day free
trial" ($143.88/yr), `onboardingCompleted` stayed `false`, and there was no skip. Once
redeemed it completed straight away and Gmail connected without any trouble — so this is
about the *evaluation* path, not the product. Two consequences worth weighing:

- A developer evaluating the MCP integration can't see `customMcpServers` work at all
  before paying — the integration surface is behind the same gate as the product.
- At **this event**, where every participant is given a free month, several teams
  (including ours) spent the morning blocked on redeeming it rather than building
  against the thing you want feedback on.

**Suggestion:** a developer mode that unlocks MCP registration and `tools/list`
without the full subscription. The people who register a custom MCP server are the
people most likely to keep using and recommending the product.

## 8. Smaller things

- **`nativeActionToggles` doesn't reflect connected integrations.** After connecting
  Gmail, `connectedIntegrations` became `["gmail"]` but the toggle list was unchanged
  (editText, insertText, openApp, setVolume, controlPlayback, reminders) — no email
  action appears. We assume the toggles cover only *native OS* actions and integrations
  are dispatched elsewhere, but from outside it reads as "Gmail is connected and yet
  there is no email action", which is confusing when you're deciding what to build
  natively vs. via MCP. A one-line label on that section would fix it.
- The `dictations` table in `voiceos.db` is an excellent debugging hook — being able
  to confirm exactly what was transcribed settles "did it mishear me?" instantly.
  Mention it in developer docs; we found it by looking.
- Onboarding shows a step number with no total (we saw step 15, then 16 of
  `onboardingStepVersion` 24). A count would tell a user whether they're nearly done.

---

## What we built on it, for context

**CrewOS** — you say one sentence out loud, and a crew of agents works your inbox
and calendar while three characters narrate themselves on your dock. VoiceOS is the
ear: it hears the sentence, calls `run_crew_task` on our MCP server, and can be asked
"what's the crew doing?" mid-run and get a spoken answer back. Eight MCP tools, Node
stdlib only.

The parts of VoiceOS that made it possible: `customMcpServers` is a genuinely open
extension point, the config is plain readable JSON rather than an opaque store, and
voice-answerable confirmations mean the loop can stay autonomous without a trust
setting. Our top three asks are (1) surface prefixed tool names in the UI, (2) derive
`requiresConfirmation` from MCP annotations, and (3) document the voice-answerable
confirmation path — it's your best agent feature and it isn't written down.

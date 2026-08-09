# voiceos-bridge / demo-seed

Puts a fixed, deterministic inbox and calendar into a **throwaway** Google account, so the
demo runs against the same 18 emails every rehearsal.

```powershell
uv run seed.py --dry-run     # no credentials, no network — verifies everything
uv run seed.py               # wipe + reseed (asks which account first)
uv run seed.py --wipe        # remove seeded items, leave the account clean
```

`uv` handles the dependencies via PEP 723 inline metadata — there is no venv to activate
and no `pip install` step.

## The fixture is a contract, not decoration

`fixtures.json` is pinned by `orchestrator/prompts/execution-*.md`, which hardcodes the seeded
inbox into the agents' prompt. **Change a sender or subject in one and you must change the
other**, or triage narrates an inbox the audience cannot see.

The arithmetic is load-bearing too:

| | count | what happens on stage |
|---|---|---|
| newsletters | 6 | archived — "Archiving six newsletters." |
| noise + travel | 8 | archived |
| meeting requests | 2 | David Chen → 2pm tomorrow, Priya → 30 min |
| needs a human reply | 2 | **left in the inbox** — "inbox down to two real emails" |
| **total** | **18** | |

`--dry-run` asserts these counts against `meta` in the fixture and exits non-zero if they
drift. Two calendar gaps are deliberately left free — tomorrow 14:00 and the day after at
10:00. Fill either and the demo's best line stops being true.

## First-time setup (~5 min, once)

`credentials.json` is not in the repo and must never be. To make one:

1. Google Cloud Console → new project.
2. Enable **Gmail API** and **Google Calendar API**.
3. OAuth consent screen → **External** → add the demo account as a test user.
4. Credentials → OAuth client ID → **Desktop app** → download JSON.
5. Save it as `credentials.json` next to `seed.py`.

First real run opens a browser to authorise, then caches `token.json`. Both files are
gitignored.

## Safety

- **Inserts, does not send.** `users.messages.insert` places mail directly into the mailbox.
  The fixture senders are fake `.example.com` addresses — sending would bounce, or worse,
  reach a real person.
- **Everything is marked.** Emails get the `crew-demo-seed` label; events get
  `extendedProperties.private.crewDemoSeed=1`. `--wipe` only ever touches those, so it
  cannot eat mail the seeder did not create.
- **It shows you the account before writing.** `batchDelete` is permanent, and the account
  is whatever `token.json` holds. The script prints the address and message count and waits
  for a `y`; it warns loudly if the mailbox has >500 messages, because a fresh demo account
  does not. `--yes` skips the prompt once you trust it. Run it against a throwaway account,
  never a real one.
- Reseeding is idempotent: a bare run wipes then seeds, so it always converges to exactly
  the fixture.

## Status

Written and verified on Windows/Node-free Python via `uv`. `--dry-run` passes end to end
(18 messages + 7 events built, assertions hold), and the missing-credentials path prints
instructions rather than a traceback. **The authenticated paths — OAuth, insert, wipe — are
untested**, because no demo account existed when this was written. Budget 10 minutes the
first time you point it at a real account.

# claude-todo

Persistent project-level TODO tracking for Claude Code.

Claude intelligently manages the TODO list — you don't write descriptions or pick item numbers. Claude scans conversation context, writes rich self-contained descriptions, and updates status as work progresses.

## Install

```bash
/install-plugin https://github.com/byliu-labs/claude-todo
```

## Usage

| Command | What happens |
|---------|-------------|
| `/todo` | List all items, auto-update status from conversation context, suggest next item |
| `/todo add` | Claude scans conversation for next steps, proposes items, asks you to confirm |
| `/todo clean` | Remove completed items |

## How it works

- TODO items are stored in `.claude/todo.md` in your project repo
- Claude writes detailed, self-contained descriptions — any future session can execute items without prior context
- Status updates happen automatically as Claude works on items
- The file is meant to be committed, so your team can see planned work

## Design philosophy

**Claude manages the list, not you.** The traditional TODO workflow (user types description, user marks done) adds friction. Instead:

- `/todo add` — Claude reads the conversation and proposes items. You just confirm.
- Status transitions — Claude marks items in-progress when starting work and done when finishing.
- Rich descriptions — since the file is on disk (not in context), descriptions include file paths, function names, rationale, and expected behavior. No context is lost between sessions.

## TODO file format

```markdown
# Project TODO

> Auto-managed by `/todo` command. Persists across conversations.

## Pending

- [ ] #1 — Daily compliance table-not-found: graceful alert instead of crash (added: 2026-03-04)
  Currently `scripts/daily_compliance_check.py` raises RuntimeError (line ~185) when
  no bitable table matches the target date. Change to: send an alert message to the
  test user explaining which date/table was not found, then exit 0.

## In Progress

- [-] #3 — Refactor auth middleware (added: 2026-03-03)
  Extract token validation from each route handler into shared middleware.
  See `src/routes/api.py:authenticate()` for the pattern to extract.

## Done

- [x] #2 — Fix duplicate webhook processing (added: 2026-03-01, done: 2026-03-04)
  Added idempotency check in `src/webhooks.py:handle_event()` using event ID dedup.
```

## License

MIT

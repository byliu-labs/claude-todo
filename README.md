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
| `/todo clean` | Remove old completed items (> 2 weeks, unreferenced) |

## How it works

- TODO items are stored in `.todos/` at your project root
- A lightweight index at `.todos/index.md` has titles and status; detailed mini-PRDs live in `.todos/NNN.md`
- Claude writes detailed, self-contained descriptions — any future session can execute items without prior context
- Status updates happen automatically as Claude works on items
- A global registry at `~/.config/claude-todo/projects.md` tracks active TODOs across all your projects

### Git

The `.todos/` directory is committed by default, so your team can see planned work. Add `.todos/` to `.gitignore` if you prefer private tracking.

## Design philosophy

**Claude manages the list, not you.** The traditional TODO workflow (user types description, user marks done) adds friction. Instead:

- `/todo add` — Claude reads the conversation and proposes items. You just confirm.
- Status transitions — Claude marks items in-progress when starting work and done when finishing.
- Rich descriptions — since the file is on disk (not in context), descriptions include file paths, function names, rationale, and expected behavior. No context is lost between sessions.

## File layout

### Project-level

```
.todos/
├── index.md          # Lightweight index: titles, status, dates
├── 001.md            # Mini-PRD for item #1
├── 002.md            # etc.
└── human.md          # Human-only action items
```

### Global

```
~/.config/claude-todo/
└── projects.md       # Cross-project TODO registry
```

## Migration

If you used a previous version that stored files in `.claude/todos/`, the plugin will auto-migrate on the next `/todo` invocation: files move from `.claude/todos/` to `.todos/` and `.claude/todo.md` becomes `.todos/index.md`.

## License

MIT

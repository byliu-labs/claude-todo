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
| `/todo` | Rebuild index from frontmatter, display items with prioritization hints |
| `/todo add` | Scan conversation for next steps, propose items with Eisenhower quadrants, ask to confirm |
| `/todo clean` | Remove old completed items (> 2 weeks, unreferenced) |

## How it works

Each TODO item is a self-describing markdown file with YAML frontmatter in `.todos/`:

```yaml
---
id: 1
title: "Fix graceful alert on table-not-found"
type: todo            # todo | question | human
status: pending       # pending | in-progress | done
created: 2026-03-04
done: null
blocked_by: null      # "human", item id, or null
assignee: null
quadrant: q2          # q1 | q2 | q3 | q4 | null
deadline: null        # hard deadlines only
---
```

The index (`index.md`) is **derived** — rebuilt from frontmatter on every `/todo` invocation, never manually edited. A standalone `rebuild-index.sh` script is included for CI and non-Claude use.

### Key properties

- **Source of truth**: individual PRD files, not the index
- **Conflict-free collaboration**: each item is a separate file — git merge just works
- **Prioritization**: Eisenhower quadrants (Q1-Q4) drive cross-project planning
- **Blocking**: `blocked_by` field tracks dependencies and human-gated items
- **Global registry**: `~/.config/claude-todo/projects.md` tracks active TODOs across all projects

### Git

The `.todos/` directory is committed by default. Add `.todos/` to `.gitignore` if you prefer private tracking.

## Design philosophy

**Claude manages the list, not you.** The traditional TODO workflow (user types description, user marks done) adds friction. Instead:

- `/todo add` — Claude reads the conversation and proposes items with quadrants. You just confirm.
- Status transitions — Claude marks items in-progress when starting work and done when finishing.
- Rich descriptions — PRDs include file paths, function names, rationale, and expected behavior. No context is lost between sessions.

## File layout

```
.todos/
├── index.md          # DERIVED — regenerated on every /todo
├── 001.md            # Mini-PRD for item #1 (any type)
├── 002.md            # Mini-PRD for item #2
└── 004.md            # Open question — also a PRD file

~/.config/claude-todo/
└── projects.md       # Cross-project TODO registry
```

## Migration

If you used a previous version that stored files in `.claude/todos/`, the plugin auto-migrates on the next `/todo` invocation: files move to `.todos/` and get YAML frontmatter added.

## License

MIT

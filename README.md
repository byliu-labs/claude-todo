# claude-todo

Persistent project-level TODO tracking for Claude Code.

Claude intelligently manages the TODO list — you don't write descriptions or pick item numbers. Claude scans conversation context, writes rich self-contained descriptions, and updates status as work progresses.

## Install

```bash
/plugin marketplace add byliu-labs/claude-todo
/plugin install claude-todo@byliu-labs-claude-todo
```

Or interactively: run `/plugin`, go to **Discover**, and select claude-todo.

## Usage

| Command | What happens |
|---------|-------------|
| `/todo` | Rebuild index from frontmatter, display items with prioritization hints |
| `/todo add` | Scan conversation for next steps, propose items with Eisenhower quadrants, ask to confirm |
| `/todo clean` | Remove old completed items (> 2 weeks, unreferenced) |
| `/stats` | Print 30-day integrity + lead-time rollup from local telemetry (see Telemetry below) |

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

### Git — gitignore `.todos/` (with retro exemptions)

```bash
cat >> .gitignore <<'GITIGNORE'
.todos/*
!.todos/goal.md
!.todos/retros/
!.todos/retros/**
GITIGNORE
git add .gitignore && git commit -m "chore: untrack .todos/ PRDs"
# If you already committed PRD files, untrack them (keeps goal.md / retros/ tracked):
git ls-files .todos/ | grep -v -E '^\.todos/(goal\.md|retros/)' \
  | xargs -r git rm --cached && git commit -m "chore: untrack .todos/ PRDs"
```

**Why `.todos/*` and not `.todos/`:** Git cannot re-include a file inside an ignored directory. `.todos/` (trailing slash, no star) tells Git to skip the directory entirely — the `!` exemptions for `goal.md` and `retros/` would silently do nothing. `.todos/*` ignores the directory's *contents*, leaving the directory itself reachable so the negations take effect.

**Why this is not optional:** when Claude moves a new todo file into a feature worktree to commit unrelated code, a committed `.todos/` becomes invisible to other sessions until the PR merges. Next-id allocation scans the current working tree, so IDs get reassigned and the two files collide at merge time. Keeping PRDs out of git preserves one source of truth in the main repo.

**Why the exemptions:** `goal.md` is the per-project north star read by `/retro` and needs to travel with the repo. `retros/` accumulates week-over-week Ship Memos meant to be shared with collaborators. Both are stable, non-colliding files — they don't have the worktree/ID-reassignment problem that PRDs have.

The skill runs `bin/check-gitignore.sh` on every invocation and prints the fix commands above until this is done.

## Telemetry

Opt-in, fully local. Events write one JSONL line per occurrence to `~/.config/claude-todo/telemetry/events.jsonl`. Nothing leaves your machine.

Three tiers via `~/.config/claude-todo/config.yaml`:

```yaml
telemetry: local   # default — write events locally
# telemetry: off   # disable entirely
# telemetry: share # reserved for a future anonymized community roll-up (not implemented yet)
```

### What's recorded

- `item_created` — when `/todo add` creates an item. Payload: id, type, refined, parent, quadrant, has_deadline.
- `status_changed` — every status transition. Payload: id, from, to, days_since_created, days_since_prev_status, type, quadrant.
- `id_collision_detected` — when `rebuild-index.sh` finds two files with the same id. Surfaced to the user on the next `/todo list`.
- `worktree_escape_detected` — when `.todos/` would be written outside the main repo (self-caught guard for CLAUDE.md violations).

Every event carries: schema version, UTC timestamp, 12-char hashed `project_id` (derived from the git remote or path — never a name or absolute path in the shared form), and a short session id. Underscore-prefixed fields like `_cwd`, `_resolved_todos_dir` are local-only diagnostics and would be stripped before any future share.

### Reading your own data

```
/stats            # 30-day Integrity + Flow rollup across all tracked projects
```

Or directly: `bash $PLUGIN_DIR/bin/todo-stats.sh 30d`. The events file is plain JSONL — `jq`, `grep`, or any text tool works on it.

### Turning it off

```yaml
telemetry: off
```

Past events in `events.jsonl` stay on disk until you delete the file. Delete it whenever you want.

## Weekly retro

`/retro` produces a weekly retrospective anchored on a declared per-project goal. It:

- Reads your `.todos/` PRDs (Outcome + Learned + Work Log markers) plus local telemetry.
- Classifies closed items against the project's north star (`advances NS` / `tangent` / `tech-debt` / `unclear`).
- Emits a trajectory verdict (closer / same / drift) and a Ship Memo readable by non-engineers.
- Writes the full output to `.todos/retros/YYYY-WNN.md` (committed). Prints a 3-line pointer in the conversation.

The first run on a project triggers a short "write your north star" flow and exits — the retro refuses to guess what you're optimizing for. Subsequent runs produce the memo.

### Learning capture

Learnings feed the retro automatically via two hooks:

- **On close** — `/todo` prompts for a one-line takeaway when you transition an item to `done`, appending to the PRD's `## Learned` section.
- **During work** — use `@decision`, `@surprise`, or `@learned` markers in `## Work Log` entries. The retro greps these and includes them verbatim.

Skip the close-time prompt by pressing Enter. The markers are optional — but a week with zero of them is a signal that reasoning wasn't captured, and the retro flags it.

### Per-project setup

Requires `.todos/goal.md` + a `.todos/retros/` directory, both of which should be committed. See the gitignore recipe above.

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

## Migration from v1.x

v1.x stored everything per-project inside `.claude/`. There was no global registry.

If you have projects with the old layout (`.claude/todo.md` and `.claude/todos/`), migration is automatic. Just run `/todo` in each project — Claude will:

1. Move PRD files from `.claude/todos/*.md` → `.todos/`
2. Add YAML frontmatter to files that lack it
3. Convert `human.md` checklist entries into numbered PRD files with `type: human`
4. Rebuild the index from frontmatter
5. Clean up the empty `.claude/todos/` directory
6. Auto-create the global registry at `~/.config/claude-todo/projects.md` (new in v2.0)

No manual steps needed. The migration triggers once per project on first `/todo` run.

## License

MIT

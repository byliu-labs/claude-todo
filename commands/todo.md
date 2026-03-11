---
description: Manage project-level TODO items that persist across conversations. Claude scans context to add/update items intelligently.
argument-hint: "[list|add|clean]"
allowed-tools: Read(**), Edit(**), Write(**), Glob(**), Grep(**), AskUserQuestion
---

# Project TODO Tracker

Manages a persistent TODO index at `.todos/index.md` with detailed mini-PRDs in `.todos/NNN.md`. **Claude owns the list** — writes descriptions, manages lifecycle, and clarifies gaps before implementing.

The TODO index is cheap to read (titles only). Full PRD details live in separate files, loaded on-demand when working on an item.

A global registry at `~/.config/claude-todo/projects.md` tracks all projects with active TODOs.

## File layout

### Project-level (at project root)

```
.todos/
├── index.md          # Lightweight index: titles, status, dates
├── 001.md            # Mini-PRD for item #1
├── 002.md            # Mini-PRD for item #2
├── 004.md            # Questions also get PRD files
└── human.md          # Human action items — things only the user can do
```

The `.todos/` directory is committed to git by default. Add `.todos/` to `.gitignore` if you prefer private tracking.

### Global registry

`~/.config/claude-todo/projects.md` tracks all projects with active TODOs. Updated automatically by `/todo`. Format:

```markdown
# Active Projects

> Cross-project TODO registry. Auto-updated by `/todo`.

| Project | Path | Pending | Last updated |
|---------|------|---------|--------------|
| my-project | /absolute/path/to/project | 3 | 2026-03-11 |
```

One row per project. Remove the row when a project has zero pending + zero in-progress + zero open question items.

## Migration from `.claude/todos/`

If the project has a legacy layout (`.claude/todo.md` or `.claude/todos/`):

1. Move `.claude/todos/*.md` to `.todos/` (preserving filenames).
2. Move `.claude/todo.md` to `.todos/index.md`.
3. Update path references inside index.md from `.claude/todos/NNN.md` to `.todos/NNN.md`.
4. Delete empty `.claude/todos/` directory.
5. Do NOT delete `.claude/` itself — it may contain other Claude Code config.
6. Tell the user what was migrated.

**Trigger:** Any time `/todo` runs and `.claude/todo.md` exists but `.todos/index.md` does not. Only migrate once — if both exist, `.todos/index.md` is authoritative. If `.todos/index.md` exists AND `.claude/todos/` still contains `.md` files, warn the user about orphaned legacy files and ask whether to merge them into `.todos/`.

## Behavior based on arguments

Parse `$ARGUMENTS`:

### No arguments or "list" → Show index + auto-update

1. Read `.todos/index.md`. If missing, say "No TODO items yet. Use `/todo add` to scan the conversation for items."
2. **Auto-update**: Scan conversation for items completed or started this session. Update status in the index.
3. Display items grouped by: Pending, In Progress, Open Questions, Done.
4. Suggest next item to work on (lowest pending number).
5. If open questions now have enough context to resolve, propose converting or closing.
6. If completed items > 2 weeks old, suggest `/todo clean`.
7. **Update global registry**: Read `~/.config/claude-todo/projects.md` (create dir + file if missing). Update (or insert) the row for the current project: set pending count from the index, set last-updated to today. If the project has zero pending + zero in-progress + zero open question items, remove the row. Note: concurrent sessions in different projects may overwrite each other's row updates — if a row appears missing, re-run `/todo` in that project to re-register.

### "add" → Scan context and propose new items

1. Read `.todos/index.md` (create `.todos/` dir if missing).
2. Scan conversation for three categories:
   - **Actionable TODOs** (for Claude): agreed-upon changes, next steps, discovered bugs, "do later" items
   - **Open Questions**: unresolved design decisions, edge cases needing investigation, trade-offs without conclusions (NOT pure musings — must have concrete project impact)
   - **Human action items**: things only the user can do — manual testing (E2E, UI, device-specific), PM decisions, config changes in external services, credential setup, stakeholder communication, etc.
3. Draft proposed items as mini-PRDs (TODOs and Questions) or as human checklist items.
4. **Ask user to confirm** (AskUserQuestion, multiSelect). Present all three categories separately.
5. For each confirmed item:
   - TODOs/Questions: add one-line entry to `index.md` + create `.todos/NNN.md` with full PRD.
   - Human items: append to `.todos/human.md` (see format below).
6. **Update global registry**: Same as list step 7.

### "clean" → Remove old completed items

1. Only remove `[x]` entries that are **> 2 weeks old AND not referenced by any pending/in-progress item**.
2. Before deleting, check if any pending item's PRD mentions the completed item's number (e.g., "after #2 is done" or "blocked by #1"). If so, keep it.
3. Remove qualifying entries from `index.md` and their `.todos/NNN.md` files.
4. Report what was cleared and what was kept (with reason).
5. **Update global registry**: Same as list step 7.

## Lifecycle management

Claude manages status **proactively during normal work**:

- **Starting work**: Read the item's `.todos/NNN.md` first, update index to `[-]`.
- **Finishing work**: Update index to `[x]` with completion date. **Never delete** — move to Done. The PRD file is kept for reference by related items.
- **Discovering follow-up**: Mention to user, offer to add. If the new item depends on the just-completed one, note the dependency in the new PRD.
- **Natural break points**: When Claude finishes a chunk of work (implementation + tests passing, a PR-ready commit, completing a TODO item), check `.todos/human.md` for pending human items. If any are relevant to what was just completed, **remind the user** with a brief summary of what needs their attention and why now is a good time.

### Clarify-first protocol

**Before writing code for a TODO, read its `.todos/NNN.md` and check for `[TBD]` markers or gaps.** If any required PRD section is missing/vague, ask the user BEFORE starting. Check:
1. Is the expected behavior specific enough to write a test from?
2. Are edge cases covered?
3. Is scope clear (what's in AND what's out)?

### Open question lifecycle

- **Resolve** → convert to TODO (new `[ ]` item) or close with brief note in Done.
- **Stale** → during `/todo list`, flag questions open > 1 week and ask if user has new context.

## Index format (`index.md`)

```markdown
# Project TODO

> Index only — details in `.todos/NNN.md`.

## Pending

- [ ] #1 — Daily compliance: graceful alert on table-not-found (added: 2026-03-04)
- [ ] #2 — Weekly compliance: forgiveness logic for back-fillers (added: 2026-03-04)

## In Progress

- [-] #3 — Update methodology doc with holiday edge cases (added: 2026-03-04)

## Open Questions

- ? #4 — Should 40h standard adjust for holiday weeks? (added: 2026-03-04)

## Done

- [x] #5 — Fix duplicate webhook processing (added: 2026-03-01, done: 2026-03-04)
```

Index rules:
- One line per item — title only, no details
- Sequential numbering across all sections (never reuse)
- `[ ]` / `[-]` / `[x]` for TODOs, `?` for questions
- Keep all sections even if empty
- PRD filenames are zero-padded to 3 digits: `001.md`, `002.md`, ..., `999.md`

## PRD file format (`.todos/NNN.md`)

Each file is a mini-PRD. Required sections for TODOs:

```markdown
# #1 — Daily compliance: graceful alert on table-not-found

**Problem:** [Why this needs to change — the pain point or failure mode]

**Current behavior:** [What happens now, with file paths and line numbers]

**Expected behavior:** [What should happen after, specific enough to write tests from]

**Edge cases:** [Boundary conditions, failure modes, special scenarios]

**Test plan:** [How to verify — unit tests, manual steps, expected output]

**Scope:** [What's in scope. What's explicitly NOT in scope.]
```

For open questions:

```markdown
# #4 — Should 40h standard adjust for holiday weeks?

**Context:** [Background on the issue]

**Options:** [Known alternatives with trade-offs]

**What would resolve this:** [Decision or information needed]

**Impact if ignored:** [What goes wrong if we don't address this]
```

PRD rules:
- Use `[TBD]` for missing sections — signals "clarify before implementing"
- Include file paths, function names, line references where stable
- Be detailed — these files are loaded on-demand, not always in context
- If a PRD exceeds ~40 lines, the TODO might be too big — consider splitting

## Human action items (`.todos/human.md`)

A flat `- [ ]` / `- [x]` checklist for things only the human can do: manual testing, PM decisions, external config, credential setup, etc. Not numbered — lives outside the TODO index. Reference related TODO numbers where applicable (e.g., "after #2 is done").

Example:

```markdown
# Human Action Items

- [ ] Run E2E tests on staging after #2 is deployed
- [ ] Set up API key in production dashboard (needed for #3)
- [x] Confirmed holiday schedule with PM (2026-03-05)
```

Claude adds items during `/todo add`, checks them off when the user says they've done something, and **reminds the user at natural break points** — after completing a TODO, after all pending work is done, or at session start if stale items exist.

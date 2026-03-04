---
description: Manage project-level TODO items that persist across conversations. Claude scans context to add/update items intelligently.
argument-hint: "[add|clean]"
allowed-tools: Read(**), Edit(**), Write(**), Glob(**), Grep(**), AskUserQuestion
---

# Project TODO Tracker

Manages a persistent TODO index at `.claude/todo.md` with detailed mini-PRDs in `.claude/todos/NNN.md`. **Claude owns the list** — writes descriptions, manages lifecycle, and clarifies gaps before implementing.

The TODO index is cheap to read (titles only). Full PRD details live in separate files, loaded on-demand when working on an item.

## File layout

```
.claude/
├── todo.md              # Lightweight index: titles, status, dates
└── todos/
    ├── 001.md           # Mini-PRD for item #1
    ├── 002.md           # Mini-PRD for item #2
    └── 005.md           # Questions also get PRD files
```

## Behavior based on arguments

Parse `$ARGUMENTS`:

### No arguments or "list" → Show index + auto-update

1. Read `.claude/todo.md`. If missing, say "No TODO items yet."
2. **Auto-update**: Scan conversation for items completed or started this session. Update status in the index.
3. Display items grouped by: Pending, In Progress, Open Questions, Done.
4. Suggest next item to work on (lowest pending number).
5. If open questions now have enough context to resolve, propose converting or closing.
6. If completed items > 2 weeks old, suggest `/todo clean`.

### "add" → Scan context and propose new items

1. Read `.claude/todo.md` (create `.claude/` and `.claude/todos/` dirs if missing).
2. Scan conversation for two categories:
   - **Actionable TODOs**: agreed-upon changes, next steps, discovered bugs, "do later" items
   - **Open Questions**: unresolved design decisions, edge cases needing investigation, trade-offs without conclusions (NOT pure musings — must have concrete project impact)
3. Draft proposed items as mini-PRDs.
4. **Ask user to confirm** (AskUserQuestion, multiSelect). Present TODOs and Questions separately.
5. For each confirmed item: add one-line entry to `todo.md` index + create `todos/NNN.md` with full PRD.

### "clean" → Remove old completed items

1. Only remove `[x]` entries that are **> 2 weeks old AND not referenced by any pending/in-progress item**.
2. Before deleting, check if any pending item's PRD mentions the completed item's number (e.g., "after #2 is done" or "blocked by #1"). If so, keep it.
3. Remove qualifying entries from `todo.md` and their `todos/NNN.md` files.
4. Report what was cleared and what was kept (with reason).

## Lifecycle management

Claude manages status **proactively during normal work**:

- **Starting work**: Read the item's `todos/NNN.md` first, update index to `[-]`.
- **Finishing work**: Update index to `[x]` with completion date. **Never delete** — move to Done. The PRD file is kept for reference by related items.
- **Discovering follow-up**: Mention to user, offer to add. If the new item depends on the just-completed one, note the dependency in the new PRD.

### Clarify-first protocol

**Before writing code for a TODO, read its `todos/NNN.md` and check for `[TBD]` markers or gaps.** If any required PRD section is missing/vague, ask the user BEFORE starting. Check:
1. Is the expected behavior specific enough to write a test from?
2. Are edge cases covered?
3. Is scope clear (what's in AND what's out)?

### Open question lifecycle

- **Resolve** → convert to TODO (new `[ ]` item) or close with brief note in Done.
- **Stale** → during `/todo list`, flag questions open > 1 week and ask if user has new context.

## Index format (`todo.md`)

```markdown
# Project TODO

> Index only — details in `.claude/todos/NNN.md`.

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

## PRD file format (`todos/NNN.md`)

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

---
description: Manage project-level TODO items that persist across conversations. Claude scans context to add/update items intelligently.
argument-hint: "[list|add|clean]"
allowed-tools: Read(**), Edit(**), Write(**), Glob(**), Grep(**), AskUserQuestion
---

# Project TODO Tracker

Manages persistent TODO items in `.todos/`. Each item is a self-describing markdown file with YAML frontmatter. The index (`index.md`) is **derived** — rebuilt from scanning frontmatter, never manually edited.

**Claude owns the list** — writes descriptions, manages lifecycle, and clarifies gaps before implementing.

## Architecture

```
.todos/
├── index.md          # DERIVED — regenerated on every /todo invocation
├── 001.md            # Mini-PRD for item #1 (any type)
├── 002.md            # Mini-PRD for item #2
└── 004.md            # Open question — also a PRD file
```

Every item — whether actionable by Claude, blocked on a human, or an open question — is a numbered PRD file. The frontmatter `type` and `status` fields determine how items appear in the index.

The `.todos/` directory is committed to git by default. Add `.todos/` to `.gitignore` if you prefer private tracking.

### Global registry

`~/.config/claude-todo/projects.md` tracks all projects with active TODOs. Updated automatically by `/todo`. Format:

```markdown
# Active Projects

> Cross-project TODO registry. Auto-updated by `/todo`.

| Project | Path | Next action | Nearest deadline | Q1 | Q2 | Blocked | Last updated |
|---------|------|-------------|------------------|----|----|---------|--------------|
| odyssey-ml | /path/to/odyssey | #3 Update methodology doc | 2026-03-15 | 1 | 2 | 1 | 2026-03-11 |
| nest | /path/to/nest | #12 Snapshot testing setup | — | 0 | 3 | 0 | 2026-03-11 |
```

- **Next action**: Title of the lowest-numbered pending, unblocked item.
- **Nearest deadline**: Earliest `deadline` among non-done items, or `—`.
- **Q1 / Q2**: Count of non-done items in each quadrant.
- **Blocked**: Count of items with `blocked_by` set.

Remove a row when a project has zero non-done items.

## Frontmatter schema

```yaml
---
id: 1
title: "Daily compliance: graceful alert on table-not-found"
type: todo            # todo | question | human
status: pending       # pending | in-progress | done
created: 2026-03-04
done: null            # YYYY-MM-DD when completed, or null
blocked_by: null      # "human", item id (integer), or null
assignee: null        # name string or null
quadrant: q2          # q1 | q2 | q3 | q4 | null
deadline: null        # YYYY-MM-DD or null (hard deadlines only)
---
```

### Field rules

- `id`: Sequential integer, never reused. Zero-padded in filenames: `001.md`.
- `type`:
  - `todo` — actionable by Claude or developer
  - `question` — unresolved design decision with concrete project impact
  - `human` — only a human can do this (manual testing, PM decisions, credential setup, external config)
- `status`: Three states only — `pending`, `in-progress`, `done`.
  - **There is no `blocked` status.** Blocked items have `status: pending` with `blocked_by` set. The index generator uses `blocked_by` as a display hint to group them separately.
- `blocked_by`: Single value. `"human"` for human-gated items, an integer item id for dependency chains, or `null`. **Limitation**: only one blocker per item. If an item has multiple blockers, pick the primary one and note others in the PRD body.
- `assignee`: Name string for collaboration (works with git transport), or `null`.
- `quadrant`: Eisenhower classification. `q1` = urgent + important (do first), `q2` = important, not urgent (schedule and protect), `q3` = urgent, not important (timebox), `q4` = neither (eliminate). `null` = not yet classified.
- `deadline`: Hard external deadlines only (launches, contracts, compliance). Not aspirational targets.

## PRD body templates

### TODOs and human items

```markdown
# #1 — Daily compliance: graceful alert on table-not-found

**Problem:** [Why this needs to change]

**Current behavior:** [What happens now, with file paths and line numbers]

**Expected behavior:** [Specific enough to write tests from]

**Edge cases:** [Boundary conditions, failure modes]

**Test plan:** [How to verify]

**Scope:** [In scope. Explicitly NOT in scope.]
```

For `type: human`, replace Problem/Current/Expected with:

```markdown
# #7 — Set up API key in production dashboard

**What:** [Concrete action the human needs to take]

**Why:** [What depends on it]

**Needed for:** #3

**Done when:** [Observable outcome that confirms completion]
```

### Questions

```markdown
# #4 — Should 40h standard adjust for holiday weeks?

**Context:** [Background]

**Options:** [Alternatives with trade-offs]

**What would resolve this:** [Decision or info needed]

**Impact if ignored:** [What goes wrong]
```

### PRD rules

- Use `[TBD]` for missing sections — signals "clarify before implementing"
- Include file paths, function names, line references where stable
- Be detailed — these files are loaded on-demand, not always in context
- If a PRD exceeds ~40 lines, consider splitting into smaller items

## Index generation

The index is **never manually edited**. Claude rebuilds it by reading frontmatter from all `.todos/[0-9][0-9][0-9].md` files on every `/todo` invocation. This is pure string formatting — no LLM reasoning needed.

A standalone `rebuild-index.sh` script ships with the plugin repo for CI and non-Claude use. Claude does not need to generate this script — it reads frontmatter directly and writes the index inline.

### Index format

```markdown
# Project TODO

> Auto-generated from `.todos/*.md` frontmatter. Do not edit manually.

## In Progress

- [-] #3 — Update methodology doc (added: 2026-03-04) @asher

## Pending

- [ ] #1 — Daily compliance: graceful alert (added: 2026-03-04) [q1] (due: 2026-03-15)
- [ ] #2 — Weekly compliance: forgiveness logic (added: 2026-03-04) [q2]

## Blocked

- [ ] #7 — Set up API key in production dashboard (added: 2026-03-04) [blocked: human] [q1]
- [ ] #8 — Deploy alerting to staging (added: 2026-03-05) [blocked: 7]

## Open Questions

- ? #4 — Should 40h standard adjust for holiday weeks? (added: 2026-03-04)

## Done

- [x] #5 — Fix duplicate webhook processing (added: 2026-03-01, done: 2026-03-04)
```

Grouping logic:
- `status: in-progress` → In Progress
- `status: pending` + `blocked_by: null` → Pending
- `status: pending` + `blocked_by` set → Blocked (display the blocker)
- `type: question` + not done → Open Questions
- `status: done` → Done

Suffix tags: show `@assignee` if set, `[qN]` if set, `(due: date)` if set, `[blocked: X]` if blocked.

### Token cost

Reading the index: ~20-50 tokens. Reading one PRD: ~100-200 tokens. Claude loads PRDs on-demand only when working on an item.

## Behavior based on arguments

### No arguments or "list" → Rebuild index + display

1. Scan all `.todos/[0-9][0-9][0-9].md` frontmatter.
2. **Auto-update**: Scan conversation for items completed or started this session. Update frontmatter in relevant PRD files.
3. **Rebuild index** from frontmatter.
4. Display grouped items.
5. **Prioritization hints**:
   - Flag Q1 items not in-progress.
   - Flag items with deadline within 7 days not in-progress.
   - Suggest next item: lowest pending unblocked, preferring Q1 > Q2 > Q3 > unclassified > Q4.
6. If open questions have enough context to resolve, propose converting or closing.
7. If done items > 2 weeks old, suggest `/todo clean`.
8. **Update global registry**.

### "add" → Scan context and propose new items

1. Read index (rebuild if stale; create `.todos/` dir if missing).
2. Scan conversation for: actionable TODOs, open questions, human action items.
3. Draft items with frontmatter + PRD body. **Propose a quadrant for each.** Ask about deadline only if there's reason to believe one exists.
4. **Ask user to confirm** (AskUserQuestion, multiSelect). Present categories separately. Include proposed quadrant so user can override.
5. Create `.todos/NNN.md` for each confirmed item.
6. Rebuild index. Update global registry.

### "clean" → Remove old completed items

1. Only remove done items **> 2 weeks old AND not referenced by any non-done item's PRD**.
2. Remove qualifying `.todos/NNN.md` files.
3. Rebuild index. Update global registry.
4. Report what was cleared and what was kept (with reason).

## Lifecycle management

Claude manages status **proactively during normal work**:

- **Starting work**: Read `.todos/NNN.md`, update to `status: in-progress`.
- **Finishing work**: Update to `status: done`, set `done: YYYY-MM-DD`. Never delete the file.
- **Discovering follow-up**: Offer to add. Set `blocked_by` on new item if it depends on the completed one.
- **Natural break points**: After completing work, check for `type: human` items. Remind the user if any are relevant.
- **Unblocking**: When a human confirms completion, set their item to `status: done`. Check if other items have `blocked_by` pointing to it — clear their `blocked_by` to `null`.

### Clarify-first protocol

**Before writing code for a TODO, read its PRD and check for `[TBD]` markers.** If any required section is missing or vague, ask the user BEFORE starting:
1. Is expected behavior specific enough to write a test from?
2. Are edge cases covered?
3. Is scope clear?

### Open question lifecycle

- **Resolve** → create a TODO or mark done with brief note.
- **Stale** → flag questions open > 1 week during `/todo list`.

## Collaboration: git as transport

Each item is a self-describing file, so collaborators can independently create and edit PRD files without conflict. The index is derived and rebuilt locally — it never conflicts.

**ID allocation**: `glob .todos/[0-9]*.md` to find next available number. On rare simultaneous creates, git merge surfaces both files and the next `/todo` detects + renumbers duplicates.

See `personal-os-vision.md` for the MCP server extension roadmap. The file format doesn't change when switching transports.

## Migration from `.claude/todos/`

**Trigger:** `/todo` runs and `.claude/todo.md` exists but `.todos/index.md` does not.

v1.x stored everything per-project inside `.claude/`. There was no global registry.

1. Move `.claude/todos/*.md` → `.todos/` (preserve filenames).
2. Add YAML frontmatter to each PRD file that lacks it. Parse title and status from old index entries or file content. Set `quadrant: null`, `deadline: null`, `blocked_by: null`.
3. If `.claude/todos/human.md` exists, convert each `- [ ]` / `- [x]` entry into a separate numbered PRD file with `type: human`, `blocked_by: "human"`. Then delete `human.md`.
4. Regenerate index from frontmatter.
5. Delete empty `.claude/todos/`. Do NOT delete `.claude/` itself.
6. The global registry at `~/.config/claude-todo/projects.md` is new — it will be auto-created and populated when the "Update global registry" step runs at the end of `/todo list`.
7. Tell the user what was migrated.

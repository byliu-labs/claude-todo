---
description: Manage project-level TODO items that persist across conversations. Claude scans context to add/update items intelligently.
argument-hint: "[add|clean]"
allowed-tools: Read(**), Edit(**), Write(**), Glob(**), Grep(**), AskUserQuestion
---

# Project TODO Tracker

Manages a persistent TODO file at `.claude/todo.md` in the current project repo. **Claude owns the list** — Claude writes descriptions, decides when items are done, and manages lifecycle. The user just says `/todo` to see status or `/todo add` to capture new items from the conversation.

## How to determine the project root

Use the current working directory. The TODO file lives at `<project-root>/.claude/todo.md`.

## Behavior based on arguments

Parse `$ARGUMENTS` to determine the action:

### No arguments or "list" → Show current TODOs + auto-update

1. Read `.claude/todo.md`. If it doesn't exist, say "No TODO items yet."
2. **Auto-update**: Scan the current conversation context for items that may have been completed or started. If any TODO items have been addressed by work done in this session, update their status automatically (move to Done with completion date, or to In Progress).
3. Display all items grouped by status (Pending, In Progress, Done).
4. Suggest which item to work on next (lowest-numbered pending item).
5. If there are completed items older than 2 weeks, suggest running `/todo clean`.

### "add" → Scan context and propose new TODOs

1. Read `.claude/todo.md` (create if missing).
2. **Scan the entire conversation** for:
   - Explicit next steps mentioned by the user or by Claude
   - Agreed-upon changes that haven't been implemented yet
   - Follow-up work identified during implementation
   - Bug reports or issues discovered but not yet fixed
   - Anything the user said "let's do that later" or "next time" about
3. Draft a list of proposed TODO items with rich, self-contained descriptions (see "Writing good TODO descriptions" below).
4. **Ask the user to confirm** which items to add (use AskUserQuestion with multiSelect). Include a brief summary for each proposed item so the user can judge.
5. Add confirmed items to the file with sequential numbers and today's date.
6. If no new TODOs are found in context, say so.

### "clean" → Remove completed items

1. Read `.claude/todo.md`.
2. Remove all items marked `[x]`.
3. Write the updated file.
4. Show how many items were cleared.

## Automatic lifecycle management

Claude should manage TODO status changes **proactively during normal work**, not just when `/todo` is invoked:

- **When starting work on a TODO item**: Update it to `[-]` (In Progress).
- **When finishing work on a TODO item**: Update it to `[x]` (Done) with completion date.
- **When discovering new follow-up work during implementation**: Mention it to the user and offer to add it.

This means `/todo` (list) often just confirms what Claude has already been tracking.

## Writing good TODO descriptions

The TODO file lives on disk — it does NOT consume context tokens until read. So descriptions should be **detailed and self-contained**. A future Claude session (or a teammate) with zero memory of the original conversation should be able to pick up and execute the item.

### What to include

- **What** needs to change (specific behavior, not vague goals)
- **Where** in the codebase (file paths, function names, line references if stable)
- **Why** this change is needed (the problem or motivation)
- **How** it should work (expected behavior after the change)
- **Context** that informed the decision (edge cases discussed, alternatives rejected)

### Examples

**Bad — too vague, requires re-discovery:**
```
- [ ] #1 — Fix daily compliance error handling (added: 2026-03-04)
```

**Bad — slightly better but still missing the "how" and "why":**
```
- [ ] #1 — Daily compliance: send alert on table-not-found instead of raising RuntimeError (added: 2026-03-04)
```

**Good — self-contained, actionable without original conversation:**
```
- [ ] #1 — Daily compliance table-not-found: graceful alert instead of crash (added: 2026-03-04)
  Currently `scripts/daily_compliance_check.py` raises RuntimeError (line ~185) when
  no bitable table matches the target date and no fallback FEISHU_BITABLE_TABLE_ID is
  configured. In CI this crashes silently. Change to: send an alert message to the test
  user (via feishu_client send_message) explaining which date/table was not found, then
  exit 0 so CI doesn't show a red X for a non-error condition. The alert should include
  the date searched and suggest checking if the weekly bitable was created.
```

**Good — captures the full decision context:**
```
- [ ] #2 — Weekly compliance: only count currently-missing people (forgiveness logic) (added: 2026-03-04)
  In `src/compliance.py:format_weekly_summary()` (line ~714), the missed_count merges
  historical ever-missed IDs (from `_fetch_ever_missed_open_ids()`) with current violations.
  This creates confusing messages like "2人有缺失" + "所有缺失已补填". Decision: change
  missed_count to use only `len(violations)` (currently-missing). This makes back-fillers
  fully forgiven. After this change, `_fetch_ever_missed_open_ids()` and the
  "所有缺失已补填" branch become dead code — remove them. No tracking table schema changes
  needed. Also update `output/report-methodology.md` section on "ever missed" to reflect
  the new behavior.
```

### Formatting rules for multi-line descriptions

- First line: concise title after the `#N —`
- Subsequent lines: indented 2 spaces under the `- [ ]` marker
- Use blank lines between paragraphs within a description if needed
- Keep each item under ~10 lines — if it needs more, it should probably be split into multiple TODOs

## TODO file format

```markdown
# Project TODO

> Auto-managed by `/todo` command. Persists across conversations.
> Claude maintains this list — scans conversation context to add items,
> updates status as work progresses. Descriptions are intentionally detailed
> so any future session can execute them without prior context.

## Pending

- [ ] #1 — Daily compliance table-not-found: graceful alert instead of crash (added: 2026-03-04)
  Currently `scripts/daily_compliance_check.py` raises RuntimeError (line ~185) when
  no bitable table matches the target date and no fallback is configured. In CI this
  crashes silently. Change to: send an alert message to the test user explaining which
  date/table was not found, then exit 0.

- [ ] #2 — Weekly compliance forgiveness logic (added: 2026-03-04)
  In `src/compliance.py:format_weekly_summary()`, change missed_count to only count
  currently-missing people (`len(violations)`), not historically-missed. Remove the
  `_fetch_ever_missed_open_ids()` call and "所有缺失已补填" dead code branch.

## In Progress

- [-] #3 — Working on this task (added: 2026-03-03)
  Description with enough context to understand the task fully.

## Done

- [x] #4 — Completed task title (added: 2026-03-01, done: 2026-03-04)
  Original description preserved for history.
```

Rules:
- Items are numbered sequentially (never reuse numbers, even after removal)
- New items always get the next number (max existing + 1)
- Keep all three sections even if empty
- Dates use YYYY-MM-DD format
- Multi-line descriptions indented 2 spaces under the checkbox marker

## Important

- Always create the `.claude/` directory if it doesn't exist
- This file SHOULD be committed to the repo so the team can see planned work
- Do NOT duplicate items that already exist — check before adding
- When in doubt, add MORE context rather than less — disk is cheap, re-discovery is expensive

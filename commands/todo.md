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
3. Display all items grouped by status (Pending, In Progress, Open Questions, Done).
4. Suggest which item to work on next (lowest-numbered pending item).
5. If any open questions now have enough context to resolve, propose converting them to TODOs or closing them.
6. If there are completed items older than 2 weeks, suggest running `/todo clean`.

### "add" → Scan context and propose new TODOs

1. Read `.claude/todo.md` (create if missing).
2. **Scan the entire conversation** for two categories:

   **Actionable TODOs** (things we know how to do):
   - Explicit next steps mentioned by the user or by Claude
   - Agreed-upon changes that haven't been implemented yet
   - Follow-up work identified during implementation
   - Bug reports or issues discovered but not yet fixed
   - Anything the user said "let's do that later" or "next time" about

   **Open Questions** (unresolved issues that may become TODOs):
   - Design questions where we discussed trade-offs but didn't decide
   - Edge cases or asymmetries discovered but not yet addressed
   - "We should think about X" or "I wonder if Y" — anything unresolved that has practical implications
   - Questions that need investigation, data, or user input before they're actionable
   - Do NOT capture pure musings or philosophical tangents — only questions tied to concrete project concerns

3. Draft proposed items in both categories with rich descriptions (see "Writing good TODO descriptions" and "Writing good open questions" below).
4. **Ask the user to confirm** which items to add (use AskUserQuestion with multiSelect). Present TODOs and Questions as separate groups so the user can judge each.
5. Add confirmed items to the file with sequential numbers and today's date.
6. If no new items are found in context, say so.

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

### Open question lifecycle

- **Adding**: When a conversation surfaces an unresolved design question, edge case, or trade-off with no clear answer, add it as a `?` item.
- **Resolving**: When a question gets answered (by the user, by investigation, or by a later conversation), either:
  - Convert it to a TODO: add a new `[ ]` item with the decided action, remove the `?` item.
  - Close it: remove the `?` item and note the resolution briefly in the Done section if it's worth preserving.
- **Stale questions**: During `/todo` list, if a question has been open for a while, mention it and ask if the user has new context.

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

## Writing good open questions

Open questions are things we noticed or discussed but can't act on yet. They sit in a dedicated section until resolved — at which point they either become a TODO or get removed.

### What qualifies as an open question

- A design decision with multiple valid approaches and no clear winner yet
- An edge case or inconsistency discovered during work that needs more thought
- Something that requires investigation, profiling, or user/stakeholder input
- A known asymmetry or gap that might need fixing but the priority is unclear

### What does NOT qualify

- Pure musings ("wouldn't it be cool if...")
- Questions already answered in the conversation (capture the answer as a TODO instead)
- Vague concerns without concrete project impact

### Examples

**Good — captures the tension and what would resolve it:**
```
- ? #5 — Should weekly compliance adjust the 40h standard for holiday weeks? (added: 2026-03-04)
  Currently a week with 3 statutory holidays still expects 40h, which flags everyone
  as below standard. Options: (a) pro-rate to 8h × workdays, (b) skip the check for
  short weeks, (c) leave as-is since holiday overtime should compensate. Need to check
  with PM whether the 40h target is meant to be absolute or workday-proportional.
```

**Good — documents a discovered asymmetry:**
```
- ? #6 — Compliance vs analytics disagree on holiday overtime (added: 2026-03-04)
  Compliance ignores holiday work entirely (is_workday filter), but CEO dashboard and
  ROI reports count all hours including holidays. Someone working 8h on a holiday gets
  zero compliance credit but the hours appear in analytics. Is this intentional? If not,
  which system should change? Needs product decision before we can write a TODO.
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

## Open Questions

- ? #5 — Should weekly compliance adjust the 40h standard for holiday weeks? (added: 2026-03-04)
  Currently a week with 3 statutory holidays still expects 40h, which flags everyone
  as below standard. Options: (a) pro-rate to 8h × workdays, (b) skip the check for
  short weeks, (c) leave as-is. Need PM input on whether 40h is absolute or proportional.

## Done

- [x] #4 — Completed task title (added: 2026-03-01, done: 2026-03-04)
  Original description preserved for history.
```

Rules:
- Items are numbered sequentially across ALL sections (never reuse numbers, even after removal)
- New items always get the next number (max existing + 1)
- Keep all sections even if empty
- Dates use YYYY-MM-DD format
- Multi-line descriptions indented 2 spaces under the marker
- TODOs use `[ ]` / `[-]` / `[x]` markers; Questions use `?` marker
- When a question is resolved: either convert it to a TODO (new `[ ]` item referencing the question number) or remove it with a brief note of the resolution

## Important

- Always create the `.claude/` directory if it doesn't exist
- This file SHOULD be committed to the repo so the team can see planned work
- Do NOT duplicate items that already exist — check before adding
- When in doubt, add MORE context rather than less — disk is cheap, re-discovery is expensive

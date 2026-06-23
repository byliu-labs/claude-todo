---
description: Audit pending todos against the codebase and close implemented/stale ones. This command should be used when the user asks to "clean up stale todos", "audit pending todos", "check which todos are done", "todo hygiene", or "codebase todo audit".
argument-hint: "[--dry-run]"
allowed-tools: Read(**), Edit(**), Write(**), Glob(**), Grep(**), Bash(**), Agent(**), AskUserQuestion
---

# Todo Cleanup — Codebase-Verified Audit

Audit all pending `.todos/` items against the actual codebase. Close items whose
**Expected Behavior** is fully implemented. Present findings for user approval
before writing any changes.

**This is NOT the same as `/todo review`.** Review grooms the backlog (stale items,
overlaps, unrefined items). Cleanup verifies whether pending work has actually been
done in the codebase.

## Anti-patterns (hard failures from real audits)

These caused 11 false closures in the first real-world run. Treat each as a
blocking validation rule — if any is violated, the item stays pending.

| Anti-pattern | Example | Why it fails |
|---|---|---|
| **Title matching** | `spot_check_import.py` exists → "spot check" todo is done | Script generates samples; todo asks a human to verify them |
| **File existence = feature done** | `db.py` exists → "auto-fill from DB" is done | File stores records but has no lookup function |
| **Config = execution** | `outlook_sync.yaml` lists 15 mailboxes → "backup 14 mailboxes" is done | Config added but backfill never ran |
| **Prerequisite = deliverable** | Shadow mode (v1 baseline) exists → "preview mode" (v2 feature) is done | Two different features with overlapping vocabulary |
| **Parent closed with open children** | All children "probably done" → close parent | One child reverts, parent is wrong |
| **Time-gated todo closed early** | "Closes after 12 weeks of p95 < threshold" → closed at week 2 | Monitoring window hasn't elapsed |
| **Human-gated closed by code** | `blocked_by: "human"` but code evidence exists | Human action (interview, config, ops decision) was never taken |

## Execution flow

### Phase 1 — Collect

Read all `.todos/[0-9]*.md` files. Filter to `status: pending` or `status: in-progress`.
Record id, title, type, parent, blocked_by, created date, and quadrant.

### Phase 2 — Classify

Sort items into verification tracks:

| Track | Condition | Audit method |
|---|---|---|
| **Skip** | `blocked_by: "human"`, `type: human`, `type: question` | Cannot close by code evidence. Report as "skipped (human/question)". |
| **Skip** | PRD body contains time-gate language ("closes after N weeks/months", "re-evaluate in") | Cannot close before time window elapses. Report as "skipped (time-gated)". |
| **Skip** | `type: feature` (parent) | Derived from children. Only closeable after all children close. |
| **Verify** | Everything else | Proceed to Phase 3. |

### Phase 3 — Verify (the critical phase)

For each item on the Verify track:

**Step 1 — Read the full PRD.** Not the title. Not the first line. The entire
`Expected behavior` section plus `Test plan` and `Scope`.

**Step 2 — Extract verification targets.** For each bullet in Expected behavior,
identify what codebase evidence would prove it:

- A named script or function → grep for it, then READ the implementation to
  verify it does what the spec describes (not just that it exists)
- A DB table or column → check `sql/` migrations
- A UI component → check the frontend source
- A config entry → check it exists AND that consumers read it
- An integration or wiring → check the call site, not just the definition

**Step 3 — Score each bullet.**

| Score | Meaning |
|---|---|
| **met** | Implementation matches the spec bullet. Evidence: specific file + line. |
| **partial** | Something related exists but doesn't fully satisfy the bullet. |
| **unmet** | No evidence found, or evidence contradicts the spec. |

**Step 4 — Verdict.**

| Condition | Verdict |
|---|---|
| ALL bullets scored **met** | `done` — propose closing |
| MOST bullets **met**, remainder are trivial/obsolete | `done` — propose closing with note |
| Mix of **met** and **unmet** | `keep` — report what's done and what's not |
| ALL bullets **unmet** | `keep` — no action needed |
| Spec is clearly superseded by a different approach | `superseded` — propose closing with `resolved_by` |
| Spec describes something no longer relevant | `wontfix` — propose cancelling |

### Phase 4 — Check parents

After individual verdicts, check parent features:
- If ALL children of a feature are now `done` or `cancelled` → propose closing parent
- If not → leave parent open, report remaining children

### Phase 5 — Present findings

Display a table for user approval. Group by verdict:

```
## Propose closing (N items)

| # | Title | Verdict | Evidence |
|---|-------|---------|----------|
| 266 | Cron-failure alerting | done | pipeline_watchdog.py + install-cron.sh |
| 076 | CI drift check | superseded | drift audit #441/#443 |

## Keep open (M items)

| # | Title | Why |
|---|-------|-----|
| 258 | Outreach auto-fill | db.py stores influencer_id but no handle→email lookup |
| 278 | Mailbox backup | Config added, backfill not executed |

## Skipped (K items)

| # | Title | Reason |
|---|-------|--------|
| 238 | Retire templates T13/T20 | blocked:human |
| 309 | Track bot latency | time-gated (12-week window) |
```

Use `AskUserQuestion` with multiSelect to let the user approve/reject each
proposed closure individually.

### Phase 6 — Execute

For each approved closure:

1. Update frontmatter: `status: done`, `done: YYYY-MM-DD`, `resolution: "completed"` or
   `"superseded"` or `"cancelled"` with a brief evidence note.
2. Emit `status_changed` telemetry event.
3. Check if closing this item completes a parent feature → prompt user.

After all updates:
- Run `rebuild-index.sh`
- Update global registry

## Parallelization strategy

With many pending items (50+), Phase 3 is slow if done sequentially. Use the
Agent tool to parallelize verification in batches:

- Group items by category (from frontmatter `category` field)
- Dispatch one agent per category (max 4-5 concurrent)
- Each agent receives the full PRD text for its batch, not just titles
- Each agent must return per-bullet evidence, not just a verdict

**Mandatory in every agent prompt:**

```
Tool rules (follow strictly):
- Search file contents → Grep tool, NOT bash grep/rg
- Read files → Read tool, NOT cat/head/tail/sed
- Find files → Glob tool, NOT find/ls
- Never use bash pipes (|)

Validation rules:
- READ the full Expected Behavior section of each todo
- For each bullet, find the IMPLEMENTING code, not just a file with a matching name
- A file existing is NOT proof of completion — read it and verify the logic matches
- Report per-bullet evidence: file path + what the code actually does
```

## `--dry-run` flag

When `--dry-run` is passed (or user says "just check", "audit only", "don't change
anything"), execute Phases 1-5 but skip Phase 6. Report findings without modifying
any files.

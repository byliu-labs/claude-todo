---
description: "Weekly retro — learnings, trajectory vs north star, Ship Memo for leadership. Writes .todos/retros/YYYY-WNN.md."
argument-hint: "[7d]"
allowed-tools: Bash(bash*), Bash(git*), Read(**), Write(**)
---

# /retro — Weekly retro

Produces a goal-anchored, PRD-shaped retro for the current project. Writes the full output to `<project>/.todos/retros/YYYY-WNN.md` and prints a 3-line pointer to the conversation.

---

## Step 1 — Resolve paths and invoke the aggregator

Resolve `$PLUGIN_DIR` as the parent of this file's `commands/` directory. Then:

```bash
main_repo=$(cd "$(git rev-parse --git-common-dir)/.." && pwd -P) || { echo "Not in a git repo."; exit 1; }
todos_dir="$main_repo/.todos"
window="${ARGUMENTS:-7d}"

JSON=$(bash "$PLUGIN_DIR/bin/retro-read.sh" "$window")
```

Parse `$JSON` — it contains everything needed (see `docs/specs/2026-04-20-retro-plan.md` for the output contract).

If the aggregator exits non-zero (e.g., unsupported window), relay its stderr and stop.

---

## Step 2 — First-run flow when no goal

If `goal.present` in the JSON is `false`:

Respond with exactly:

> No north star yet for **{project.name}**. The retro needs one before it can tell you whether the week moved you closer to the goal.
>
> In 1–2 sentences, what's the end state for this project? What does "done" look like a year from now?
>
> Also: what 3–5 measurable signals would tell you you're getting there?

Wait for the user to answer. Then draft `<project>/.todos/goal.md` with this exact structure:

```markdown
---
north_star: |
  {user's answer, reflowed to ~72-char lines}
success_metrics:
  - "{metric 1}"
  - "{metric 2}"
  - "{metric 3}"
updated: {YYYY-MM-DD today}
---

# Context

{optional context the user mentioned — constraints, non-goals, stakeholders}
```

Show the draft, ask for a y/n confirmation, write via the Write tool. Then tell the user:

> Goal saved to `.todos/goal.md`. Commit it and re-run `/retro` when ready.

**Stop.** Do not proceed to the retro — the first run is goal-setting only.

---

## Step 3 — Classify closed items against the north star

For each item in `closed_items`:

Read `item.title`, `item.outcome_snippet`, `item.learned`, and `item.work_log_markers`. Classify against `goal.north_star` as exactly one of:

- `advances-ns` — direct progress on the north star (or a load-bearing prerequisite for it)
- `tangent` — valid work, but not on the critical path for the stated goal
- `tech-debt` — maintenance, cleanup, infra, deployment, or tooling
- `unclear` — insufficient information or ambiguous alignment; prompts goal revision

Write a one-sentence rationale per item. Do not hedge — if it's unclear, mark it `unclear` and call that out. Do not fabricate an `advances-ns` to feel good — honesty is load-bearing.

---

## Step 4 — Pick a trajectory verdict

Count classifications. Rules of thumb (deviate if a single large item dominates):

- Majority `advances-ns` (>50% by count, or any `advances-ns` with a major scope/impact flag) → **closer**
- Majority `tangent` + `tech-debt` combined, no `advances-ns` → **drift**
- Mixed with at least one meaningful `advances-ns` → **same**
- All `unclear` → **same**, but open the output with a call for goal revision

The verdict comes with your one-sentence explanation grounding the call in 1–2 specific items.

---

## Step 5 — Distill learnings

Combine:

- All `item.learned[]` entries (from `## Learned` sections)
- All `item.work_log_markers` entries with `marker in {decision, surprise, learned}`

Dedupe near-duplicates. Keep original dates and IDs. Order by date ascending. Limit to 10 — if there are more, keep the 10 most substantive (skip trivial ones like "landed the branch").

---

## Step 6 — Write the retro file

Write to `{main_repo}/.todos/retros/{window.iso_week}.md` using the Write tool. If the directory doesn't exist, create it (the Write tool handles this). Use this template verbatim (substitute bracketed placeholders):

```markdown
# Retro — {project.name} — Week of {Monday of iso_week, YYYY-MM-DD}

## Ship Memo (for leadership)

{1 paragraph, 80–150 words. Quantified in business outcomes. No commit counts,
no lead times, no PRD jargon. Style: "This week we onboarded X, unblocking Y.
We are [still behind | on track | ahead] on [specific metric]." No
self-deprecation, no apology-farming.}

**One question for leadership:** {a single decision the user needs from a
stakeholder. Draw from open_items where blocked_by references external work, or
from Work Log markers that called out an ask. OMIT THIS LINE entirely if there
is no genuine question — fake questions are worse than no questions.}

## Trajectory: {closer | same | drift}

**North star:** {goal.north_star}
**Verdict rationale:** {one-sentence explanation referencing 1–2 specific items}

**Classification of {closed_items.length} closed items:**
- ✓ advances NS: {count} — {one-line summary across these items}
- → tangent:     {count} — {one-line summary}
- 🔧 tech-debt:  {count} — {one-line summary}
- ? unclear:     {count} — {"flag for goal revision" or omit the line if 0}

**Evidence:**
- #{id} [{classification}]: {title} — {one-sentence rationale or outcome snippet}
- ...

## Shipped this week ({closed_items.length})

| # | Title | Type | Quadrant | Lead time | Class |
|---|-------|------|----------|-----------|-------|
| {id} | {title} | {type} | {quadrant or "—"} | {lead_time_days}d | {symbol} |

## Learnings ({count} distilled)

- {date} #{id} @{marker or "learned"}: {text verbatim}
- ...

{If learning_capture.capture_rate < 0.5: add a line —
"Capture rate: {with_learned_section}/{closed_in_window}. Consider pausing at close
to write a one-liner — the retro is weaker without them."}

## Success metrics

| Metric | This week |
|--------|-----------|
| {metric} | unmeasured |

*V1 note: metrics show "unmeasured" until instrumentation lands. Make it honest,
not aspirational — "unmeasured" beats a made-up number.*

## Next week — open items ({open_items.length})

- #{id} [{quadrant}] {title}{" — blocked by #" + blocked_by if blocked_by else ""}{" — deadline " + deadline if deadline else ""}
- ...

**Proposed focus:** {one conversational sentence based on open-item quadrant mix.
Not prescriptive. E.g.: "Three q1 items with deadlines this week; #55 is the
critical-path blocker."}

---

*Integrity events this window: {integrity_events.length}{" (clean)" if 0 else ""}.*
*Learning capture rate: {with_learned_section}/{closed_in_window} ({capture_rate * 100 rounded}%).*
*Goal last updated: {goal.updated} ({staleness_days}d ago).*
*Generated: {ISO timestamp now} by /retro.*
```

Symbols for the classification column: `advances-ns` → `✓`, `tangent` → `→`, `tech-debt` → `🔧`, `unclear` → `?`.

---

## Step 7 — Respond in the conversation

Print exactly three lines (no preamble, no follow-up):

```
Retro written: .todos/retros/{iso_week}.md
Trajectory: {verdict} — {one-phrase reason}
{closed_items.length} closed, {learning_capture.with_learned_section} with learnings, {open_items.length} still open.
```

The file is the deliverable.

---

## Ship Memo framing rules (internal)

When drafting the Ship Memo in Step 6:

1. **Outcomes, not activity.** "3 clients onboarded" beats "4 items closed."
2. **Quantify or say "unmeasured".** No guesses. Unmeasured is honest; made-up numbers erode trust.
3. **80–150 words.** Anything longer signals the lede is buried.
4. **No jargon the CEO wouldn't use.** "Pipeline" is fine. "UPSERT" / "psycopg3 pipeline mode" is not.
5. **One question for leadership, max.** Skip the line entirely if there isn't a real one.
6. **No self-deprecation.** Problems are framed once as "still behind on X", not three times as apology.

---

## Important rules

- The ONLY file you write (in Step 6) is `.todos/retros/{iso_week}.md`. Do not create any other file during the retro flow.
- During the first-run flow (Step 2), the only file you write is `.todos/goal.md`.
- Overwrite an existing retro file for the same week without asking — retros are cheap to regenerate.
- If the aggregator rejected the window (anything other than `7d`), print its error verbatim and stop.
- If `closed_items` is empty, still write the retro, but the Ship Memo acknowledges "No items closed this week" and the trajectory verdict defaults to `same`.

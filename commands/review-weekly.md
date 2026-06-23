---
description: "Weekly Socratic review of life priorities, commitments, and energy allocation. Use --monthly for deeper monthly reflection with insight mining."
argument-hint: "[--monthly]"
allowed-tools: Read(**), Edit(**), Write(**), Glob(**), Grep(**), Bash(date*|ls*|wc*), AskUserQuestion
---

# /review-weekly — Socratic Review

Weekly review with coaching questions, or monthly reflection with insight mining. Synthesizes daily check-in data, todo project status, and life priorities into an actionable conversation.

---

## Shared: Activation Check

```
LIFE_CONFIG=~/.config/claude-life/config.yaml
```

1. Check if `$LIFE_CONFIG` exists (use Read tool).
2. If it does not exist: respond with "Life layer not set up yet. Run `/plan` to get started." **Stop.**
3. If it exists: proceed.

## Shared: Data Integrity

Before processing any YAML file, validate:
- If a file fails to parse (malformed YAML), **skip it** and warn: `"⚠ {filename} has a formatting issue — skipping."`
- If config references an area key with no matching file in `areas/`, warn: `"⚠ Priority '{key}' has no area file."`
- Never crash on bad data.

## Shared: Area Key Resolution

**Area key** = filename stem of files in `~/.config/claude-life/areas/`. Case-insensitive. Include `active` and `paused` areas for review context.

---

## Mode Selection

Check the user's argument:
- `--monthly` → **Monthly Mode**
- No argument → **Weekly Mode**

Additionally, if today is the last weekend (Saturday/Sunday) of the month and mode is weekly: after completing the weekly review, suggest: "This is the last weekend of the month. Run `/review-weekly --monthly` for a deeper look?" Do NOT auto-switch — user decides.

---

## Weekly Mode

### Step 1: Read data (batched parallel reads)

**Batch 1 (parallel):**
- Read `~/.config/claude-life/config.yaml`
- Read all `~/.config/claude-life/areas/*.yaml` (Glob + Read)

**Batch 2 (parallel):**
- Read all daily journal files for the current ISO week: `~/.config/claude-life/journal/daily/{YYYY-MM-DD}.md` for Monday through today. At most 7 files.
- Read `~/.config/claude-todo/projects.md` (if exists)
- Read previous week's summary: `~/.config/claude-life/journal/weekly/{prev-week YYYY-WNN}.md` (if exists — needed for trends and question dedup)

### Step 2: Compute weekly data

From the daily journal files, compute:

1. **Time allocation per area.** Sum durations from all parsed log entries across the week's dailies.
2. **Commitment hit rates.** Count `+CommitmentName` markers across the week's dailies. Compare against `target_count` from area YAML files.
3. **Tracked days.** Count of daily files that exist for this week.
4. **Priority gap.** Compare `config.yaml` priority ranking against actual time allocation ranking. Compute gap as percentage difference between stated priority position and actual allocation position.
5. **Qualitative tags.** Distill key themes from Notes lines across the week's dailies into 3-7 interpretable labels (e.g., `gym-improving`, `finance-research-stalled`, `energy-high`).

### Step 3: Generate review (front-load wins)

Present the review in this order — **wins first, gaps second:**

1. **Wins and progress.** What went well. Commitment improvements. Milestones approaching. Reference specific days/entries.
2. **Allocation numbers.** Time per area with trend vs. last week (UP/DOWN/STABLE/FLAT). Always show direction, not just absolute numbers.
3. **Priority gap analysis.** If stated priorities don't match actual allocation, name the gap concretely: "Finance (#1 priority) got 10% of time — ranked #3 in actual allocation."
4. **Weekly intent acknowledgment.** If `weekly_intent` was set in config, frame the review around it. Don't flag the intentional skew as a gap.

**Partial data:** If fewer than 7 daily files exist, acknowledge it: "{N} of 7 days tracked. Here's what we have." Never frame gaps as failure.

### Step 4: Socratic coaching (3-4 questions max)

#### Persona Selection

Select a **lead persona** based on the week's computed data. Use the `## Insight Data` YAML block from the previous week's summary if available for pre-computed values. If no previous weekly summary exists (first week), default to The Biographer.

| Condition | Lead persona |
|-----------|-------------|
| Default | **The Biographer** — warm, identity-focused, narrative |
| Priority gap > 40% | **The Product Manager** — ROI, allocation, bottleneck-hunting |
| Check-in rate < 50% (< 4 of 7 days) | **The Stoic** — agency, honest self-assessment, reclaiming momentum |
| `other` time > priority #1 time | **The Essentialist** — pruning, via negativa, what actually matters |

The lead persona shapes 2-3 coaching questions. One question from a secondary persona is allowed if the data warrants it.

**Read previous week's `## Coaching Q&A` section** to avoid repeating questions two weeks in a row.

#### Persona Question Banks

**The Biographer (Identity lens):**
- "You've hit {commitment} for {N} weeks straight. What does a person who does this consistently do next?"
- "If we wrote a chapter about this week, what would the title be?"
- "What was the one moment this week where you felt most like the version of yourself you're building toward?"

**The Product Manager (ROI lens):**
- "We have a priority gap in {area}. Is this a resource problem (no time) or a friction problem (the next task is too vague)?"
- "Which life area is your bottleneck right now? If we fixed that one, would everything else get easier?"
- "If this week were a sprint, would we ship the {current quarter} milestone, or are we experiencing feature creep?"

**The Stoic (Agency lens):**
- "You missed {commitment} {N} times. Was the obstacle external, or was it a choice? Either answer is fine — let's be honest."
- "What was the most challenging moment this week, and are you satisfied with how you responded?"
- "What's the 2-minute starter step we can commit to for tomorrow to reclaim momentum?"

**The Essentialist (Via Negativa lens):**
- "If we could keep only one commitment from this week and drop the rest, which one actually moves the needle?"
- "The {N}h in 'other' — was that intentional rest, or a shadow version of a priority we haven't named?"
- "What did you do this week out of habit that you'd be willing to stop entirely next week?"

#### Escalation Rules

- **Goal milestone approaching with thin progress:** Offer concrete options. "Block 2 hours this week, or push the milestone to {next month}?" Not "you're behind."
- **Same area at 0% for 3+ consecutive weeks:** Stop asking "what happened?" Instead: "Adjust the ranking to match reality, or make a concrete plan?"
- **Short answers are fine.** If the user gives a brief reply, acknowledge and move to Decisions. Don't nag for depth.

### Step 5: Capture decisions

After the coaching conversation, ask: "Any decisions or changes to make based on this? (priority changes, milestone adjustments, new plans — or 'nothing, we're good')"

Record decisions in the weekly summary.

### Step 6: Write weekly summary

Write (or overwrite) `~/.config/claude-life/journal/weekly/{YYYY-WNN}.md`:

```markdown
# Week {N} ({Mon date}-{Sun date})

## Weekly Intent
{None / or: "{area} — {reason}"}

## Trends (relative to last week)
- {area}: {hours}h — {UP|DOWN|STABLE|FLAT} from {last week hours}h ({commitment progress})
- ...

## vs. Priorities
{Priority gap analysis — which priorities matched allocation, which didn't}

## Wins
- {specific wins with concrete references}

## Coaching Q&A
{Questions asked and user's responses — preserved for next week's dedup}

## Decisions
{Any changes decided during the review}

## Insight Data
```yaml
week: {YYYY-WNN}
tracked_days: {N}
intent: { area: {area|null}, active: {true|false} }
hours: { {area}: {hours}, ... }
commitments: { {name}: [{hit}, {target}], ... }
priorities: [{area1}, {area2}, ...]
qualitative_tags: [{tag1}, {tag2}, ...]
```
```

The `## Insight Data` block is machine-readable YAML for insight mining. `qualitative_tags` are generated by distilling qualitative notes into interpretable labels.

---

## Monthly Mode

**Trigger:** User passes `--monthly`.

### Step 1: Read data (batched parallel reads)

**Batch 1 (parallel):**
- Read `~/.config/claude-life/config.yaml`
- Read all `~/.config/claude-life/areas/*.yaml`
- Read all `~/.config/claude-life/goals/*.md`

**Batch 2 (parallel):**
- Read at most 5 weekly summaries for the current month: `~/.config/claude-life/journal/weekly/` files whose ISO week's Monday falls in this month.
- Read `~/.config/claude-todo/projects.md` (if exists)
- Read previous month's reflection: `~/.config/claude-life/journal/monthly/{prev-month YYYY-MM}.md` (if exists)

**Do NOT read daily files.** Monthly mode reads weekly summaries only — progressive summarization.

### Step 2: Generate monthly view

1. **Time allocation trend across weeks.** Show how each area's hours moved week to week. Direction matters more than numbers.
2. **Commitment consistency trends.** Table format:

   ```
   | Commitment | W1 | W2 | W3 | W4 | Trend |
   |------------|----|----|----|----|-------|
   | Gym 3x/wk  | 1/3 | 2/3 | 2/3 | 3/3 | improving |
   ```

3. **Goal progress vs. timeline.** For each active goal: "{X}% through timeline, ~{Y}% through milestones. {Current month} milestone: {status}."
4. **Priority stack assessment.** Overall: did allocation match priorities this month?

### Step 3: Identity layer

- **4+ weeks consistent on a commitment:** Name the identity shift. "Gym seems established — this is part of your routine now, not something you push yourself to do."
- **Offer to graduate established habits:** "Increase the target, or redirect that discipline energy?"
- **Area lifecycle decisions:** "Social media paused for 2 months. Drop, keep paused, or reactivate?"
- **`other` decomposition:** If the same sub-category appears in `other` for 3+ consecutive weeks (check qualitative tags), suggest promoting it: "You've had 'errands' in 'other' for 4 weeks running. Create a 'maintenance' area, or keep it as 'other'?"
- **System cost awareness:** "Time spent on life management this month: ~{estimate from check-in + review count}. Worth the insight?"

### Step 4: Insight mining

**Activation condition:** Count files in `~/.config/claude-life/journal/weekly/`. If fewer than 8 weekly summaries exist, **skip insight mining entirely.** Say nothing about it — don't mention that insights aren't available yet.

If ≥8 weekly summaries exist, read the last 8 and run three tiers:

#### Tier 1: Structural patterns (rule-based)

Read the `## Insight Data` YAML blocks from the 8 weekly summaries. Look for system-level patterns:

- Does an area only get attention during weeks with explicit `weekly_intent`?
- Does commitment consistency drop in the second half of every month?
- Do areas with linked todo projects (via `.mappings.yaml`) get more time than areas without?

These are always actionable because they point to system design changes, not willpower.

#### Tier 2: Qualitative narrative mining (LLM-native)

Read the `**Qualitative:**` lines from weekly summaries and the `qualitative_tags` from Insight Data. Look for:

- **Decision stalls:** The same topic appearing across 3+ weeks without resolution. "You've mentioned 'researching index funds' for 5 weeks without committing."
- **Emotional precursors:** Frustration or energy patterns preceding allocation changes.
- **Emerging interests:** Repeated mentions of topics not captured by any goal or area.

#### Tier 3: Cross-area co-occurrence (raw counts)

Simple co-occurrence counts from the 8 weekly Insight Data blocks. **NOT correlation coefficients** — with 8 data points, statistical tests are dishonest.

Format: "In {X} of 8 weeks, {area A condition} coincided with {area B condition}."

Present raw counts. Frame as observation, not analysis: "I noticed X and Y tend to move together. Here are the weeks. Does this match your experience?"

**Never use the word "correlation"** or statistical terminology. Use "tends to coincide with," "moved together in X of Y weeks."

#### Surfacing rules

- **Maximum 1 insight per monthly reflection.** Quality over quantity.
- **Zero insights is always valid.** Surface nothing rather than something weak.
- Every surfaced insight MUST include:
  1. The raw evidence ("in 6 of 8 weeks...")
  2. One possible interpretation framed as a question
  3. One small experiment ("for the next 2 weeks, try X and see if Y follows")

### Step 5: Rebuild area-first views

For each active area, generate or overwrite `~/.config/claude-life/journal/areas/{area_key}.md`:

```markdown
# {area_key} — Area Timeline

Last rebuilt: {today YYYY-MM-DD}

## Summary
Total tracked: {sum hours}h across {N} weeks
Trend: {direction} from {earliest avg}h/wk to {recent avg}h/wk
Goal progress: "{goal title}" — {estimate}% complete

## Weekly History
- W{N}: {hours}h — {key activity or milestone}
- W{N-1}: {hours}h — {key activity}
...

## Qualitative Arc
{Distilled narrative from weekly qualitative summaries — the story of this area over time}
```

Read hours and qualitative data from weekly summaries only (not dailies).

### Step 6: Write monthly reflection

Write `~/.config/claude-life/journal/monthly/{YYYY-MM}.md`:

```markdown
# {Month Year}

## Time Allocation (monthly)
- {area}: {hours}h ({percent}%) — {commitment summary}
- ...

## Goal Progress
- **{area}: {goal title}** — {X}% through timeline, ~{Y}% through milestones. {Status}.
- ...

## Commitment Trends
| Commitment | W1 | W2 | W3 | W4 | Trend |
|------------|----|----|----|----|-------|
| ... | ... | ... | ... | ... | ... |

## Priority Stack Assessment
{Did allocation match priorities? Specific recommendations.}

## Identity Notes
{Established habits, areas needing attention, lifecycle decisions}

## Insight
{The one insight surfaced, if any. Or: "No patterns strong enough to surface this month."}

## Decisions
{Area lifecycle changes, priority re-ranking, goal adjustments made during this reflection}
```

---

## Review Variation

To prevent the review feeling repetitive over weeks:

- **Rotate question styles.** Don't always ask "what blocked X?" Try different angles on the same topic.
- **Every 3-4 weeks, zoom into one area deeply** instead of surveying all areas shallowly. Pick the area with the most interesting trend.
- **After the first month, incorporate relative comparisons:** "This was your best health week since you started tracking."
- **If weekly intent was set,** frame the entire review around it: "This was an intentional {area}-focus week. How'd it go?"
- **If weekly intent was NOT set but allocation was heavily skewed,** ask: "Was this week intentionally focused on {area}, or did it drift?" The answer either sets a retroactive intent (no guilt) or surfaces a genuine gap.

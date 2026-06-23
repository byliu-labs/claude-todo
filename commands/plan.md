---
description: Morning briefing with life priorities, commitments, and deadlines. First run activates life layer setup.
allowed-tools: Read(**), Edit(**), Write(**), Glob(**), Grep(**), Bash(mkdir*), AskUserQuestion
---

# /plan — Morning Briefing + Life Layer Setup

Daily morning command. Shows what to focus on today by synthesizing life priorities, commitments, and todo deadlines into a ≤10 line glance.

On first run (no `~/.config/claude-life/config.yaml`), enters interactive setup mode to configure life areas, commitments, and priorities.

---

## Shared: Activation Check

```
LIFE_CONFIG=~/.config/claude-life/config.yaml
LIFE_ACTIVE=false
```

1. Check if `$LIFE_CONFIG` exists (use Read tool — if it returns content, life layer is active).
2. If it exists: set `LIFE_ACTIVE=true`, proceed to **Morning Mode**.
3. If it does not exist: proceed to **Setup Mode**.

## Shared: Data Integrity

Before processing any YAML file, validate:
- If a file fails to parse (malformed YAML), **skip it** and warn the user: `"⚠ {filename} has a formatting issue — skipping. Fix it or run /plan to recreate."`
- If `config.yaml` references an area key that has no matching file in `areas/`, warn: `"⚠ Priority '{key}' has no area file. Run /plan to fix."`
- Never crash on bad data. Show what you can, warn about what you can't.

## Shared: Area Key Resolution

**Area key** = filename stem of files in `~/.config/claude-life/areas/` (e.g., `health.yaml` → key `health`). Case-insensitive matching. Used consistently in time entries, config, and cross-references.

Read all `*.yaml` files in `~/.config/claude-life/areas/` to build the active area key list. Only areas with `status: active` are included in the morning briefing. `paused` areas are recognized but excluded from commitments display. `archived` areas are ignored entirely.

---

## Setup Mode

**Trigger:** `~/.config/claude-life/config.yaml` does not exist.

### Step 1: Create directory structure

Run via Bash:
```bash
mkdir -p ~/.config/claude-life/{areas,goals,journal/{daily,weekly,monthly,areas}}
```

### Step 2: Walk through life areas

Use AskUserQuestion for each step. One question at a time, conversational.

1. **Ask about life domains.** "What areas of your life do you want to track? Common ones: health, finance, relationships, career, hobbies. You can add up to 7."

2. **For each area the user names:**
   - Ask: "Any regular commitments for {area}? (e.g., 'gym 3x per week', 'review portfolio monthly'). Say 'none' if it's just time tracking."
   - Ask: "Any specific goal for {area}? (e.g., 'run a half marathon by October'). Say 'none' to skip."
   - Write `~/.config/claude-life/areas/{key}.yaml`:
     ```yaml
     name: {user's name for the area}
     status: active
     created: {today YYYY-MM-DD}

     commitments:
       - name: {commitment name}
         frequency: {daily|weekly|monthly}
         target_count: {number}

     goals:
       - id: 1
         title: "{goal title}"
         file: goals/{key}-001.md
     ```
   - If the user provided a goal, write the goal file at `~/.config/claude-life/goals/{key}-001.md`:
     ```yaml
     ---
     id: 1
     area: {key}
     title: "{goal title}"
     status: active
     target_date: {ask user, or null}
     created: {today}
     ---

     # {goal title}

     ## Monthly milestones
     [TBD — flesh out during first /review-weekly]

     ## Success criteria
     [TBD]
     ```

3. **Soft cap check.** If the user names more than 7 areas: "You have {N} areas. More than 7 can dilute tracking — are you sure, or would some of these work better as sub-focuses within existing areas?" Let them override.

### Step 3: Set priority stack

Ask: "Rank these areas by priority for the current period. #1 is where you most want to grow. Areas not ranked are 'steady state.'"

Present the areas as a numbered list and let the user reorder.

### Step 4: Check-in anchor

Ask: "What's an existing daily ritual we can attach your evening check-in to? (e.g., 'after closing laptop', 'before bed', 'after dinner')"

### Step 5: Write config.yaml

Write `~/.config/claude-life/config.yaml`:
```yaml
current_priorities:
  period: {current quarter, e.g., 2026-Q1}
  ranked:
    - {area key 1}
    - {area key 2}
    # ... in user's ranked order

weekly_intent: null

check_in:
  anchor: "{user's anchor}"
```

### Step 6: Write empty .mappings.yaml

Write `~/.config/claude-life/.mappings.yaml`:
```yaml
# Categorization memory — maps natural language terms to area keys.
# Updated automatically from user corrections during /checkin.
# Format: term: area_key
```

### Step 7: Immediately run Morning Mode

After setup completes, run the Morning Mode flow below so the user sees their first briefing right away.

---

## Morning Mode

**Trigger:** `~/.config/claude-life/config.yaml` exists.

### Step 1: Read data (parallel where possible)

**Batch 1 (parallel):**
- Read `~/.config/claude-life/config.yaml`
- Read all `~/.config/claude-life/areas/*.yaml` (Glob for `*.yaml`, then Read each)

**Batch 2 (parallel):**
- Read `~/.config/claude-todo/projects.md` (if it exists — omit deadlines section if not)
- Read yesterday's daily journal: `~/.config/claude-life/journal/daily/{yesterday YYYY-MM-DD}.md` (if exists)

### Step 2: Check for recovery

Count consecutive days with daily journal files going backward from yesterday. If the most recent daily file is 3+ days ago:

**Recovery protocol:** "Welcome back. Want a catch-up summary of what you missed, or start fresh from today?"
- If catch-up: read the last few daily entries and summarize briefly.
- If fresh start: proceed normally, no guilt.

### Step 3: Auto-clear expired weekly intent

If `config.yaml` has `weekly_intent` set and `weekly_intent.expires` is before today: clear it by writing `weekly_intent: null` back to config.yaml via Edit.

### Step 4: Generate briefing

Output a **≤10 line** morning briefing. No questions. No conversation. A glance at the fridge whiteboard.

**Format:**
```
Day {streak count}. {day of week}, {date}.

Focus: {#1 priority area} — {one-line context from yesterday or goal}
Commitments: {today's active commitments, e.g., "Gym (2/3 this week)"}
{if weekly intent set: "Intent: {area} — {reason}"}
{if todo deadlines within 7 days: "Deadline: {project} — {item} (due {date})"}
{if yesterday had notable event: "Yesterday: {brief context}"}

Check-in anchor: {anchor from config}
```

**Rules:**
- Priority area named first. Commitments second. Deadlines third.
- Commitment progress counts are derived from this week's daily files (scan for `+CommitmentName` markers). If no dailies exist yet this week, show `(0/{target} this week)`.
- If yesterday had a milestone hit or streak milestone, one line acknowledging it.
- **No questions in morning mode.** If the user volunteers information (e.g., "this week is marathon week"), capture it as weekly intent — write to config.yaml. But don't ask.
- If no todo `projects.md` exists, simply omit the deadlines line.
- If no yesterday journal exists, omit the yesterday line.

### Pure todo mode (life layer not active)

If `~/.config/claude-life/config.yaml` does not exist AND the user has `~/.config/claude-todo/projects.md`:

Show a minimal briefing from todo data only:
```
{day of week}, {date}.

Active projects:
{summary from projects.md — next actions and nearest deadlines}
```

If neither config exists, inform the user: "No life layer or todo projects found. Run `/plan` to set up life tracking, or use `/todo add` in a project directory."

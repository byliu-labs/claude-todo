---
description: Evening check-in. Log what you did today in natural language. Claude parses, tracks commitments, and confirms in one message.
allowed-tools: Read(**), Edit(**), Write(**), Glob(**), Grep(**), Bash(date*), AskUserQuestion
---

# /checkin — Evening Pulse

Lowest-friction daily entry. User speaks naturally, Claude parses into structured data, confirms with one observation. Two messages max.

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
- If a file fails to parse (malformed YAML), **skip it** and warn: `"⚠ {filename} has a formatting issue — skipping. Fix manually or run /plan to recreate."`
- If config references an area key with no matching file in `areas/`, warn: `"⚠ Priority '{key}' has no area file."`
- Never crash on bad data.

## Shared: Area Key Resolution

**Area key** = filename stem of files in `~/.config/claude-life/areas/` (e.g., `health.yaml` → key `health`). Case-insensitive matching.

Read all `*.yaml` files in `~/.config/claude-life/areas/` to build the area key list. Include `active` and `paused` areas. `archived` areas are **not recognized** — if input matches an archived area key, warn: `"{key} is archived. Reactivate it first, or this goes to 'other'."`

Also read `~/.config/claude-life/.mappings.yaml` for previously resolved term→key mappings.

---

## Flow

### Step 1: Read context (parallel)

**Batch 1 (parallel):**
- Read `~/.config/claude-life/config.yaml`
- Read all `~/.config/claude-life/areas/*.yaml` (Glob + Read)
- Read `~/.config/claude-life/.mappings.yaml` (if exists)

**Batch 2:**
- Check if today's daily file exists: `~/.config/claude-life/journal/daily/{today YYYY-MM-DD}.md`

### Step 2: Prompt for input

- **If today's file exists:** Show the current summary from the file, then ask: "Anything to add?"
- **If no file for today:** "Quick check-in. What'd you do today?"

**Wait for user input.** This is the user's one message.

### Step 3: Parse input

Parse the user's natural language into structured data:

1. **Extract time entries.** Look for area references and durations. Match each against:
   - Known area keys (from `areas/*.yaml` filenames, case-insensitive)
   - `.mappings.yaml` entries (e.g., if `money stuff: finance` exists, "money stuff" → `finance`)
   - If no match found: assign to `other` with the raw term preserved in Notes

2. **Extract commitment hits.** If input implies a commitment was fulfilled (e.g., "went to gym" and health area has a "Gym" commitment), generate a `+CommitmentName` marker.

3. **Infer unmentioned commitments.** If the user says "just coded all day," infer that non-coding commitments were NOT hit today. Do NOT ask about them — infer from absence.

4. **Extract qualitative notes.** Observations, decisions, feelings mentioned in the input. These carry through to weekly summaries.

5. **Handle minimal input.** "Nothing today" or "rest day" → log a minimal entry with no time data. The streak still counts.

### Step 4: Write daily file

**If new file:** Create `~/.config/claude-life/journal/daily/{today YYYY-MM-DD}.md` with the full structure.

**If appending:** Append a new log entry block below existing entries, then regenerate the `## Summary` section by re-reading all log entries in the file.

#### Daily file structure

```markdown
# {YYYY-MM-DD} ({day abbrev})

## Summary
**Time:** {area}: {duration}, {area}: {duration}, ...
**Commitments:** [x] {hit} [_] {missed}
**Trend:** {one relative trend vs. this week so far}
**Qualitative:** {key observations from notes}

---

## Log

### {HH:MM}
> {raw user input verbatim}

{area}: {duration} ({activity}) | {area}: {duration} ({activity})
Commitments: +{CommitmentName}, +{CommitmentName}
Notes: {qualitative observations}
```

#### Parsed block contract

Each log entry MUST follow this exact template — it is the contract between `/checkin` (writer) and `/review-weekly` (reader):

```
### HH:MM
> [raw user input verbatim — always preserve in a blockquote]

area1: duration (activity) | area2: duration (activity) | ...
Commitments: +CommitmentName, +CommitmentName
Notes: [qualitative observations extracted from input]
```

- `Commitments:` line lists ONLY commitments hit in this entry, prefixed with `+`.
- If no commitments were hit, omit the `Commitments:` line entirely.
- If no qualitative notes, omit the `Notes:` line.
- The `other` key is always valid for uncategorized time.

#### Summary regeneration

After appending the log entry, **regenerate the entire `## Summary` section** by reading all log entries in the file:

- **Time:** Sum durations per area across all log entries for the day.
- **Commitments:** Scan all entries for `+CommitmentName` markers. Mark `[x]` for hit, `[_]` for not hit (compare against `areas/*.yaml` commitment lists for active areas).
- **Trend:** Compare this week's commitment counts so far against last week's. Derive from scanning this week's daily files for `+CommitmentName` markers. Show one relative trend (e.g., "Gym 2/3 this week, improving from 1/3 last week").
- **Qualitative:** Distill key observations from all Notes lines.

### Step 5: Handle corrections

If the user's input contains a correction ("that should be finance, not coding" / "count that as gym" / "remove the 30min errands"):

1. Update the daily file: append a correction note `[corrected → {area}]` next to the original entry. Regenerate summary.
2. If the correction implies a new mapping (e.g., "blog should be social-media"): append to `~/.config/claude-life/.mappings.yaml`:
   ```yaml
   blog: social-media
   ```

### Step 6: Handle weekly intent (if volunteered)

If the user says something like "this week is marathon week" or "focusing on health this week" — they're volunteering a weekly intent. Write to `config.yaml`:
```yaml
weekly_intent:
  area: health
  reason: "marathon week"
  expires: {next Monday YYYY-MM-DD}
```

Do NOT ask about weekly intent. Only capture it if volunteered.

### Step 7: Confirm (one message)

Respond with **one message only.** This is the second and final message in the interaction.

**Format:**
```
Day {streak count}. {one adaptive observation}.
```

**Adaptive observation rules (pick ONE):**
- **On track:** Brief confirmation with streak or commitment progress. "Gym 2/3 this week — need one more by Sunday."
- **Falling behind:** One concrete nudge. "Gym 1/3 with two days left — need both to hit target."
- **Milestone:** "Gym 3/3 — first time hitting target." Reference the trajectory.
- **Minimal day:** "Logged. Rest days are data too."
- **Never punish** a low-progress day. Neutral-to-warm tone.
- **Celebrate trends concretely**, not generically. Not "great job!" — instead reference the specific progress.

**Streak counting:** Count consecutive days with daily journal files, going backward from today. Any daily file counts — including minimal entries with no structured time data. The streak rewards showing up, not thoroughness.

**Do NOT:**
- Ask follow-up questions (unless the input is genuinely ambiguous — e.g., "did some stuff" with no areas identifiable at all)
- List everything that was logged (the user just said it)
- Provide a lengthy summary
- Ask about missed commitments

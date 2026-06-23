---
description: Manage project-level TODO items that persist across conversations. Claude scans context to add/update items intelligently.
argument-hint: "[list|add|review|refine #N]"
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

**`.todos/` should be gitignored.** Committing it causes ID collisions when Claude moves a new todo file into a feature worktree to commit unrelated code — the file becomes invisible to other sessions until the PR merges, and IDs get reallocated. The skill runs `bin/check-gitignore.sh` at every invocation and surfaces the one-time fix commands when the project hasn't done this yet.

### Worktree awareness: always write to the main repo

**CRITICAL:** TODOs are project-level, not branch-level. When working in a git worktree, always resolve the main repository root and write `.todos/` files there — never in the worktree directory.

```bash
# Detect if we're in a worktree
main_repo=$(git rev-parse --git-common-dir | sed 's|/\.git$||')
todos_dir="$main_repo/.todos"
```

**Why:** Worktrees are temporary workspaces that get removed after a PR merges. TODOs written inside a worktree are lost when `git worktree remove` runs. They also create duplicate files that collide when the branch merges to master. The `.todos/` folder in the main repo is the single source of truth.

### Global registry

`~/.config/claude-todo/projects.md` tracks all projects with active TODOs. Updated automatically by `/todo`. Format:

```markdown
# Active Projects

> Cross-project TODO registry. Auto-updated by `/todo`.

| Project | Path | Next action | Nearest deadline | Features | Q1 | Q2 | Blocked | Last updated |
|---------|------|-------------|------------------|----------|----|-----|---------|--------------|
| odyssey-ml | /path/to/odyssey | #3 Update methodology doc | 2026-03-15 | 1 | 1 | 2 | 1 | 2026-03-11 |
| nest | /path/to/nest | #12 Snapshot testing setup | — | 0 | 0 | 3 | 0 | 2026-03-11 |
```

- **Next action**: Title of the lowest-numbered pending, unblocked item.
- **Nearest deadline**: Earliest `deadline` among non-done items, or `—`.
- **Q1 / Q2**: Count of non-done items in each quadrant.
- **Blocked**: Count of items with `blocked_by` set.

Remove a row when a project has zero non-done items.
- **Features**: Count of non-done `type: feature` items.

## Plugin directory and preflight

The plugin ships scripts that this skill calls. Resolve the plugin root once per invocation — it's the parent of the directory containing this file (`commands/`).

```bash
# $PLUGIN_DIR = parent of this skill's commands/ directory
PLUGIN_DIR="/path/to/claude-todo"   # example; derive from the skill's load path
```

### Preflight: check that .todos/ is gitignored

Run at the start of every `/todo` invocation. If the script prints anything, relay the output verbatim to the user once, then continue. It is silent on healthy setups.

```bash
bash "$PLUGIN_DIR/bin/check-gitignore.sh"
```

### Telemetry

Telemetry is opt-in, gated by `~/.config/claude-todo/config.yaml` (`telemetry: local` by default). Every event is a single JSONL line appended to `$CLAUDE_TODO_HOME/telemetry/events.jsonl` (default `~/.config/claude-todo/telemetry/events.jsonl`). `log-event.sh` handles the schema, session id, project id, and worktree-escape detection — skill code only provides the payload.

Emit exactly these three events from `/todo`:

**After creating each item in `/todo add` (step 5 below):**

```bash
payload=$(printf '{"id":%s,"type":"%s","refined":%s,"parent":%s,"quadrant":%s,"has_deadline":%s}' \
  "$id" "$type" "$refined" "${parent:-null}" "${quadrant_json:-null}" "$has_deadline")
bash "$PLUGIN_DIR/bin/log-event.sh" item_created "$payload" --todos-dir "$main_repo/.todos"
```

**On every status transition (in Lifecycle management):**

```bash
payload=$(printf '{"id":%s,"from":"%s","to":"%s","days_since_created":%s,"days_since_prev_status":%s,"type":"%s","quadrant":%s}' \
  "$id" "$from" "$to" "$days_since_created" "${days_since_prev:-null}" "$type" "${quadrant_json:-null}")
bash "$PLUGIN_DIR/bin/log-event.sh" status_changed "$payload" --todos-dir "$main_repo/.todos"
```

`from`/`to` are the frontmatter status values. Both `days_since_*` are integers computed from `created` and the previous status change date if known (else `null`).

**Integrity alerts surfaced during `/todo list` (step 1 below):**

`rebuild-index.sh` already emits `id_collision_detected` on duplicate ids. To surface new integrity events to the user, read `events.jsonl` and compare against the project's `.last-viewed.json` marker:

```bash
python3 - "$PLUGIN_DIR" "$main_repo/.todos" <<'PY'
import json, os, sys, pathlib, time, subprocess
plugin_dir, todos_dir = sys.argv[1], sys.argv[2]
home = os.environ.get("CLAUDE_TODO_HOME", os.path.expanduser("~/.config/claude-todo"))
events_path = pathlib.Path(home) / "telemetry" / "events.jsonl"
todos_path = pathlib.Path(todos_dir)
marker = todos_path / ".last-viewed.json"
# Resolve THIS project's id so we only surface alerts for it, not events
# from other projects that happen to be newer than the per-project marker.
try:
    pid = subprocess.check_output(
        ["bash", f"{plugin_dir}/bin/project-id.sh", todos_dir],
        text=True).strip()
except Exception:
    pid = ""
last_ts = ""
if marker.exists():
    try: last_ts = json.loads(marker.read_text()).get("last_viewed_ts","")
    except Exception: pass
integrity = {"id_collision_detected","worktree_escape_detected",
             "filename_id_mismatch_detected","index_rebuild_failed"}
new = []
if events_path.exists():
    for line in events_path.read_text().splitlines():
        try: ev = json.loads(line)
        except Exception: continue
        if ev.get("event") not in integrity: continue
        if pid and ev.get("project_id") != pid: continue
        if ev.get("ts","") <= last_ts: continue
        new.append(ev)
if new:
    print("⚠ Integrity alerts since you last ran /todo:")
    for ev in new[-10:]:
        payload = {k: v for k, v in ev.items()
                   if k not in ("v","ts","event","project_id","session_id")
                   and not k.startswith("_")}
        print(f"  {ev['ts']} {ev['event']} " + json.dumps(payload))
# Write marker only when .todos/ exists — avoids first-run FileNotFoundError
# in fresh repos where /todo runs before any items have been created.
if todos_path.exists():
    marker.write_text(json.dumps({"last_viewed_ts": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}))
PY
```

`.last-viewed.json` lives in `.todos/` so it's project-local and gitignored with the rest.

### Learned capture (on close)

When a status transition writes `status: done`, after emitting `status_changed`, ask the user one question:

> #{ID} done. One-line takeaway? (Enter to skip)

If the user replies with non-empty text:

1. Append to the PRD's `## Learned` section (create the section at the bottom of the PRD body if it doesn't exist):

   ```markdown
   ## Learned

   - {YYYY-MM-DD}: {user's response verbatim}
   ```

2. Emit `learning_captured` telemetry:

   ```bash
   payload=$(printf '{"id":%s,"source":"learned_section","marker":null}' "$id")
   bash "$PLUGIN_DIR/bin/log-event.sh" learning_captured "$payload" --todos-dir "$main_repo/.todos"
   ```

If the user presses Enter / replies empty, skip silently. Do not probe, do not second-ask. The prompt is a nudge, not a gate. Takeaways feed `/retro`.

## Frontmatter schema

```yaml
---
id: 1
title: "Daily compliance: graceful alert on table-not-found"
type: todo            # todo | question | human | feature
status: pending       # pending | in-progress | done
created: 2026-03-04
done: null            # YYYY-MM-DD when completed, or null
blocked_by: null      # "human", item id (integer), or null
assignee: null        # name string or null
quadrant: q2          # q1 | q2 | q3 | q4 | null
deadline: null        # YYYY-MM-DD or null (hard deadlines only)
branch: null          # set at in-progress transition; git branch name
worktree: null        # absolute path to worktree if created, else null
pr_url: null          # PR URL once opened, or null
resolution: null      # completed | superseded | cancelled — only set when status: done
resolved_by: null     # item id of superseding item (resolution: superseded only)
parent: null          # integer (feature id) or null for standalone items
refined: false        # boolean — false means "backlog" (unrefined)
category: null        # short slug grouping items by topic (e.g. "infra", "outreach"), or null
---
```

### Field rules

- `id`: Sequential integer, never reused. Zero-padded in filenames: `001.md`.
- `type`:
  - `todo` — actionable by Claude or developer
  - `question` — unresolved design decision with concrete project impact
  - `human` — only a human can do this (manual testing, PM decisions, credential setup, external config)
  - `feature` — delivers user-visible value through one or more child todos. Cannot be nested (`parent` must be `null`). Status is derived from children except for the terminal `done` state, which requires explicit E2E test evidence (see Feature Lifecycle).
- `status`: Three states only — `pending`, `in-progress`, `done`.
  - **There is no `blocked` status.** Blocked items have `status: pending` with `blocked_by` set. The index generator uses `blocked_by` as a display hint to group them separately.
- `blocked_by`: Single value. `"human"` for human-gated items, an integer item id for dependency chains, or `null`. **Limitation**: only one blocker per item. If an item has multiple blockers, pick the primary one and note others in the PRD body.
- `assignee`: Name string for collaboration (works with git transport), or `null`.
- `quadrant`: Eisenhower classification. `q1` = urgent + important (do first), `q2` = important, not urgent (schedule and protect), `q3` = urgent, not important (timebox), `q4` = neither (eliminate). `null` = not yet classified.
- `deadline`: Hard external deadlines only (launches, contracts, compliance). Not aspirational targets.
- `branch`: Git branch name when work started. Set at `in-progress` transition. `null` until then.
- `worktree`: Absolute path to the git worktree if one was created for this item. `null` otherwise.
- `pr_url`: PR URL once a PR is opened. `null` until then.
- `resolution`: Closure reason. Only set when `status: done`. Values: `completed` (normal finish), `superseded` (another item replaces this), `cancelled` (dropped). `resolution: null` + `status: done` is equivalent to `resolution: completed` — backward compatible.
- `resolved_by`: Integer item id of the superseding item. Only set when `resolution: superseded`. `null` otherwise.
- `parent`: Integer referencing a `type: feature` item's id, or `null`. Only `type: todo` and `type: human` items may have a parent. `type: feature` and `type: question` always have `parent: null`. A child item can only belong to one feature.
- `refined`: Boolean. Items created by `/todo add` from a brief mention start `refined: false`. Items created with full PRD content (problem, expected behavior, test plan all filled) start `refined: true`. `/todo refine #N` transitions to `true`. **Reversible:** can return to `false` via PRD sync (significant scope drift), `/todo review` (stale detection), or user request. `/todo list` only suggests `refined: true` items as next work.
- `category`: Short slug (e.g. `infra`, `data-pipeline`, `outreach`) used to topically group items in the index. Only affects rendering of **Pending** and **Blocked** sections, which sub-group items by category alphabetically; items with `category: null` fall under `(uncategorized)`. **In Progress**, **Open Questions**, and **Done** stay flat regardless. Optional — projects without a category convention can leave every item `null` and the index renders as before. Categories are project-defined; there's no fixed taxonomy.

### Done semantics

`status: done` may only be set when there is completion evidence:

| Work type | Required evidence |
|-----------|-------------------|
| PR-backed work | PR confirmed merged (not just opened) |
| `type: human` | Explicit human confirmation in conversation |
| Local-only work | No PR and no remaining human steps |
| Partial implementation | Keep `in-progress` if Claude is still working; `pending` + `blocked_by` if blocked on a dependency |

### PR-backed items awaiting merge

When Claude opens a PR for a todo item, the item must stay `status: in-progress` with `pr_url` set. This is the signal that distinguishes "still coding" from "awaiting review/merge." Before stopping work, run the PRD sync. `## Current State` → `Remaining steps` must name what is being waited on:

```markdown
**Remaining steps:** PR #47 open — awaiting review and merge
```

Item stays `in-progress` until the PR is confirmed merged. At that point set `status: done`, `resolution: completed`, `done: YYYY-MM-DD`.

**Separate case — code complete but human config needed:** This is not an open-PR case. Use the discovery protocol to create a `type: human` item for the config step (e.g., Cloudflare setup). Then transition the current item to `pending` with `blocked_by` set to the new human item id. The current item is blocked, not in-progress.

Do not set `blocked_by: "human"` on open-PR items — `blocked_by` is for items that cannot start; an open PR is an item in-progress awaiting external completion, not a blocked item.

### Feature lifecycle

#### Derived status

Feature status is computed from children, never manually set to `in-progress`:

| Children state | Feature display status |
|---|---|
| No children yet | `pending` (unrefined feature = backlog) |
| All children `pending`, none blocked | `pending` |
| Any child `in-progress` | `in-progress` |
| Mix of `done` and `pending`, none `in-progress`, at least one unblocked | `pending` (work remains) |
| All non-done children are blocked (every remaining child has `blocked_by` set) | `blocked` |
| All children `done` | Ready for feature-level E2E |

**Blocked features:** A feature is blocked when it has remaining non-done children and every one of those remaining children has `blocked_by` set. This is the only way a feature enters the Blocked section of the index. If even one child is unblocked and pending, the feature is `pending`, not blocked.

#### Feature completion gate

A feature is NOT `done` when all children are `done`. A feature is `done` when:

1. All child items have `status: done`
2. The feature's integration/E2E test plan has been executed and passes
3. The acceptance criteria are verified

The `status` field on a feature is written only twice: `pending` at creation, `done` at completion. In between, the displayed status is derived.

#### Creating features

Features can be created via `/todo add` (if conversation reveals user-visible value) or `/todo review` (which may suggest converting a large standalone todo). `/todo feature` is NOT a separate command.

When creating a feature, verify it meets the **user-visible value test:**

- New capability users couldn't do before → feature
- Measurably faster/more reliable for users → feature
- Fewer errors/bugs users encounter → feature
- Internal refactor, code cleanup, tech debt → NOT a feature (it's a todo)
- Infrastructure/tooling change → NOT a feature (unless user-facing)

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

### Features

```markdown
# #10 — Auth system with login, signup, and password reset

**Goal:** [What user-visible value this delivers]

**Acceptance Criteria:**
- [ ] Users can create an account with email and password
- [ ] Users can log in and receive a session token
- [ ] Users can reset their password via email link
- [ ] Invalid credentials return clear error messages

**Integration/E2E Test Plan:**
- [End-to-end test descriptions covering the feature as a whole]
- [These test cross-cutting behavior, not individual todo items]

**Scope:** [In scope / NOT in scope]
```

Acceptance criteria are written from the user's perspective — observable outcomes, not implementation steps.

### Appended sections (lifecycle)

These sections are added to PRD bodies during implementation — not present at creation time.

#### Discovered During Implementation

```markdown
## Discovered During Implementation

- 2026-03-28: **Set up Cloudflare token** → created as #014 (type: human)
- 2026-03-28: **Should token rotation be automated?** → created as #015 (type: question)
```

Append a line each time a new item is discovered while implementing this PRD. Append-only — do not edit or remove existing lines. Each line is the forward link to the new item; the new PRD is the source of truth for that item.

Each new item's PRD must include: `> Discovered during implementation of: #NNN` (where NNN is this PRD's id).

#### Current State

```markdown
## Current State

**Last synced:** YYYY-MM-DD

**Approach taken:** [What was actually done, if different from Expected behavior]

**Deviations from plan:** [What changed and why — scope, approach, constraints discovered]

**Remaining steps:** [Anything not done — link to PRD numbers if captured as discoveries]
```

Overwrite on each sync — do not append. Omit entirely only when the item is `done` and implementation matched plan with nothing remaining — do not omit while the item is still `in-progress`.

**Remaining steps always appears** if the item is not complete, even if nothing else deviated.

#### Work Log

PRDs accumulate a `## Work Log` section during active work. Each entry starts with `- YYYY-MM-DD @who:` and is append-only — never edit or delete previous entries.

Three markers turn a regular entry into a machine-readable signal:

| Marker | When to use |
|--------|-------------|
| `@decision` | Made a design call with >1 option. Include the alternative you didn't pick. |
| `@surprise` | Observed behavior that differs from what you expected. |
| `@learned` | A generalizable lesson (distinct from `@surprise`, which is the observation that produces it). |

Syntax: place the marker before the colon, after the author handle.

```markdown
## Work Log

- 2026-04-18 @asher @decision: scoped to federal holidays only; regional deferred as #148.
- 2026-04-19 @asher @surprise: holidays.yaml already had 2027 data; expected a gap.
- 2026-04-19 @asher @learned: frontmatter-first scan is faster than per-file Python parse.
- 2026-04-19 @asher: landed PR #172.
```

**When to log:** at decision points, on surprising test/integration output, and when you realize something worth remembering next time. Not every keystroke — decisions, discoveries, completions. A week-long PRD with zero `@`-marker entries is a signal that reasoning wasn't captured; `/retro` surfaces this.

Markers are read by `/retro` and are the primary source of mid-session learnings (the `## Learned` section on close only captures the final takeaway).

### PRD rules

- Use `[TBD]` for missing sections — signals "clarify before implementing"
- Include file paths, function names, line references where stable
- Be detailed — these files are loaded on-demand, not always in context
- If a PRD exceeds ~40 lines, consider splitting into smaller items

## Index generation

The index is **never manually edited** and **never written by Claude directly**.

**MANDATORY: Always run `rebuild-index.sh` to regenerate the index.** The script lives in the plugin repo root — the parent directory of where this skill's `commands/` folder is. Locate it by looking up the path this skill was loaded from, go one level up, and run:

```bash
bash /path/to/plugin-repo/rebuild-index.sh /path/to/project/.todos
```

Claude must **never** hand-write or hand-edit `index.md`. The script is the single source of truth for index format. Writing it manually produces formatting drift (wrong ordering, missing sections, collapsed Done lists, unquoted blocker values, etc.).

### Index format

```markdown
# Project TODO

> Auto-generated from `.todos/*.md` frontmatter. Do not edit manually.

## In Progress

### #10 — Auth System (3/5 done) [q1]
- [x] #11 — Login endpoint (done: 2026-03-20)
- [-] #12 — Signup flow (in-progress) @alice
- [ ] #13 — Password reset
- [ ] #14 — Session management
- [ ] #15 — OAuth integration [blocked: 12]

- [-] #20 — Fix CSV export bug [q1]

## Pending

### #25 — Payment Integration (0/3 done) [q2]
- [ ] #26 — Stripe webhook handler
- [ ] #27 — Invoice generation
- [ ] #28 — Refund flow [blocked: human]

- [ ] #30 — Update API docs [q3]

## Blocked

### #40 — Email Notifications (0/2 done) [q2]
- [ ] #41 — Set up SendGrid credentials [blocked: human]
- [ ] #42 — Implement notification templates [blocked: 41]

## Backlog (unrefined)

- [ ] #35 — Mobile push notifications
- [ ] #36 — Multi-language support
- [ ] #37 — Dark mode

## Open Questions

- ? #50 — Should we support SSO for v1?

## Done

### #5 — User Onboarding Flow (completed)
- [x] #6 — Welcome email (done: 2026-03-10)
- [x] #7 — Profile setup wizard (done: 2026-03-12)
- [x] #8 — Tutorial overlay (done: 2026-03-15)

- [x] #9 — Fix timezone bug (done: 2026-03-18)
- [~] #3 — Legacy auth endpoint (superseded by #10, done: 2026-03-28)
- [-] #4 — Migrate deprecated config (cancelled, done: 2026-03-20)
```

Grouping logic:

1. **Features** are placed in the section matching their derived status (see Feature lifecycle). Children are nested under the feature regardless of individual child status — you see all children together.
2. **Standalone items** (`parent: null`) follow existing grouping rules below.
3. **New section: Backlog (unrefined)** — items with `refined: false` that are `status: pending` and not blocked. Appears after Blocked, before Open Questions.
4. **Feature progress indicator:** `(3/5 done)` suffix shows child completion count.
5. **Children within a feature** are ordered: in-progress first, then pending, then blocked, then done. This puts actionable items at the top.

Standalone grouping (unchanged from v2):
- `status: in-progress` → In Progress
- `status: pending` + `blocked_by: null` + `refined: true` → Pending
- `status: pending` + `blocked_by` set → Blocked (display the blocker)
- `status: pending` + `refined: false` → Backlog (unrefined)
- `type: question` + not done → Open Questions
- `status: done` + `resolution: null` or `resolution: completed` → Done, marker `[x]`
- `status: done` + `resolution: superseded` → Done, marker `[~]`, append `(superseded by #NNN)` suffix
- `status: done` + `resolution: cancelled` → Done, marker `[-]`, append `(cancelled)` suffix (same symbol as In Progress — distinguished by section: Done vs. In Progress)

Section ordering:
1. In Progress — features with any in-progress child + standalone in-progress items
2. Pending — refined, unblocked features and standalones
3. Blocked — items/features where all paths are blocked
4. Backlog (unrefined) — `refined: false` items
5. Open Questions — `type: question`, not done
6. Done — completed/superseded/cancelled

Suffix tags: show `@assignee` if set, `[qN]` if set, `(due: date)` if set, `[blocked: X]` if blocked.

### Token cost

Reading the index: ~20-50 tokens. Reading one PRD: ~100-200 tokens. Claude loads PRDs on-demand only when working on an item.

## The boil-the-lake gate (run before creating any `type: todo`)

**Before filing ANY actionable todo — whether via `/todo add` or the discovery
protocol during implementation — STOP and ask: "Why don't I just do this RIGHT
NOW?"**

A todo is a deferral, and deferral is not free: a separate PR, a separate
context rebuild, a backlog entry that competes with newer work, and a rough edge
the user feels in the meantime. For small work the deferral cost usually exceeds
the cost of just doing it.

Apply the gate to every candidate `type: todo`:

1. **Estimate the effort.** If it's roughly **< 1 hour and scoped**, the default
   is **DO IT NOW** — fold it into the current PR or an immediate follow-up PR —
   not file it.
2. **Only file instead of doing when at least one is true:**
   - It meaningfully expands the current PR's diff/scope (it's a different feature).
   - It touches a genuinely different *surface* than the current work (e.g. CI
     infra, a new credential, a deploy cron, a DB migration) — "a different
     file" does **not** count.
   - It depends on infrastructure / telemetry / data that does not exist yet.
   - The user explicitly asked to defer it.
3. **If you file it anyway, state the reason in one line** naming which condition
   above applies. "Filed #N — needs a prod-DSN CI secret that doesn't exist yet"
   is legitimate. "Filed #N to keep this PR small" / "deferred from review" /
   "v1.1 polish" is the laziness this gate exists to stop — do it now instead.

This is the mechanical form of the `feedback_no_small_deferrals` rule ("boil the
lake — when finishing, finish all of it"). The recurring failure mode is carving
a 30-minute item out of a shipping PR as "deferred from review / v1.1" when it
should just have been done in the same PR. Don't.

## Behavior based on arguments

### No arguments or "list" → Rebuild index + display

0. **Preflight**: run `bash "$PLUGIN_DIR/bin/check-gitignore.sh"` and relay any output. Then run the integrity alert block from the "Plugin directory and preflight" section to surface new `id_collision_detected` / `worktree_escape_detected` events since `.last-viewed.json`.
1. Scan all `.todos/[0-9][0-9][0-9].md` frontmatter.
2. **Auto-update**: Scan conversation for items completed or started this session. For each item that was in-progress this session: run the PRD sync protocol (see Lifecycle management) before changing its status. Then update frontmatter in relevant PRD files.
3. **GitHub PR reconciliation** (silent catch-all): For any item with `branch` set and `status != done`, check whether that branch's PR has been merged on GitHub. Run a single batch call:
   ```bash
   gh pr list --state merged --limit 50 --json number,headRefName,mergedAt,url
   ```
   Match results against items by `headRefName == branch`. For each match: set `status: done`, `done: <mergedAt date as YYYY-MM-DD>`, `pr_url: <url>` (if not already set), `resolution: completed`. No user confirmation needed — this is a bookkeeping sync, not a decision. If any items were auto-closed this way, report them at the top of the list output: `Auto-closed from merged PRs: #86 (PR #101), #87 (PR #102)`. Skip silently if `gh` is unavailable, not authenticated, or the repo has no GitHub remote.
4. **Feature-aware auto-update**: If a child todo is marked done and it's the last child of a feature, prompt: "All children of feature #N are done. Run E2E tests and mark feature complete?" Do not auto-complete features — always require E2E verification.
5. **Rebuild index** from frontmatter (see Index generation for feature-nested format).
6. Display grouped items.
7. **Prioritization hints** (scored):
   - Score each pending, unblocked, `refined: true` item:

   | Signal | Score |
   |--------|-------|
   | Quadrant: Q1 | +4 |
   | Quadrant: Q2 | +3 |
   | Quadrant: Q3 | +2 |
   | Quadrant: null | +1 |
   | Quadrant: Q4 | +0 |
   | Deadline within 7 days | +3 |
   | Completing this finishes a feature | +2 |
   | Completing this unblocks N items | +1 per item (transitive) |
   | Pending > 14 days | +1 |

   - Display format:

   ```
   Suggested next:
     #15 — OAuth integration [q1]
       Completing this finishes feature #10 (4/5 done)
       Unblocks #22 (API rate limiting depends on auth)

     Also consider:
     #20 — Fix CSV export bug [q1] (deadline in 5 days)
     #13 — Password reset (#10, 3/5 done) [q2]
   ```

   - Show top suggestion with reasoning, plus up to 2 runners-up. Only suggest `refined: true` items.
8. If open questions have enough context to resolve, propose converting or closing.
9. If done items > 2 weeks old, suggest `/todo review` (which includes cleanup).
10. **Update global registry**.

### "add" → Scan context and propose new items

**Run the boil-the-lake gate (above) on every candidate first.** If a candidate
is a `type: todo` that's roughly < 1h and scoped, do it now (or fold it into the
current PR) instead of proposing it as a todo. Only propose the ones that pass
the gate's defer criteria.

1. Read index (rebuild if stale; create `.todos/` dir if missing).
2. Scan conversation for: actionable TODOs, open questions, human action items, **and items that deliver user-visible value** (potential features).
3. Draft items with frontmatter + PRD body:
   - **Feature detection:** If a proposed item describes a user-facing capability (new feature, measurably better performance, fewer user-facing errors), propose it as `type: feature` with the feature PRD template. Apply the user-visible value test (see Feature lifecycle). Internal refactors, code cleanup, and infrastructure work are NOT features.
   - **Parent assignment:** If a proposed todo clearly relates to an existing feature, propose `parent: <feature-id>`. User can override to standalone or a different parent.
   - **Refined status:** Items added from brief mentions start `refined: false`. Items added with enough detail to fill the PRD template start `refined: true`. When in doubt, default to `refined: false` — refinement is cheap.
   - **Propose a quadrant** for each. Ask about deadline only if there's reason to believe one exists.
4. **Ask user to confirm** (AskUserQuestion, multiSelect). Present categories separately. Include proposed quadrant and `type` so user can override.
5. Create `.todos/NNN.md` for each confirmed item. **Emit `item_created`** per the telemetry block in "Plugin directory and preflight" — one event per item.
6. Rebuild index. Update global registry.

### "clean" → Redirected to review

If user types `/todo clean`, respond: "Cleanup is now part of `/todo review`, which also checks for refinement opportunities, overlaps, and stale items. Running review now." Then execute the review behavior below.

### "review" → Systematic grooming

Reads all items and produces a prioritized list of suggestions. Non-destructive — every suggestion requires user confirmation before action.

1. Scan all `.todos/[0-9][0-9][0-9].md` frontmatter AND bodies (review reads bodies, unlike list which reads frontmatter only).
2. Run all checks, collect findings:

| # | Check | Condition | Suggestion |
|---|-------|-----------|------------|
| 1 | **Blocked with resolved blocker** | `blocked_by` points to a `done` item | "Unblock #8 — blocker #7 is done" |
| 2 | **Near-complete features** | Feature with 1-2 non-done children remaining | "Feature #10 is 4/5 done — prioritize #15 to close it out" |
| 3 | **Unrefined items** | `refined: false`, created > 3 days ago | "These need refinement: #35, #36" |
| 4 | **Large standalone todos** | No parent, body suggests multi-step work delivering user-visible value | "Consider converting #20 to a feature" |
| 5 | **Stale pending items** | `refined: true`, `pending` for > 14 days, no progress | "#8 has been pending 14 days" |
| 6 | **Refined but stale** | `refined: true` but has `[TBD]` markers, pending > 30 days, or has open unresolved discoveries | "These may need re-refinement: #14, #22" → suggest setting `refined: false` |
| 7 | **Potential overlaps** | Items sharing primary targets or near-identical scope | "#3 and #11 look related" (triggers overlap handling protocol) |
| 8 | **Orphan todos** | Standalone todo whose scope fits an existing feature | "Consider linking #20 to feature #10" |
| 9 | **Stale done items (cleanup)** | `done` date > 2 weeks, not referenced by non-done items | "Eligible for cleanup: #3, #6" |

3. Present findings grouped by category, most actionable first: unblock → near-complete → unrefined → large standalones → stale → refined-stale → overlaps → orphans → cleanup.
4. For each finding, propose a concrete action.
5. User confirms which actions to take (AskUserQuestion). Claude executes confirmed actions only.
6. Rebuild index and update global registry after all changes.

**Cleanup rules** (check #9): Only remove done items > 2 weeks old AND not referenced by any non-done item's PRD. All `resolution` values eligible equally (`completed`, `superseded`, `cancelled`). Report what was cleared and what was kept.

### "refine #N" → Deep-dive on a single item

Makes an item actionable by filling gaps and, for features, breaking them into child todos.

**Parse:** Extract the item number N from the argument. Read `.todos/NNN.md`.

**If `type: feature`:**

1. Read the feature PRD.
2. Scan codebase for relevant files, modules, architecture.
3. Fill `[TBD]` sections:
   - Goal (if missing)
   - Acceptance criteria — written from user perspective, observable outcomes
   - Integration/E2E test plan — tests that cover the feature end-to-end
   - Scope boundaries
4. Propose child items — each independently implementable and testable.
   - Each child gets `parent: N` and `refined: true`.
   - Use `type: todo` for implementation work, `type: human` for manual prerequisites (credentials, external config, dashboard setup).
   - Each child has a full PRD body matching its type template.
5. Present all proposals (PRD edits + child items) for user confirmation via `AskUserQuestion`.
6. Create confirmed items. Set `refined: true` on the feature. Write PRD edits only after confirmation.
7. Rebuild index and update global registry.

**If `type: todo` (standalone):**

1. Read the PRD.
2. Scan codebase for relevant files, modules, architecture.
3. Draft proposed edits: fill `[TBD]` sections with codebase-informed detail.
4. If the item describes user-visible value AND looks like multi-step work:
   - Suggest converting to `type: feature` with child items (todo or human).
   - Apply the user-visible value test. Do NOT suggest feature conversion for internal/technical work.
5. Present proposed PRD edits for user confirmation via `AskUserQuestion`.
6. Write confirmed edits. Set `refined: true`.

**If `type: question`:**

1. Read the question PRD.
2. Scan codebase and conversation for context that might resolve it.
3. Draft proposed changes:
   - If enough information exists, propose resolution (convert to todo or close with decision).
   - If not, propose filling in missing context to make the question more specific.
4. Present proposed changes for user confirmation via `AskUserQuestion`.
5. Write confirmed changes.

**Key rule:** Refine always proposes, never auto-writes. User confirms before any PRD is modified or item created. This applies to ALL types — features, todos, and questions alike.

## Lifecycle management

Claude manages status **proactively during normal work**:

**On every status change below, emit a `status_changed` telemetry event** per the template in "Plugin directory and preflight". Fire it after writing the frontmatter, with `from`/`to` matching the old and new `status` values.

- **Starting work**: Read `.todos/NNN.md`, update to `status: in-progress`. Set `branch` to current git branch and `worktree` to the absolute worktree path (if work is in a worktree; otherwise `null`).
- **Before stopping work** (before any status transition, context switch, or session end): Run the PRD sync protocol (see below).
- **Finishing work**: May only set `status: done` when completion evidence exists (see Done semantics). Set `done: YYYY-MM-DD`. Set `resolution: completed` if closing normally; `resolution: superseded` or `cancelled` only via confirmed user choice (see Overlap handling). Never delete the file.
- **Opening a PR**: Set `pr_url`. Item stays `in-progress`. Update `## Current State` → `Remaining steps` to name what is being waited on (e.g., `PR #47 open — awaiting review and merge`).
- **Discovering follow-up**: Mandatory three-step protocol (see below). Not optional.
- **Natural break points**: After completing work, check for `type: human` items. Remind the user if any are relevant.
- **Unblocking**: When a human confirms completion, set their item to `status: done`. Check if other items have `blocked_by` pointing to it — clear their `blocked_by` to `null`.
- **Suspected overlap with another item**: Never act autonomously. Use the overlap handling protocol (see below).

### PRD sync protocol

**Trigger:** Before Claude stops active work on an item — before any status transition, context switch, or command end.

If implementation matched plan, the item is `status: done`, and nothing remains: no action needed. This exemption does not apply if `pr_url` is set — always run the sync before any status transition on open-PR items.

Otherwise, update (or create) `## Current State` in the PRD body:

```markdown
## Current State

**Last synced:** YYYY-MM-DD

**Approach taken:** [What was actually done, if different from Expected behavior]

**Deviations from plan:** [What changed and why — scope, approach, constraints discovered]

**Remaining steps:** [Anything not done — link to PRD numbers if captured as discoveries]
```

- Overwrite on each sync, do not append.
- `Remaining steps` always appears if the item is not yet complete.
- Branch and PR stay canonical in frontmatter. The body may show a human-readable summary, but the machine source is `branch`, `worktree`, `pr_url`.
- If the deviation reflects the new accepted plan, update `Expected behavior` or `Scope` to match that accepted understanding. Do not rewrite the spec to rationalize a questionable implementation — if in doubt, leave the original intact and note the deviation.

**De-refinement on significant drift:** When the sync detects significant scope drift or new unresolved unknowns, set `refined: false` on the item. "Significant" means: the `Deviations from plan` section describes a fundamentally different approach, `Remaining steps` names work not in the original scope, or new `[TBD]` markers were added. Minor deviations (different implementation detail, same outcome) do not trigger de-refinement.

### Discovery protocol

If Claude identifies additional human work, implementation work, or an unresolved decision during execution, all three steps are **mandatory**:

**Step 1 — Append to the source PRD:**

```markdown
## Discovered During Implementation

- YYYY-MM-DD: **[Item title]** → created as #NNN (type: human | todo | question)
```

Append-only. The new PRD is the source of truth; this entry is the forward link.

**Step 2 — Create new PRD(s):**

**First run the boil-the-lake gate (see top of this skill).** A "discovered
follow-up" found mid-implementation is the #1 source of lazy deferrals: it's
usually < 1h, scoped, and on the *same* surface you're already editing — which
means the gate says do it NOW, in the current PR, not file it. Only create a
`type: todo` here when it genuinely meets a defer criterion (different surface,
missing infra, or user asked to defer) — and say which one in the
`## Discovered During Implementation` line.

- Use `type: human` for human-required actions (external config, credentials, infrastructure).
- Use `type: todo` for follow-up implementation work.
- Use `type: question` for unresolved decisions.
- Include a backlink in the new PRD body: `> Discovered during implementation of: #NNN`
- **Do not over-block:** set `blocked_by: <source-item-id>` only if the new item genuinely cannot start until the source item is done. Many discoveries are merely related.
- **Parent inheritance:** If the source item (the one being implemented) has `parent: N`, the new item defaults to `parent: N` (same feature). Propose this default in the confirmation: "Discovered **[title]** — adding to feature #N. Override? [y/N]". If the discovered item is clearly unrelated to the feature's scope, propose `parent: null` instead.

**Step 3 — Rebuild index and update global registry** before ending the session if any new non-done item was created.

**What counts as a discovery:**
- A human action required before the feature works end-to-end
- A dependency discovered mid-implementation not in the original scope
- An assumption that should be tracked as an explicit decision
- Any follow-up work that would otherwise be lost on context switch

**Refined status for discoveries:** Discovered items start `refined: false` unless the discovery includes enough detail to fill the PRD template. Discoveries are often rough observations that need refinement before they're actionable.

### Overlap handling

Claude may never change an item to a terminal state based on perceived overlap. Overlap is a hypothesis, not a fact.

**When Claude suspects overlap:**

1. Stop. Do not change any status.
2. Present via `AskUserQuestion`:

```
#003 and #011 look related:
  #003: [title]
  #011: [title]

Are these:
  A. Independent — keep both
  B. #011 supersedes #003 — mark #003 as superseded (sets resolution: superseded, resolved_by: 11)
  C. #003 is a subtask/blocker for #011 — sets blocked_by: 3 on #011 (meaning #011 waits for #003)
  D. Something else — I'll follow your lead
```

3. Act only on the confirmed choice.

**On blocked_by direction:** if #003 must finish before #011 can proceed, set `blocked_by: 3` on #011 (the parent is blocked by the subtask). Reason about direction before proposing.

**Triggers:** two items share the same primary target (file, function, external service), or one item's scope appears to fully contain another's, or a new item being drafted sounds nearly identical to an existing pending item.

**Does not trigger:** items that touch the same area but have distinct goals, or partial overlap.

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

## Backward compatibility (v2 → v3)

v3 changes are additive. No automated migration needed:

- **Missing `parent` field:** defaults to `null` (standalone item). All existing items are standalone.
- **Missing `refined` field:** defaults to `true` for display stability — existing items stay in Pending, not Backlog. `/todo review` check #6 ("refined but stale") catches legacy items that are actually vague or over-broad and suggests de-refining them.
- **`type: feature`** is new — no existing items have it.
- **`/todo clean`** is redirected to `/todo review`. If user types `clean`, review runs automatically.
- **Global registry** gains a `Features` column. Existing rows get `0` until features are created.

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

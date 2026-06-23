#!/usr/bin/env bash
# Telemetry test harness. Runs in a disposable $CLAUDE_TODO_HOME.
# Usage: bash test/run-tests.sh

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

export CLAUDE_TODO_HOME="$TMPROOT/claude-todo"
mkdir -p "$CLAUDE_TODO_HOME"

pass=0
fail=0

assert_eq() {
  local label="$1" want="$2" got="$3"
  if [ "$want" = "$got" ]; then
    echo "  ok  $label"
    pass=$((pass + 1))
  else
    echo "  FAIL $label"
    echo "       want: $want"
    echo "       got:  $got"
    fail=$((fail + 1))
  fi
}

assert_match() {
  local label="$1" pattern="$2" got="$3"
  if printf '%s' "$got" | grep -Eq "$pattern"; then
    echo "  ok  $label"
    pass=$((pass + 1))
  else
    echo "  FAIL $label"
    echo "       pattern: $pattern"
    echo "       got:     $got"
    fail=$((fail + 1))
  fi
}

# ---------- project-id.sh ----------

echo "test: project-id.sh returns 12-hex for git remote"
repo1="$TMPROOT/repo1"
mkdir -p "$repo1"
git -C "$repo1" init -q
git -C "$repo1" remote add origin https://example.com/a/b.git
id1=$(cd "$repo1" && bash "$PLUGIN_DIR/bin/project-id.sh")
assert_match "project-id length/charset" '^[0-9a-f]{12}$' "$id1"

echo "test: project-id.sh is stable across invocations"
id1b=$(cd "$repo1" && bash "$PLUGIN_DIR/bin/project-id.sh")
assert_eq "project-id stability" "$id1" "$id1b"

echo "test: project-id.sh differs for different remotes"
repo2="$TMPROOT/repo2"
mkdir -p "$repo2"
git -C "$repo2" init -q
git -C "$repo2" remote add origin https://example.com/x/y.git
id2=$(cd "$repo2" && bash "$PLUGIN_DIR/bin/project-id.sh")
if [ "$id1" = "$id2" ]; then
  echo "  FAIL project-id differentiation (both $id1)"
  fail=$((fail + 1))
else
  echo "  ok  project-id differentiation"
  pass=$((pass + 1))
fi

echo "test: project-id.sh falls back to path when no remote"
repo3="$TMPROOT/repo3"
mkdir -p "$repo3"
git -C "$repo3" init -q
id3=$(cd "$repo3" && bash "$PLUGIN_DIR/bin/project-id.sh")
assert_match "fallback id charset" '^[0-9a-f]{12}$' "$id3"

echo "test: projects.json is populated"
proj_json="$CLAUDE_TODO_HOME/telemetry/projects.json"
if [ -f "$proj_json" ]; then
  assert_match "projects.json has id1" "$id1" "$(cat "$proj_json")"
else
  echo "  FAIL projects.json missing at $proj_json"
  fail=$((fail + 1))
fi

# ---------- log-event.sh basic emission ----------

echo "test: log-event.sh writes one JSONL line on local tier"
events="$CLAUDE_TODO_HOME/telemetry/events.jsonl"
rm -f "$events"
cd "$repo1"
bash "$PLUGIN_DIR/bin/log-event.sh" item_created \
  '{"id":42,"type":"task","refined":true,"parent":null,"quadrant":null,"has_deadline":false}' \
  --todos-dir "$repo1/.todos"
line_count=$(wc -l < "$events" | tr -d ' ')
assert_eq "one event line" "1" "$line_count"

echo "test: event has required fields"
line=$(tail -1 "$events")
assert_match "has v field" '"v":1' "$line"
assert_match "has ts field" '"ts":"[0-9]{4}-[0-9]{2}-[0-9]{2}T' "$line"
assert_match "has event field" '"event":"item_created"' "$line"
assert_match "has project_id" "\"project_id\":\"$id1\"" "$line"
assert_match "has session_id" '"session_id":"[0-9a-f]{8}-[0-9]+"' "$line"
assert_match "has id payload field" '"id":42' "$line"

echo "test: off tier writes nothing"
printf 'telemetry: off\n' > "$CLAUDE_TODO_HOME/config.yaml"
rm -f "$events"
bash "$PLUGIN_DIR/bin/log-event.sh" item_created '{"id":99}' --todos-dir "$repo1/.todos"
assert_eq "no events on off tier" "" "$(cat "$events" 2>/dev/null || true)"
printf 'telemetry: local\n' > "$CLAUDE_TODO_HOME/config.yaml"

# ---------- log-event.sh worktree escape ----------

echo "test: writing to main-repo .todos does NOT emit escape"
rm -f "$events"
mkdir -p "$repo1/.todos"
cd "$repo1"
bash "$PLUGIN_DIR/bin/log-event.sh" item_created '{"id":1}' --todos-dir "$repo1/.todos"
assert_eq "no escape on main repo" "0" "$(grep -c worktree_escape_detected "$events" || true)"

echo "test: writing to a different dir emits escape BEFORE the original event"
rm -f "$events"
mkdir -p "$TMPROOT/escaped/.todos"
cd "$repo1"
bash "$PLUGIN_DIR/bin/log-event.sh" item_created '{"id":2}' --todos-dir "$TMPROOT/escaped/.todos"
assert_eq "escape line count" "1" "$(grep -c worktree_escape_detected "$events" || true)"
first_line=$(head -1 "$events")
assert_match "escape first" '"event":"worktree_escape_detected"' "$first_line"
second_line=$(tail -1 "$events")
assert_match "original event second" '"event":"item_created"' "$second_line"

echo "test: escape payload carries local-only fields"
assert_match "escape has _resolved" '"_resolved_todos_dir":' "$first_line"
assert_match "escape has _expected" '"_expected_main_repo_dir":' "$first_line"
assert_match "escape has _cwd" '"_cwd":' "$first_line"

echo "test: log-event.sh from OUTSIDE the repo uses --todos-dir for project_id"
# Regression: rebuild-index.sh is documented to be callable with an explicit
# .todos path from anywhere. The event must attach to that project, not cwd.
rm -f "$events"
cd "$TMPROOT"   # cwd is NOT repo1
bash "$PLUGIN_DIR/bin/log-event.sh" item_created '{"id":7}' --todos-dir "$repo1/.todos"
line=$(tail -1 "$events")
assert_match "event carries repo1 project_id" "\"project_id\":\"$id1\"" "$line"
assert_eq "no bogus escape when cwd is outside repo" "0" \
  "$(grep -c worktree_escape_detected "$events" || true)"

echo "test: project-id.sh accepts explicit context_dir"
id1_from_outside=$(bash "$PLUGIN_DIR/bin/project-id.sh" "$repo1/.todos")
assert_eq "project-id context_dir matches in-repo id" "$id1" "$id1_from_outside"

# ---------- rebuild-index.sh id collision detection ----------

echo "test: duplicate ids trigger id_collision_detected"
todos="$repo1/.todos"
mkdir -p "$todos"
cat > "$todos/001.md" <<EOF
---
id: 1
title: "first"
type: task
status: pending
created: 2026-04-18
---
Body.
EOF
cat > "$todos/002.md" <<EOF
---
id: 1
title: "second"
type: task
status: pending
created: 2026-04-19
---
Body.
EOF
rm -f "$events"
bash "$PLUGIN_DIR/rebuild-index.sh" "$todos" >/dev/null 2>&1 || true
assert_eq "collision emitted" "1" "$(grep -c id_collision_detected "$events" || true)"
line=$(grep id_collision_detected "$events")
assert_match "collision has id" '"id":1' "$line"
assert_match "collision has files" '"files":' "$line"

echo "test: clean todos dir does not emit collision"
rm -f "$todos/002.md"
rm -f "$events"
bash "$PLUGIN_DIR/rebuild-index.sh" "$todos" >/dev/null 2>&1 || true
assert_eq "no collision on clean dir" "0" "$(grep -c id_collision_detected "$events" 2>/dev/null || echo 0)"

# ---------- todo-stats.sh ----------

echo "test: todo-stats prints Integrity and Flow sections"
rm -f "$events"
now_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
old_iso=$(date -u -v-40d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "40 days ago" +"%Y-%m-%dT%H:%M:%SZ")
recent_iso=$(date -u -v-5d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "5 days ago" +"%Y-%m-%dT%H:%M:%SZ")
cat >> "$events" <<EOF
{"v":1,"ts":"$recent_iso","event":"id_collision_detected","project_id":"$id1","session_id":"aa-1","id":5,"files":["005.md","005b.md"]}
{"v":1,"ts":"$recent_iso","event":"item_created","project_id":"$id1","session_id":"aa-1","id":10,"type":"task","refined":true}
{"v":1,"ts":"$recent_iso","event":"status_changed","project_id":"$id1","session_id":"aa-1","id":10,"from":"pending","to":"done","days_since_created":2,"days_since_prev_status":null,"type":"task","quadrant":null}
{"v":1,"ts":"$old_iso","event":"status_changed","project_id":"$id1","session_id":"bb-1","id":8,"from":"pending","to":"done","days_since_created":1,"days_since_prev_status":null,"type":"task","quadrant":null}
EOF
out=$(bash "$PLUGIN_DIR/bin/todo-stats.sh" 30d)
assert_match "has Integrity header" 'Integrity' "$out"
assert_match "has Flow header" 'Flow' "$out"
assert_match "counts 1 collision" 'id_collision_detected: *1' "$out"
assert_match "excludes 40d-old event from flow" '1 items' "$out"

echo "test: unsupported window exits with message"
if bash "$PLUGIN_DIR/bin/todo-stats.sh" 7d >/dev/null 2>&1; then
  echo "  FAIL unsupported window should exit nonzero"
  fail=$((fail + 1))
else
  echo "  ok  7d window rejected"
  pass=$((pass + 1))
fi

# ---------- check-gitignore.sh ----------

echo "test: clean repo (gitignored, untracked) prints nothing"
repo_g="$TMPROOT/repo-gitignored"
mkdir -p "$repo_g/.todos"
git -C "$repo_g" init -q
echo ".todos/" > "$repo_g/.gitignore"
git -C "$repo_g" add .gitignore
git -C "$repo_g" -c user.email=t@t -c user.name=t commit -q -m init
out=$(cd "$repo_g" && bash "$PLUGIN_DIR/bin/check-gitignore.sh")
assert_eq "clean repo silent" "" "$out"

echo "test: .todos not gitignored emits nudge"
repo_ng="$TMPROOT/repo-not-gitignored"
mkdir -p "$repo_ng/.todos"
git -C "$repo_ng" init -q
out=$(cd "$repo_ng" && bash "$PLUGIN_DIR/bin/check-gitignore.sh")
assert_match "suggests gitignore recipe" '!\.todos/goal\.md' "$out"
assert_match "recipe exempts retros" '!\.todos/retros/' "$out"

echo "test: tracked .todos files emit untrack nudge"
repo_t="$TMPROOT/repo-tracked"
mkdir -p "$repo_t/.todos"
git -C "$repo_t" init -q
echo "x" > "$repo_t/.todos/001.md"
git -C "$repo_t" add .todos/001.md
git -C "$repo_t" -c user.email=t@t -c user.name=t commit -q -m seed
out=$(cd "$repo_t" && bash "$PLUGIN_DIR/bin/check-gitignore.sh")
assert_match "suggests git rm --cached" 'git rm --cached' "$out"

echo "test: correct recipe with tracked goal.md+retros is silent"
repo_ex="$TMPROOT/repo-exempt"
mkdir -p "$repo_ex/.todos/retros"
git -C "$repo_ex" init -q
cat > "$repo_ex/.gitignore" <<'GI'
.todos/*
!.todos/goal.md
!.todos/retros/
!.todos/retros/**
GI
echo "north_star: test" > "$repo_ex/.todos/goal.md"
echo "# week 1" > "$repo_ex/.todos/retros/2026-W01.md"
git -C "$repo_ex" add .gitignore .todos/goal.md .todos/retros/2026-W01.md
git -C "$repo_ex" -c user.email=t@t -c user.name=t commit -q -m seed
out=$(cd "$repo_ex" && bash "$PLUGIN_DIR/bin/check-gitignore.sh")
assert_eq "exempt-only tracked → silent" "" "$out"

echo "test: correct recipe nudges use .todos/* not .todos/"
out=$(cd "$repo_ng" && bash "$PLUGIN_DIR/bin/check-gitignore.sh")
assert_match "recipe uses .todos/*" '\.todos/\*' "$out"

echo "test: non-git dir is silent"
plain="$TMPROOT/plain-dir"
mkdir -p "$plain/.todos"
out=$(cd "$plain" && bash "$PLUGIN_DIR/bin/check-gitignore.sh")
assert_eq "non-git silent" "" "$out"

# ---------- goal.sh ----------

echo "test: goal.sh exists subcommand on missing file exits 1"
rm -f "$repo1/.todos/goal.md"
set +e
(cd "$repo1" && bash "$PLUGIN_DIR/bin/goal.sh" exists)
rc=$?
set -e
assert_eq "exists rc on missing" "1" "$rc"

echo "test: goal.sh path subcommand prints the expected path"
expected_goal_path=$(cd "$repo1" && pwd -P)/.todos/goal.md
out=$(cd "$repo1" && bash "$PLUGIN_DIR/bin/goal.sh" path)
assert_eq "path output" "$expected_goal_path" "$out"

echo "test: goal.sh read emits JSON on valid file"
mkdir -p "$repo1/.todos"
cat > "$repo1/.todos/goal.md" <<'EOF'
---
north_star: |
  Be the memory of influencer bidding.
success_metrics:
  - "Time-to-pitch-list p50 < 10 min"
  - "Staff weekly active > 4"
updated: 2026-04-20
---

Context body.
EOF
out=$(cd "$repo1" && bash "$PLUGIN_DIR/bin/goal.sh" read)
assert_match "read has north_star" '"north_star":' "$out"
assert_match "read has 2 metrics" '"success_metrics": \[' "$out"
assert_match "read has metric 1" 'Time-to-pitch-list' "$out"
assert_match "read has metric 2" 'Staff weekly active' "$out"
assert_match "read has updated" '"updated": "2026-04-20"' "$out"
assert_match "read has staleness_days" '"staleness_days":' "$out"

echo "test: goal.sh exists subcommand on present file exits 0"
set +e
(cd "$repo1" && bash "$PLUGIN_DIR/bin/goal.sh" exists)
rc=$?
set -e
assert_eq "exists rc on present" "0" "$rc"

# ---------- retro-read.sh ----------

echo "test: retro-read.sh emits valid JSON with required top-level keys"
# Build fixture: repo1 has goal.md (already written above), one closed item with
# Learned + @decision/@surprise markers, one open item.
closed_done=$(date -u +%Y-%m-%d)
cat > "$repo1/.todos/042.md" <<EOF
---
id: 42
title: "Closed item"
type: feature
status: done
created: 2026-04-15
done: $closed_done
quadrant: q2
---
Body.

## Work Log
- 2026-04-17 @asher @decision: picked option A over B.
- 2026-04-18 @asher @surprise: holidays.yaml already had 2027 data.
- 2026-04-18 @asher: landed.

## Outcome
Feature shipped, no regressions observed.

## Learned
- 2026-04-18: prompt on close is low friction.
EOF
cat > "$repo1/.todos/055.md" <<EOF
---
id: 55
title: "Open item"
type: todo
status: pending
created: 2026-04-19
quadrant: q1
deadline: 2026-04-27
---
EOF
out=$(cd "$repo1" && bash "$PLUGIN_DIR/bin/retro-read.sh" 7d)
assert_match "has project block" '"project":' "$out"
assert_match "has window block" '"window":' "$out"
assert_match "has goal.present true" '"present": true' "$out"
assert_match "lists closed #42" '"id": 42' "$out"
assert_match "lists open #55" '"id": 55' "$out"
assert_match "learned present" '"learned":' "$out"
assert_match "work_log_markers present" '"work_log_markers":' "$out"
assert_match "decision marker parsed" '"marker": "decision"' "$out"
assert_match "surprise marker parsed" '"marker": "surprise"' "$out"
assert_match "iso_week present" '"iso_week": "[0-9]{4}-W' "$out"
assert_match "learning_capture rate" '"capture_rate":' "$out"

echo "test: retro-read.sh flags missing goal"
rm -f "$repo1/.todos/goal.md"
out=$(cd "$repo1" && bash "$PLUGIN_DIR/bin/retro-read.sh" 7d)
assert_match "goal.present false" '"present": false' "$out"

echo "test: retro-read.sh rejects unsupported window"
set +e
out=$(cd "$repo1" && bash "$PLUGIN_DIR/bin/retro-read.sh" 14d 2>&1)
rc=$?
set -e
assert_eq "14d exit code" "2" "$rc"

echo ""
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ]

#!/usr/bin/env bash
# Reads events.jsonl, prints Integrity + Flow sections for the given window.
# v1 supports only 30d.
#
# Usage: todo-stats.sh [window]
#   window: 30d (default)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./_lib.sh
source "$SCRIPT_DIR/_lib.sh"

window="${1:-30d}"
if [ "$window" != "30d" ]; then
  echo "todo-stats.sh: window '$window' not yet supported; use 30d" >&2
  exit 2
fi

events_file="$(telemetry_dir)/events.jsonl"
projects_file="$(telemetry_dir)/projects.json"

if [ ! -f "$events_file" ]; then
  echo "No telemetry data yet at $events_file."
  exit 0
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "todo-stats.sh requires python3" >&2
  exit 1
fi

python3 - "$events_file" "$projects_file" <<'PY'
import json, sys, collections, datetime, statistics, os

events_path = sys.argv[1]
projects_path = sys.argv[2]

now = datetime.datetime.now(datetime.timezone.utc)
cutoff = now - datetime.timedelta(days=30)

projects = {}
if os.path.exists(projects_path):
    with open(projects_path) as f:
        try:
            projects = json.load(f)
        except Exception:
            projects = {}

def name_for(pid):
    rec = projects.get(pid)
    return rec["name"] if rec and "name" in rec else pid

integrity = collections.Counter()
integrity_last = {}
closed_by_project = collections.defaultdict(list)
seen_projects = set()

integrity_events = {
    "id_collision_detected",
    "worktree_escape_detected",
    "filename_id_mismatch_detected",
    "index_rebuild_failed",
}

with open(events_path) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            ev = json.loads(line)
        except Exception:
            continue
        ts_s = ev.get("ts", "")
        try:
            ts = datetime.datetime.fromisoformat(ts_s.replace("Z", "+00:00"))
        except Exception:
            continue
        if ts < cutoff:
            continue
        pid = ev.get("project_id", "?")
        seen_projects.add(pid)
        name = ev.get("event")
        if name in integrity_events:
            integrity[name] += 1
            integrity_last[name] = max(integrity_last.get(name, ts), ts)
        if name == "status_changed" and ev.get("to") == "done":
            days = ev.get("days_since_created")
            if isinstance(days, (int, float)):
                closed_by_project[pid].append(days)

print("Todo telemetry — last 30 days")
project_names = sorted({name_for(p) for p in seen_projects})
print("Projects: " + (", ".join(project_names) if project_names else "(none)"))
print()
print("Integrity")
for name in ["id_collision_detected", "worktree_escape_detected",
             "filename_id_mismatch_detected", "index_rebuild_failed"]:
    count = integrity[name]
    tail = ""
    if count > 0 and name in integrity_last:
        tail = f"  (last on {integrity_last[name].date().isoformat()})"
    print(f"  {name}: {count}{tail}")
print()
print("Flow (items closed this window)")
if not closed_by_project:
    print("  (no items closed)")
else:
    for pid, days in sorted(closed_by_project.items(), key=lambda kv: -len(kv[1])):
        label = name_for(pid)
        n = len(days)
        days.sort()
        p50 = statistics.median(days) if days else 0
        if n >= 10:
            p90 = days[int(round(0.9 * (n - 1)))]
            print(f"  {label}: {n} items, p50 lead time {p50:.1f}d, p90 {p90:.1f}d")
        else:
            print(f"  {label}: {n} items, p50 lead time {p50:.1f}d")
PY

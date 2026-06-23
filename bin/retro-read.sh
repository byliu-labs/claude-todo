#!/usr/bin/env bash
# Scan .todos/ and events.jsonl for the retro window. Print a single JSON blob.
#
# Usage: retro-read.sh [window]
#   window: 7d (default) — 14d and all are reserved for v1.1.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./_lib.sh
source "$SCRIPT_DIR/_lib.sh"

window="${1:-7d}"
if [ "$window" != "7d" ]; then
  echo "retro-read.sh: window '$window' not yet supported; use 7d" >&2
  exit 2
fi

main_repo=""
if git rev-parse --git-common-dir >/dev/null 2>&1; then
  main_repo=$(cd "$(git rev-parse --git-common-dir)/.." && pwd -P)
fi
if [ -z "$main_repo" ]; then
  echo "retro-read.sh: not inside a git repo" >&2
  exit 2
fi

todos_dir="$main_repo/.todos"
goal_path="$todos_dir/goal.md"
events_file="$(telemetry_dir)/events.jsonl"
projects_file="$(telemetry_dir)/projects.json"

project_id=$(bash "$SCRIPT_DIR/project-id.sh")

python3 - "$main_repo" "$todos_dir" "$goal_path" "$events_file" "$projects_file" "$project_id" "$window" <<'PY'
import sys, json, os, re, datetime

main_repo, todos_dir, goal_path, events_path, projects_path, project_id, window = sys.argv[1:8]

now = datetime.datetime.now(datetime.timezone.utc)
days = 7
cutoff = now - datetime.timedelta(days=days)
iso_year, iso_week, _ = now.isocalendar()
iso_week_label = f"{iso_year}-W{iso_week:02d}"

# --- project record ---
project = {"name": os.path.basename(main_repo), "path": main_repo, "project_id": project_id}
if os.path.exists(projects_path):
    try:
        with open(projects_path) as f:
            pj = json.load(f)
        if project_id in pj and "name" in pj[project_id]:
            project["name"] = pj[project_id]["name"]
    except Exception:
        pass

# --- goal ---
goal = {"present": False, "north_star": "", "success_metrics": [], "updated": "", "staleness_days": None}
if os.path.exists(goal_path):
    with open(goal_path) as f:
        text = f.read()
    m = re.match(r'(?s)^---\n(.*?)\n---\n?', text)
    if m:
        fm = m.group(1).split("\n")
        data = {"north_star": "", "success_metrics": [], "updated": ""}
        i = 0
        while i < len(fm):
            line = fm[i]
            if line.startswith("north_star: |"):
                block = []
                i += 1
                while i < len(fm) and (fm[i].startswith("  ") or fm[i] == ""):
                    if fm[i].startswith("  "):
                        block.append(fm[i][2:])
                    i += 1
                data["north_star"] = "\n".join(block).strip()
                continue
            if line.startswith("north_star:"):
                data["north_star"] = line.split(":", 1)[1].strip().strip('"').strip("'")
                i += 1
                continue
            if line.startswith("success_metrics:"):
                items = []
                i += 1
                while i < len(fm) and fm[i].startswith("  - "):
                    items.append(fm[i][4:].strip().strip('"').strip("'"))
                    i += 1
                data["success_metrics"] = items
                continue
            if line.startswith("updated:"):
                data["updated"] = line.split(":", 1)[1].strip().strip('"').strip("'")
                i += 1
                continue
            i += 1
        goal.update({"present": True, **data})
        if data["updated"]:
            try:
                dt = datetime.datetime.strptime(data["updated"], "%Y-%m-%d").date()
                goal["staleness_days"] = (datetime.date.today() - dt).days
            except Exception:
                pass

# --- PRD scan ---
def parse_prd(path):
    with open(path) as f:
        text = f.read()
    m = re.match(r'(?s)^---\n(.*?)\n---\n?(.*)$', text)
    if not m:
        return None
    fm_lines = m.group(1).split("\n")
    body = m.group(2)
    fm = {}
    for line in fm_lines:
        mm = re.match(r'^(\w+):\s*(.*)$', line)
        if mm:
            k, v = mm.group(1), mm.group(2).strip().strip('"').strip("'")
            fm[k] = v if v and v != "null" else None
    def extract(sec):
        mm = re.search(rf'^##\s+{sec}\s*$(.*?)(?=^##\s+|\Z)', body, re.M | re.S)
        return mm.group(1).strip() if mm else ""
    outcome = extract("Outcome")
    learned_block = extract("Learned")
    work_log_block = extract("Work Log")
    learned = []
    for line in learned_block.split("\n"):
        line = line.strip()
        if line.startswith("- "):
            learned.append(line[2:].strip())
    markers = []
    for line in work_log_block.split("\n"):
        line = line.strip()
        if not line.startswith("- "):
            continue
        mm = re.match(r'-\s*(\d{4}-\d{2}-\d{2})\s+(?:@\w+\s+)*@(decision|surprise|learned)\b:?\s*(.*)', line)
        if mm:
            markers.append({"date": mm.group(1), "marker": mm.group(2), "text": mm.group(3).strip()})
    fm["outcome_snippet"] = outcome[:300]
    fm["learned"] = learned
    fm["work_log_markers"] = markers
    fm["lead_time_days"] = None
    if fm.get("created") and fm.get("done"):
        try:
            c = datetime.datetime.strptime(fm["created"], "%Y-%m-%d").date()
            d = datetime.datetime.strptime(fm["done"], "%Y-%m-%d").date()
            fm["lead_time_days"] = (d - c).days
        except Exception:
            pass
    fm["id"] = int(fm.get("id")) if (fm.get("id") or "").isdigit() else None
    return fm

closed = []
open_items = []
if os.path.isdir(todos_dir):
    for entry in sorted(os.listdir(todos_dir)):
        if not entry.endswith(".md"):
            continue
        if entry in ("goal.md", "index.md"):
            continue
        p = os.path.join(todos_dir, entry)
        if not os.path.isfile(p):
            continue
        prd = parse_prd(p)
        if not prd or prd["id"] is None:
            continue
        status = prd.get("status")
        if status == "done" and prd.get("done"):
            try:
                done_dt = datetime.datetime.strptime(prd["done"], "%Y-%m-%d").date()
                if done_dt >= cutoff.date():
                    closed.append({
                        "id": prd["id"],
                        "title": prd.get("title", ""),
                        "type": prd.get("type", ""),
                        "quadrant": prd.get("quadrant"),
                        "created": prd.get("created"),
                        "done": prd.get("done"),
                        "lead_time_days": prd["lead_time_days"],
                        "outcome_snippet": prd["outcome_snippet"],
                        "learned": prd["learned"],
                        "work_log_markers": prd["work_log_markers"],
                    })
            except Exception:
                pass
        elif status in ("pending", "in-progress", "blocked"):
            open_items.append({
                "id": prd["id"],
                "title": prd.get("title", ""),
                "type": prd.get("type", ""),
                "quadrant": prd.get("quadrant"),
                "deadline": prd.get("deadline"),
                "blocked_by": prd.get("blocked_by"),
            })

# --- telemetry aggregation (integrity only) ---
integrity_events = []
if os.path.exists(events_path):
    integrity = {"id_collision_detected","worktree_escape_detected","filename_id_mismatch_detected","index_rebuild_failed"}
    with open(events_path) as f:
        for line in f:
            try:
                ev = json.loads(line)
            except Exception:
                continue
            if ev.get("project_id") != project_id:
                continue
            if ev.get("event") not in integrity:
                continue
            ts_s = ev.get("ts", "")
            try:
                ts = datetime.datetime.fromisoformat(ts_s.replace("Z", "+00:00"))
            except Exception:
                continue
            if ts < cutoff:
                continue
            integrity_events.append({"ts": ts_s, "event": ev["event"], "detail": ""})

with_learned = sum(1 for c in closed if c["learned"])
with_markers = sum(1 for c in closed if c["work_log_markers"])
capture = {
    "closed_in_window": len(closed),
    "with_learned_section": with_learned,
    "with_work_log_markers": with_markers,
    "capture_rate": (with_learned / len(closed)) if closed else 0.0,
}

output = {
    "project": project,
    "window": {
        "label": window,
        "from_iso": cutoff.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "to_iso": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "iso_week": iso_week_label,
    },
    "goal": goal,
    "closed_items": closed,
    "open_items": open_items,
    "integrity_events": integrity_events,
    "learning_capture": capture,
}
print(json.dumps(output, indent=2, ensure_ascii=False))
PY

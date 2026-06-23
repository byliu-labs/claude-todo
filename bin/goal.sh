#!/usr/bin/env bash
# Read/validate <project>/.todos/goal.md. Does NOT write — Claude writes via Write tool.
#
# Subcommands:
#   path       Print resolved goal.md path and exit 0.
#   exists     Exit 0 if file exists, 1 if not.
#   read       Emit parsed frontmatter as JSON to stdout, exit 0.
#              Exits 1 with a message on stderr if file missing or malformed.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./_lib.sh
source "$SCRIPT_DIR/_lib.sh"

cmd="${1:-}"

# Resolve main repo (handles worktrees).
main_repo=""
if git rev-parse --git-common-dir >/dev/null 2>&1; then
  main_repo=$(cd "$(git rev-parse --git-common-dir)/.." && pwd -P)
fi
if [ -z "$main_repo" ]; then
  echo "goal.sh: not inside a git repo" >&2
  exit 2
fi
goal_path="$main_repo/.todos/goal.md"

case "$cmd" in
  path)
    printf '%s\n' "$goal_path"
    ;;
  exists)
    [ -f "$goal_path" ]
    ;;
  read)
    if [ ! -f "$goal_path" ]; then
      echo "goal.sh: $goal_path not found" >&2
      exit 1
    fi
    python3 - "$goal_path" <<'PY'
import sys, json, re, datetime
path = sys.argv[1]
with open(path) as f:
    text = f.read()
m = re.match(r'(?s)^---\n(.*?)\n---\n?(.*)$', text)
if not m:
    sys.stderr.write("goal.sh: frontmatter missing\n")
    sys.exit(1)
fm = m.group(1)

data = {"north_star": "", "success_metrics": [], "updated": ""}
lines = fm.split("\n")
i = 0
while i < len(lines):
    line = lines[i]
    if line.startswith("north_star: |"):
        block = []
        i += 1
        while i < len(lines) and (lines[i].startswith("  ") or lines[i] == ""):
            if lines[i].startswith("  "):
                block.append(lines[i][2:])
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
        while i < len(lines) and lines[i].startswith("  - "):
            item = lines[i][4:].strip().strip('"').strip("'")
            items.append(item)
            i += 1
        data["success_metrics"] = items
        continue
    if line.startswith("updated:"):
        data["updated"] = line.split(":", 1)[1].strip().strip('"').strip("'")
        i += 1
        continue
    i += 1

staleness_days = None
if data["updated"]:
    try:
        updated_dt = datetime.datetime.strptime(data["updated"], "%Y-%m-%d").date()
        staleness_days = (datetime.date.today() - updated_dt).days
    except Exception:
        staleness_days = None

out = {
    "path": path,
    "north_star": data["north_star"],
    "success_metrics": data["success_metrics"],
    "updated": data["updated"],
    "staleness_days": staleness_days,
}
print(json.dumps(out, indent=2))
PY
    ;;
  *)
    echo "goal.sh: unknown subcommand '$cmd' (use: path|exists|read)" >&2
    exit 2
    ;;
esac

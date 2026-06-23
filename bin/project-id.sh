#!/usr/bin/env bash
# Prints a deterministic 12-hex project_id for the current cwd.
# - Primary: sha256(git remote get-url origin)[:12]
# - Fallback: sha256(canonical path of main repo)[:12]
# Maintains $CLAUDE_TODO_HOME/telemetry/projects.json under flock.
#
# Usage: bash project-id.sh [context_dir]
#
# context_dir: optional path inside (or equal to) the project whose id to
# compute. Defaults to $PWD. Use this when the caller is outside the repo
# but knows the correct .todos/ or repo path (e.g. rebuild-index.sh invoked
# from elsewhere, or the skill emitting alerts against main_repo/.todos).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./_lib.sh
source "$SCRIPT_DIR/_lib.sh"

if ! command -v python3 >/dev/null 2>&1; then
  echo "project-id.sh: python3 is required" >&2
  exit 1
fi

ensure_dirs

context_dir="${1:-$PWD}"
# If the path itself doesn't exist yet (e.g. --todos-dir=main_repo/.todos on
# first run, before the dir is created), fall back to its parent so the git
# lookup still succeeds for the surrounding project.
if [ -d "$context_dir" ]; then
  context_dir="$(cd "$context_dir" && pwd -P)"
elif [ -d "$(dirname "$context_dir")" ]; then
  context_dir="$(cd "$(dirname "$context_dir")" && pwd -P)"
fi

# Resolve main repo for consistent path-based fallback across worktrees.
# Anchor git queries to context_dir, not $PWD, so the id reflects the
# project the caller cares about — not wherever the shell happens to be.
main_repo=""
if [ -d "$context_dir" ] && git -C "$context_dir" rev-parse --git-common-dir >/dev/null 2>&1; then
  common=$(git -C "$context_dir" rev-parse --git-common-dir)
  case "$common" in
    /*) main_repo="$(cd "$common/.." && pwd -P)" ;;
    *)  main_repo="$(cd "$context_dir" && cd "$common/.." && pwd -P)" ;;
  esac
fi

# Compute id.
remote=""
if [ -n "$main_repo" ]; then
  remote=$(git -C "$main_repo" remote get-url origin 2>/dev/null || true)
fi

if [ -n "$remote" ]; then
  id=$(printf '%s' "$remote" | sha12)
  name=$(basename "$remote" .git)
else
  path_key="${main_repo:-$context_dir}"
  id=$(printf '%s' "$path_key" | sha12)
  name=$(basename "$path_key")
fi

# Update projects.json under flock. Minimal JSON surgery via python3.
proj_file="$(telemetry_dir)/projects.json"
lock_file="$(telemetry_dir)/.projects.json.lock"
touch "$lock_file"

now=$(iso_now)
path_record="${main_repo:-$context_dir}"

# flock is optional on macOS — if missing, single-user workflow tolerates
# the rare race (concurrent claude sessions updating the same project row).
(
  if command -v flock >/dev/null 2>&1; then
    flock 9
  fi
  if [ ! -s "$proj_file" ]; then
    printf '{}\n' > "$proj_file"
  fi
  # JSON-aware upsert: python3 is the source of truth for existence check
  # (grep can false-positive on substrings inside name/path values).
  python3 - "$proj_file" "$id" "$name" "$path_record" "$now" <<'PY'
import json, sys
path, key, name, repo_path, now = sys.argv[1:6]
with open(path) as f:
    data = json.load(f)
if key in data:
    data[key]['last_seen'] = now
else:
    data[key] = {"name": name, "path": repo_path, "first_seen": now, "last_seen": now}
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
PY
) 9>"$lock_file"

printf '%s' "$id"

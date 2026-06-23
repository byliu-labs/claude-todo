#!/usr/bin/env bash
# Appends one JSON line to events.jsonl. No-op on off tier.
# Usage: log-event.sh <event_name> <payload_json> [--todos-dir DIR]
#
# payload_json is embedded as-is into the envelope. Caller is responsible
# for valid JSON — this script assembles the envelope
# {v, ts, event, project_id, session_id, ...payload} and does not validate
# payload internals.
#
# If --todos-dir is supplied, emits worktree_escape_detected BEFORE the
# main event when the resolved path does not match the main-repo .todos/.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./_lib.sh
source "$SCRIPT_DIR/_lib.sh"

event_name="${1:-}"
if [ -z "$event_name" ]; then
  echo "log-event.sh: missing event name" >&2
  exit 1
fi
payload="${2:-}"
[ -z "$payload" ] && payload='{}'
[ $# -ge 1 ] && shift
[ $# -ge 1 ] && shift

todos_dir=""
while [ $# -gt 0 ]; do
  case "$1" in
    --todos-dir) todos_dir="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

tier=$(read_tier)
if [ "$tier" = "off" ]; then
  exit 0
fi
if [ "$tier" = "community" ]; then
  ensure_dirs
  if [ ! -f "$(telemetry_dir)/.community-warned" ]; then
    echo "log-event.sh: community tier not yet implemented, falling back to local" >&2
    touch "$(telemetry_dir)/.community-warned"
  fi
fi

ensure_dirs
# Anchor project_id to --todos-dir when caller supplied one. This keeps
# rebuild-index.sh invocations from outside the project (documented flow)
# from hashing the wrong $PWD and misattributing the event.
if [ -n "$todos_dir" ]; then
  project_id=$(bash "$SCRIPT_DIR/project-id.sh" "$todos_dir")
else
  project_id=$(bash "$SCRIPT_DIR/project-id.sh")
fi
session=$(session_id)
ts=$(iso_now)
events_file="$(telemetry_dir)/events.jsonl"

emit() {
  local name="$1" body="$2"
  local inner=""
  if [ -n "$body" ] && [ "$body" != "{}" ]; then
    inner=$(printf '%s' "$body" | sed -e 's/^{//' -e 's/}$//')
  fi
  local envelope
  if [ -n "$inner" ]; then
    envelope=$(printf '{"v":1,"ts":"%s","event":"%s","project_id":"%s","session_id":"%s",%s}' \
      "$ts" "$name" "$project_id" "$session" "$inner")
  else
    envelope=$(printf '{"v":1,"ts":"%s","event":"%s","project_id":"%s","session_id":"%s"}' \
      "$ts" "$name" "$project_id" "$session")
  fi
  printf '%s\n' "$envelope" >> "$events_file"
}

# Worktree escape self-detection. Canonicalize both sides to avoid false
# positives from /var vs /private/var on macOS and similar symlink cases.
# Resolve main_repo from $todos_dir (not $PWD) so callers outside the
# project (e.g. rebuild-index.sh run from anywhere) don't log bogus escapes.
if [ -n "$todos_dir" ]; then
  main_repo=""
  escape_ctx="$todos_dir"
  if [ -d "$escape_ctx" ]; then
    escape_ctx=$(cd "$escape_ctx" && pwd -P)
  elif [ -d "$(dirname "$escape_ctx")" ]; then
    escape_ctx="$(cd "$(dirname "$escape_ctx")" && pwd -P)"
  fi
  if [ -d "$escape_ctx" ] && git -C "$escape_ctx" rev-parse --git-common-dir >/dev/null 2>&1; then
    common=$(git -C "$escape_ctx" rev-parse --git-common-dir)
    case "$common" in
      /*) main_repo=$(cd "$common/.." && pwd -P) ;;
      *)  main_repo=$(cd "$escape_ctx" && cd "$common/.." && pwd -P) ;;
    esac
  fi
  # Fallback: if the provided --todos-dir isn't itself in a git repo (e.g. a
  # stray path outside the project), anchor on $PWD — that's the caller's
  # intent signal for what "main repo" should be.
  if [ -z "$main_repo" ] && git -C "$PWD" rev-parse --git-common-dir >/dev/null 2>&1; then
    common=$(git -C "$PWD" rev-parse --git-common-dir)
    case "$common" in
      /*) main_repo=$(cd "$common/.." && pwd -P) ;;
      *)  main_repo=$(cd "$PWD" && cd "$common/.." && pwd -P) ;;
    esac
  fi
  if [ -n "$main_repo" ]; then
    expected="$main_repo/.todos"
    if [ -d "$todos_dir" ]; then
      provided_canon=$(cd "$todos_dir" && pwd -P)
    else
      parent=$(dirname "$todos_dir")
      base=$(basename "$todos_dir")
      if [ -d "$parent" ]; then
        provided_canon="$(cd "$parent" && pwd -P)/$base"
      else
        provided_canon="$todos_dir"
      fi
    fi
    if [ "$provided_canon" != "$expected" ]; then
      escape_payload=$(printf '"_resolved_todos_dir":"%s","_expected_main_repo_dir":"%s","_cwd":"%s"' \
        "$provided_canon" "$expected" "$PWD")
      emit worktree_escape_detected "{$escape_payload}"
    fi
  fi
fi

emit "$event_name" "$payload"

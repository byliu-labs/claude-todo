#!/usr/bin/env bash
# Shared helpers for telemetry scripts. Source, don't execute.

set -euo pipefail

# Telemetry root (overridable for tests via CLAUDE_TODO_HOME).
telemetry_dir() {
  local base="${CLAUDE_TODO_HOME:-$HOME/.config/claude-todo}"
  printf '%s/telemetry' "$base"
}

config_path() {
  local base="${CLAUDE_TODO_HOME:-$HOME/.config/claude-todo}"
  printf '%s/config.yaml' "$base"
}

# Make sure runtime dirs exist. Idempotent.
ensure_dirs() {
  local dir
  dir="$(telemetry_dir)"
  mkdir -p "$dir"
}

# First-run default: write local tier if config missing.
read_tier() {
  local cfg
  cfg="$(config_path)"
  if [ ! -f "$cfg" ]; then
    mkdir -p "$(dirname "$cfg")"
    printf 'telemetry: local\n' > "$cfg"
  fi
  # Minimal yaml read — we only have one key.
  local tier
  tier=$(sed -n 's/^telemetry: *\([a-z]*\).*/\1/p' "$cfg" | head -1)
  printf '%s' "${tier:-local}"
}

iso_now() {
  # UTC ISO-8601 with Z suffix, second precision.
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# sha256(stdin) truncated to 12 hex chars.
sha12() {
  shasum -a 256 | cut -c1-12
}

# sha256(stdin) truncated to 8 hex chars.
sha8() {
  shasum -a 256 | cut -c1-8
}

# Session id: cached per-cwd marker file, <1h reuse window.
session_id() {
  local cwd_hash
  cwd_hash=$(printf '%s' "$PWD" | sha8)
  local marker
  marker="$(telemetry_dir)/.session-${cwd_hash}.id"
  if [ -f "$marker" ]; then
    # File mtime within last hour?
    local age_seconds
    if [ "$(uname)" = "Darwin" ]; then
      age_seconds=$(( $(date +%s) - $(stat -f %m "$marker") ))
    else
      age_seconds=$(( $(date +%s) - $(stat -c %Y "$marker") ))
    fi
    if [ "$age_seconds" -lt 3600 ]; then
      cat "$marker"
      return
    fi
  fi
  ensure_dirs
  local sid
  sid="${cwd_hash}-$(date +%s)"
  printf '%s' "$sid" > "$marker"
  printf '%s' "$sid"
}

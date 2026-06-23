---
description: "Show todo telemetry rollup — integrity events and lead-time flow across projects. Defaults to 30-day window."
argument-hint: "[30d]"
allowed-tools: Bash(bash*)
---

# /stats — Todo telemetry rollup

Delegates to `bin/todo-stats.sh`. The only supported window today is `30d` (default). Any other argument exits with an error.

## What the user sees

- **Projects** — names (from the global registry) of every project that emitted events in the window.
- **Integrity** — counts for `id_collision_detected`, `worktree_escape_detected`, `filename_id_mismatch_detected`, `index_rebuild_failed`, plus the last-seen date when non-zero. A clean system is all zeros.
- **Flow** — for each project, items closed this window (`status_changed` → `done`) with p50 lead time, plus p90 when n ≥ 10.

Telemetry is opt-in (`~/.config/claude-todo/config.yaml` key `telemetry: local` enables it; `off` disables). If the events file is missing, the script prints "No telemetry data yet." No remote egress happens — everything is local JSONL.

## Run

Resolve `$PLUGIN_DIR` as the parent of this file's `commands/` directory, then:

```bash
bash "$PLUGIN_DIR/bin/todo-stats.sh" "${1:-30d}"
```

Relay the script's stdout verbatim. Do not post-process or summarize — the output is already designed to read at a glance.

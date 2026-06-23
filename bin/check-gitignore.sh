#!/usr/bin/env bash
# Prints a short nudge when the main repo is missing the recommended
# `.todos/` gitignore setup. Silent when everything is fine OR when cwd is
# outside a git repo. Exit code is always 0.
#
# Why this exists: committing .todos/ causes ID collisions across sessions,
# because Claude moves todo files into a feature worktree to commit them, and
# they become invisible to other sessions until the PR merges.

set -euo pipefail

if ! git rev-parse --git-common-dir >/dev/null 2>&1; then
  exit 0
fi

main_repo=$(cd "$(git rev-parse --git-common-dir)/.." && pwd -P)
todos_dir="$main_repo/.todos"

if [ ! -d "$todos_dir" ]; then
  exit 0
fi

# Probe with a representative PRD path (numeric id .md) — the recommended recipe
# `.todos/*` with `!.todos/goal.md` and `!.todos/retros/**` leaves the directory
# itself un-ignored but ignores PRD files. Testing a real PRD pattern is the
# only reliable signal; `check-ignore .todos/` changes meaning between the two
# recipes and is not a correctness check.
ignored=1
if git -C "$main_repo" check-ignore -q .todos/001.md 2>/dev/null; then
  ignored=0
fi

# Only count tracked files that SHOULD be ignored. goal.md and retros/ are
# intentionally exempted by the recipe, so a project that committed them is
# correctly configured — counting them here would false-positive the warning.
tracked_count=0
if git -C "$main_repo" ls-files --error-unmatch .todos/ >/dev/null 2>&1; then
  # grep -v returns 1 when every line is filtered out (exempt-only tracked) —
  # that's a correct-state signal here, so tolerate it with `|| true`.
  tracked_count=$({ git -C "$main_repo" ls-files .todos/ \
    | grep -v -E '^\.todos/(goal\.md|retros/)' || true; } \
    | wc -l | tr -d ' ')
fi

if [ "$ignored" -ne 0 ] || [ "$tracked_count" -gt 0 ]; then
  printf '⚠ todo skill: .todos/ is under git control.\n'
  printf '  This causes ID collisions when files move into feature worktrees to commit.\n'
  printf '  Recommended one-time fix (run from the main repo root):\n'
  printf '\n'
  if [ "$tracked_count" -gt 0 ]; then
    printf '    git rm --cached -r .todos/\n'
  fi
  if [ "$ignored" -ne 0 ]; then
    printf '    cat >> .gitignore <<GITIGNORE\n'
    printf '    .todos/*\n'
    printf '    !.todos/goal.md\n'
    printf '    !.todos/retros/\n'
    printf '    !.todos/retros/**\n'
    printf '    GITIGNORE\n'
  fi
  printf '    git add .gitignore && git commit -m "chore: untrack .todos/"\n'
  printf '\n'
fi

exit 0

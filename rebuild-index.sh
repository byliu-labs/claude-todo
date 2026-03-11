#!/usr/bin/env bash
# Regenerates .todos/index.md from PRD frontmatter.
# Ships with the plugin repo — copy to .todos/ for CI/non-Claude use.
# Usage: bash .todos/rebuild-index.sh  (or from plugin repo: bash rebuild-index.sh /path/to/.todos)

set -euo pipefail

DIR="${1:-$(cd "$(dirname "$0")" && pwd)}"
INDEX="$DIR/index.md"

if ! ls "$DIR"/[0-9][0-9][0-9].md &>/dev/null; then
  echo "No PRD files found in $DIR"
  exit 0
fi

declare -a IN_PROGRESS=() PENDING=() BLOCKED=() QUESTIONS=() DONE=()

for f in "$DIR"/[0-9][0-9][0-9].md; do
  [ -f "$f" ] || continue

  # Extract frontmatter fields via sed
  id=$(sed -n 's/^id: *//p' "$f" | head -1)
  title=$(sed -n 's/^title: *"\(.*\)"/\1/p' "$f" | head -1)
  # Fallback: unquoted title
  [ -z "$title" ] && title=$(sed -n 's/^title: *//p' "$f" | head -1)
  type=$(sed -n 's/^type: *//p' "$f" | head -1)
  status=$(sed -n 's/^status: *//p' "$f" | head -1)
  created=$(sed -n 's/^created: *//p' "$f" | head -1)
  done_date=$(sed -n 's/^done: *//p' "$f" | head -1)
  blocked_by=$(sed -n 's/^blocked_by: *//p' "$f" | head -1)
  assignee=$(sed -n 's/^assignee: *//p' "$f" | head -1)
  quadrant=$(sed -n 's/^quadrant: *//p' "$f" | head -1)
  deadline=$(sed -n 's/^deadline: *//p' "$f" | head -1)

  # Build suffix tags
  suffix=""
  [ "$assignee" != "null" ] && [ -n "$assignee" ] && suffix="$suffix @${assignee}"
  [ "$quadrant" != "null" ] && [ -n "$quadrant" ] && suffix="$suffix [${quadrant}]"
  [ "$deadline" != "null" ] && [ -n "$deadline" ] && suffix="$suffix (due: ${deadline})"

  # Route to section
  if [ "$type" = "question" ] && [ "$status" != "done" ]; then
    QUESTIONS+=("- ? #${id} — ${title} (added: ${created})${suffix}")
  elif [ "$status" = "done" ]; then
    DONE+=("- [x] #${id} — ${title} (added: ${created}, done: ${done_date})")
  elif [ "$status" = "in-progress" ]; then
    IN_PROGRESS+=("- [-] #${id} — ${title} (added: ${created})${suffix}")
  elif [ "$blocked_by" != "null" ] && [ -n "$blocked_by" ]; then
    BLOCKED+=("- [ ] #${id} — ${title} (added: ${created}) [blocked: ${blocked_by}]${suffix}")
  else
    PENDING+=("- [ ] #${id} — ${title} (added: ${created})${suffix}")
  fi
done

# Write index
cat > "$INDEX" <<'HEADER'
# Project TODO

> Auto-generated from `.todos/*.md` frontmatter. Do not edit manually.

HEADER

print_section() {
  local name="$1"
  shift
  echo "## $name" >> "$INDEX"
  echo "" >> "$INDEX"
  if [ $# -eq 0 ]; then
    echo "(none)" >> "$INDEX"
  else
    for item in "$@"; do
      echo "$item" >> "$INDEX"
    done
  fi
  echo "" >> "$INDEX"
}

print_section "In Progress" "${IN_PROGRESS[@]+"${IN_PROGRESS[@]}"}"
print_section "Pending" "${PENDING[@]+"${PENDING[@]}"}"
print_section "Blocked" "${BLOCKED[@]+"${BLOCKED[@]}"}"
print_section "Open Questions" "${QUESTIONS[@]+"${QUESTIONS[@]}"}"
print_section "Done" "${DONE[@]+"${DONE[@]}"}"

echo "Index rebuilt: $INDEX"

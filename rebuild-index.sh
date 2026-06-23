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

# Parallel arrays — index N corresponds to the Nth scanned file.
# bash 3.2 compatible (no associative arrays).
declare -a ID=() TITLE=() TYPE=() STATUS=() PARENT=() BLOCKED_BY=() REFINED=()
declare -a CREATED=() DONE_DATE=() ASSIGNEE=() QUADRANT=() DEADLINE=() RESOLUTION=()
declare -a CATEGORY=() NORM_CATEGORY=() SUFFIX=()

i=0
for f in "$DIR"/[0-9][0-9][0-9].md; do
  [ -f "$f" ] || continue

  id=$(sed -n 's/^id: *//p' "$f" | head -1)
  title=$(sed -n 's/^title: *"\(.*\)"/\1/p' "$f" | head -1)
  [ -z "$title" ] && title=$(sed -n 's/^title: *//p' "$f" | head -1)
  type=$(sed -n 's/^type: *//p' "$f" | head -1)
  status=$(sed -n 's/^status: *//p' "$f" | head -1)
  parent=$(sed -n 's/^parent: *//p' "$f" | head -1)
  blocked_by=$(sed -n 's/^blocked_by: *//p' "$f" | head -1)
  refined=$(sed -n 's/^refined: *//p' "$f" | head -1)
  created=$(sed -n 's/^created: *//p' "$f" | head -1)
  done_date=$(sed -n 's/^done: *//p' "$f" | head -1)
  assignee=$(sed -n 's/^assignee: *//p' "$f" | head -1)
  quadrant=$(sed -n 's/^quadrant: *//p' "$f" | head -1)
  deadline=$(sed -n 's/^deadline: *//p' "$f" | head -1)
  resolution=$(sed -n 's/^resolution: *//p' "$f" | head -1)
  category=$(sed -n 's/^category: *//p' "$f" | head -1)

  norm_category="$category"
  if [ -z "$norm_category" ] || [ "$norm_category" = "null" ]; then
    norm_category="~uncategorized"
  fi

  suffix=""
  [ "$assignee" != "null" ] && [ -n "$assignee" ] && suffix="$suffix @${assignee}"
  [ "$quadrant" != "null" ] && [ -n "$quadrant" ] && suffix="$suffix [${quadrant}]"
  [ "$deadline" != "null" ] && [ -n "$deadline" ] && suffix="$suffix (due: ${deadline})"

  ID[$i]="$id";           TITLE[$i]="$title";       TYPE[$i]="$type"
  STATUS[$i]="$status";   PARENT[$i]="$parent";     BLOCKED_BY[$i]="$blocked_by"
  REFINED[$i]="$refined"; CREATED[$i]="$created";   DONE_DATE[$i]="$done_date"
  ASSIGNEE[$i]="$assignee"; QUADRANT[$i]="$quadrant"; DEADLINE[$i]="$deadline"
  RESOLUTION[$i]="$resolution"; CATEGORY[$i]="$category"
  NORM_CATEGORY[$i]="$norm_category"; SUFFIX[$i]="$suffix"
  i=$((i + 1))
done
N=$i

# -------- Helpers --------

# Index of the first feature with a given id, or -1.
feature_index() {
  local fid="$1" k
  for k in $(seq 0 $((N - 1))); do
    if [ "${ID[$k]}" = "$fid" ] && [ "${TYPE[$k]}" = "feature" ]; then
      echo "$k"; return
    fi
  done
  echo "-1"
}

# Indices of all children for a given feature index, in file-scan order.
children_of() {
  local fidx="$1" fid="${ID[$fidx]}" k
  for k in $(seq 0 $((N - 1))); do
    if [ "${PARENT[$k]}" = "$fid" ]; then
      echo "$k"
    fi
  done
}

# Render a single item (no leading indent — caller may prefix).
render_item() {
  local k="$1"
  local id="${ID[$k]}" title="${TITLE[$k]}" status="${STATUS[$k]}"
  local created="${CREATED[$k]}" done_date="${DONE_DATE[$k]}"
  local blocked_by="${BLOCKED_BY[$k]}" suffix="${SUFFIX[$k]}"
  local resolution="${RESOLUTION[$k]}" type="${TYPE[$k]}"

  if [ "$type" = "question" ] && [ "$status" != "done" ]; then
    echo "- ? #${id} — ${title} (added: ${created})${suffix}"
  elif [ "$status" = "done" ]; then
    if [ "$resolution" = "superseded" ]; then
      echo "- [~] #${id} — ${title} (added: ${created}, done: ${done_date})"
    elif [ "$resolution" = "cancelled" ]; then
      echo "- [-] #${id} — ${title} (cancelled, done: ${done_date})"
    else
      echo "- [x] #${id} — ${title} (added: ${created}, done: ${done_date})"
    fi
  elif [ "$status" = "in-progress" ]; then
    echo "- [-] #${id} — ${title} (added: ${created})${suffix}"
  elif [ "$blocked_by" != "null" ] && [ -n "$blocked_by" ]; then
    echo "- [ ] #${id} — ${title} (added: ${created}) [blocked: ${blocked_by}]${suffix}"
  else
    echo "- [ ] #${id} — ${title} (added: ${created})${suffix}"
  fi
}

# Section key (IN_PROGRESS|PENDING|BLOCKED|QUESTIONS|DONE) for a non-feature item.
standalone_section() {
  local k="$1"
  local type="${TYPE[$k]}" status="${STATUS[$k]}" blocked_by="${BLOCKED_BY[$k]}"
  if [ "$type" = "question" ] && [ "$status" != "done" ]; then
    echo "QUESTIONS"
  elif [ "$status" = "done" ]; then
    echo "DONE"
  elif [ "$status" = "in-progress" ]; then
    echo "IN_PROGRESS"
  elif [ "$blocked_by" != "null" ] && [ -n "$blocked_by" ]; then
    echo "BLOCKED"
  else
    echo "PENDING"
  fi
}

# Derived section for a feature, based on its children + own explicit status.
# Spec (commands/todo.md:497, 514-517):
#   In Progress: any in-progress child, or feature itself in-progress
#   Blocked: all remaining non-done children blocked
#   Done: feature.status == done (E2E gate)
#   Pending: otherwise (including no children yet)
feature_section() {
  local fidx="$1"
  local fstatus="${STATUS[$fidx]}"

  if [ "$fstatus" = "done" ]; then
    echo "DONE"; return
  fi

  local has_in_progress=0 has_unblocked_pending=0 has_remaining=0
  local k child_status child_blocked
  for k in $(children_of "$fidx"); do
    child_status="${STATUS[$k]}"
    child_blocked="${BLOCKED_BY[$k]}"
    if [ "$child_status" != "done" ]; then
      has_remaining=1
      if [ "$child_status" = "in-progress" ]; then
        has_in_progress=1
      elif [ -z "$child_blocked" ] || [ "$child_blocked" = "null" ]; then
        has_unblocked_pending=1
      fi
    fi
  done

  if [ "$fstatus" = "in-progress" ] || [ "$has_in_progress" = "1" ]; then
    echo "IN_PROGRESS"
  elif [ "$has_remaining" = "0" ]; then
    # All children done but feature not marked done — sits in Pending awaiting E2E.
    echo "PENDING"
  elif [ "$has_unblocked_pending" = "1" ]; then
    echo "PENDING"
  else
    echo "BLOCKED"
  fi
}

# Feature header: ### #ID — Title (X/Y done) [suffix]
feature_header() {
  local fidx="$1" k total=0 done_count=0
  for k in $(children_of "$fidx"); do
    total=$((total + 1))
    [ "${STATUS[$k]}" = "done" ] && done_count=$((done_count + 1))
  done
  local id="${ID[$fidx]}" title="${TITLE[$fidx]}" suffix="${SUFFIX[$fidx]}"
  echo "### #${id} — ${title} (${done_count}/${total} done)${suffix}"
}

# Children indices ordered for display: in-progress, pending-unblocked,
# pending-blocked, done. (commands/todo.md:501)
sort_children() {
  local fidx="$1" k status blocked_by
  for k in $(children_of "$fidx"); do
    [ "${STATUS[$k]}" = "in-progress" ] && echo "$k"
  done
  for k in $(children_of "$fidx"); do
    status="${STATUS[$k]}"; blocked_by="${BLOCKED_BY[$k]}"
    if [ "$status" != "done" ] && [ "$status" != "in-progress" ]; then
      if [ -z "$blocked_by" ] || [ "$blocked_by" = "null" ]; then
        echo "$k"
      fi
    fi
  done
  for k in $(children_of "$fidx"); do
    status="${STATUS[$k]}"; blocked_by="${BLOCKED_BY[$k]}"
    if [ "$status" != "done" ] && [ "$status" != "in-progress" ]; then
      if [ -n "$blocked_by" ] && [ "$blocked_by" != "null" ]; then
        echo "$k"
      fi
    fi
  done
  for k in $(children_of "$fidx"); do
    [ "${STATUS[$k]}" = "done" ] && echo "$k"
  done
}

# Is item k nested under a real feature in this corpus?
# Items whose parent is unset, "null", or points to a missing/non-feature id
# fall back to standalone rendering (rather than vanishing).
is_nested() {
  local k="$1" p="${PARENT[$k]}"
  if [ -z "$p" ] || [ "$p" = "null" ]; then
    echo "0"; return
  fi
  if [ "$(feature_index "$p")" = "-1" ]; then
    echo "0"
  else
    echo "1"
  fi
}

# -------- Integrity: duplicate id detection (unchanged) --------
# Emits one id_collision_detected event per group of files sharing an id.
PLUGIN_BIN="$(cd "$(dirname "$0")" && pwd)/bin"
if [ -x "$PLUGIN_BIN/log-event.sh" ]; then
  tmplist=$(mktemp)
  for f in "$DIR"/[0-9][0-9][0-9].md; do
    [ -f "$f" ] || continue
    fid=$(sed -n 's/^id: *//p' "$f" | head -1)
    [ -n "$fid" ] && printf '%s\t%s\n' "$fid" "$(basename "$f")" >> "$tmplist"
  done
  sort "$tmplist" | awk -F'\t' '
    { ids[$1] = ids[$1] "," $2; cnt[$1]++ }
    END { for (id in cnt) if (cnt[id] > 1) print id "\t" substr(ids[id], 2) }
  ' | while IFS=$'\t' read -r fid files_csv; do
    files_json="[$(printf '"%s",' $(echo "$files_csv" | tr ',' '\n') | sed 's/,$//')]"
    payload=$(printf '"id":%s,"files":%s' "$fid" "$files_json")
    bash "$PLUGIN_BIN/log-event.sh" id_collision_detected "{$payload}" \
      --todos-dir "$DIR" >/dev/null 2>&1 || true
  done
  rm -f "$tmplist"
fi

# -------- Render index --------

cat > "$INDEX" <<'HEADER'
# Project TODO

> Auto-generated from `.todos/*.md` frontmatter. Do not edit manually.

HEADER

# Render features+standalones for a (section, category) pair. No headers — caller writes them.
render_section_for_category() {
  local section_key="$1" cat="$2" k c kcat
  local printed=0

  # Features in this section + category. Skip features that are themselves
  # children of another feature — they render under their parent only.
  for k in $(seq 0 $((N - 1))); do
    [ "${TYPE[$k]}" = "feature" ] || continue
    [ "$(is_nested "$k")" = "1" ] && continue
    [ "$(feature_section "$k")" = "$section_key" ] || continue
    [ "${NORM_CATEGORY[$k]}" = "$cat" ] || continue
    feature_header "$k" >> "$INDEX"
    for c in $(sort_children "$k"); do
      printf '  %s\n' "$(render_item "$c")" >> "$INDEX"
    done
    echo "" >> "$INDEX"
    printed=1
  done

  # Standalone items (not features, not nested under a feature) in this section + category
  for k in $(seq 0 $((N - 1))); do
    [ "${TYPE[$k]}" = "feature" ] && continue
    [ "$(is_nested "$k")" = "1" ] && continue
    [ "$(standalone_section "$k")" = "$section_key" ] || continue
    [ "${NORM_CATEGORY[$k]}" = "$cat" ] || continue
    render_item "$k" >> "$INDEX"
    printed=1
  done

  echo "$printed"
}

# Flat section: features then standalones, no category sub-grouping. Used for
# In Progress, Open Questions, Done — short or chronological reads.
print_section_flat() {
  local section_key="$1" header="$2"
  echo "## $header" >> "$INDEX"
  echo "" >> "$INDEX"

  local printed=0 k c

  for k in $(seq 0 $((N - 1))); do
    [ "${TYPE[$k]}" = "feature" ] || continue
    [ "$(is_nested "$k")" = "1" ] && continue
    [ "$(feature_section "$k")" = "$section_key" ] || continue
    feature_header "$k" >> "$INDEX"
    for c in $(sort_children "$k"); do
      printf '  %s\n' "$(render_item "$c")" >> "$INDEX"
    done
    echo "" >> "$INDEX"
    printed=1
  done

  for k in $(seq 0 $((N - 1))); do
    [ "${TYPE[$k]}" = "feature" ] && continue
    [ "$(is_nested "$k")" = "1" ] && continue
    [ "$(standalone_section "$k")" = "$section_key" ] || continue
    render_item "$k" >> "$INDEX"
    printed=1
  done

  if [ "$printed" = "0" ]; then
    echo "(none)" >> "$INDEX"
  fi
  echo "" >> "$INDEX"
}

# Categorized section: sub-groups items by `category` frontmatter. Used for
# Pending and Blocked — long lists where topical grouping aids navigation.
# Items without a category land in `(uncategorized)`, sorted last.
print_section_categorized() {
  local section_key="$1" header="$2"
  echo "## $header" >> "$INDEX"
  echo "" >> "$INDEX"

  # Collect normalized categories from items routed to this section.
  local cats="" k cat
  for k in $(seq 0 $((N - 1))); do
    if [ "${TYPE[$k]}" = "feature" ]; then
      [ "$(is_nested "$k")" = "1" ] && continue
      [ "$(feature_section "$k")" = "$section_key" ] || continue
    else
      [ "$(is_nested "$k")" = "1" ] && continue
      [ "$(standalone_section "$k")" = "$section_key" ] || continue
    fi
    cats="$cats
${NORM_CATEGORY[$k]}"
  done

  local sorted_cats
  sorted_cats=$(printf '%s\n' "$cats" | grep -v "^$" | sort -u)

  if [ -z "$sorted_cats" ]; then
    echo "(none)" >> "$INDEX"
    echo "" >> "$INDEX"
    return
  fi

  while IFS= read -r cat; do
    [ -z "$cat" ] && continue
    local display_cat="$cat"
    [ "$cat" = "~uncategorized" ] && display_cat="(uncategorized)"
    echo "### $display_cat" >> "$INDEX"
    echo "" >> "$INDEX"
    render_section_for_category "$section_key" "$cat" >/dev/null
    echo "" >> "$INDEX"
  done <<< "$sorted_cats"
}

print_section_flat        "IN_PROGRESS" "In Progress"
print_section_categorized "PENDING"     "Pending"
print_section_categorized "BLOCKED"     "Blocked"
print_section_flat        "QUESTIONS"   "Open Questions"
print_section_flat        "DONE"        "Done"

echo "Index rebuilt: $INDEX"

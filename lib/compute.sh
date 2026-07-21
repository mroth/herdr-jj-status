#!/usr/bin/env bash
# compute.sh <dir>
#
# Pure, side-effect-free read of a Jujutsu repo. Prints a single tab-separated
# line "<jj_bookmark>\t<jj_status>" and exits 0 when <dir> is inside a jj repo.
# Exits 3 (no output) when <dir> is not a jj repo, so the caller can clear the
# sidebar tokens.
#
# All jj calls use --ignore-working-copy so reading status never snapshots or
# mutates the working copy (this may run often), and --no-pager so nothing blocks.

set -o pipefail

dir="${1:?usage: compute.sh <dir>}"
jj=(jj --no-pager --ignore-working-copy -R "$dir")

# Not a jj repo -> signal the caller to clear tokens.
"${jj[@]}" root >/dev/null 2>&1 || exit 3

# --- jj_bookmark: local bookmark on @, else nearest ancestor bookmark, else change id + desc ---
bookmark="$("${jj[@]}" log -r '@' --no-graph -T 'local_bookmarks' 2>/dev/null)"

nearest=""
if [ -z "$bookmark" ]; then
  nearest="$("${jj[@]}" log -r 'heads(::@ & bookmarks())' --no-graph \
    -T 'local_bookmarks ++ "\n"' 2>/dev/null | grep -v '^$' | head -1)"
  bookmark="$nearest"
fi

if [ -z "$bookmark" ]; then
  # No bookmark anywhere in ancestry: fall back to the change id (+ description).
  bookmark="$("${jj[@]}" log -r '@' --no-graph \
    -T 'change_id.shortest(8) ++ if(description, " " ++ description.first_line(), "")' \
    2>/dev/null)"
fi

# --- jj_status: conflict, commits ahead of the bookmark, dirty working copy ---
status=""

# Conflict in the working-copy commit.
if [ -n "$("${jj[@]}" log -r '@' --no-graph -T 'if(conflict, "1", "")' 2>/dev/null)" ]; then
  status+="!"
fi

# Non-empty commits between the shown bookmark and @ (how far your work has moved
# past the bookmark). Only meaningful when @ is not itself on the bookmark.
if [ -n "$nearest" ]; then
  ahead="$("${jj[@]}" log -r "(${nearest}..@) ~ empty()" --no-graph -T '"x\n"' 2>/dev/null | grep -c 'x')"
  if [ "${ahead:-0}" -gt 0 ] 2>/dev/null; then
    status+="+${ahead}"
  fi
fi

# Dirty: the working-copy commit @ has uncommitted content.
if [ -z "$("${jj[@]}" log -r '@' --no-graph -T 'if(empty, "1", "")' 2>/dev/null)" ]; then
  status+="*"
fi

printf '%s\t%s\n' "$bookmark" "$status"

#!/usr/bin/env bash
# compute.sh <dir>
#
# Pure, side-effect-free read of a Jujutsu repo. Prints a single tab-separated
# line "<jj_bookmark>\t<jj_status>" and exits 0 when <dir> is inside a jj repo.
# Exits 3 (no output) when <dir> is not a jj repo, so the caller can clear the
# sidebar tokens.
#
# Grammar (see plans/display-spec.md) — location-anchored:
#   $jj_bookmark : on a bookmark        -> "main" (or "main feat")
#                  descendant of one    -> "<nearest>:: @<changeid>"  (e.g. "main:: @rx")
#                  no bookmark at all    -> "@<changeid>"
#                  (conflicted bookmark -> "name??"; divergent change -> "@id??")
#   $jj_status   : "! ↑A↓D *N"  — conflict, remote ahead/behind, dirty(file count)
#
# "::" is jj's DAG-range operator: "main::" = descendants of main, so "main:: @rx"
#   reads "in main's descendants, at change rx". No depth count (glance surface).
# @<changeid> = current change id (shortest unique), shown only when off a bookmark.
# ↑A↓D = the shown bookmark vs its remote (default "origin"); omitted if no remote.
# *N   = @ is non-empty; N = changed files.
#
# All jj calls use --ignore-working-copy so reading never snapshots/mutates the
# working copy (this may run often), and --no-pager so nothing blocks.

set -o pipefail

dir="${1:?usage: compute.sh <dir>}"
remote="${JJ_STATUS_REMOTE:-origin}"
jj=(jj --no-pager --ignore-working-copy -R "$dir")

# Not a jj repo -> signal the caller to clear tokens.
"${jj[@]}" root >/dev/null 2>&1 || exit 3

# Bare bookmark name(s), with "??" appended for a conflicted bookmark. jj's own
# "*" out-of-sync marker is intentionally dropped — we compute precise ↑↓ instead.
BM_T='local_bookmarks.map(|b| b.name() ++ if(b.conflict(), "??", "")).join(" ")'

tmpl() { "${jj[@]}" log -r "$1" --no-graph -T "$2" 2>/dev/null; }
count() { "${jj[@]}" log -r "$1" --no-graph -T '"x\n"' 2>/dev/null | grep -c 'x'; }
revset_ok() { "${jj[@]}" log -r "$1" --no-graph -T '""' >/dev/null 2>&1; }

# Working-copy commit facts (single reads).
is_conflict=$(tmpl '@' 'if(conflict, "1", "")')
is_empty=$(tmpl '@' 'if(empty, "1", "")')
is_divergent=$(tmpl '@' 'if(divergent, "1", "")')

# --- $jj_bookmark ---------------------------------------------------------
# bmname = the single bookmark used for +N and remote comparison ("" if none).
bookmark="$(tmpl '@' "$BM_T")"
bmname=""

if [ -n "$bookmark" ]; then
  # On one or more local bookmarks -> just the name(s), no change id.
  bmname="${bookmark%% *}"; bmname="${bmname%'??'}"
else
  # Off any bookmark: anchor on the current change id.
  cid="@$(tmpl '@' 'change_id.shortest()')"
  nearest="$(tmpl 'heads(::@ & bookmarks())' "${BM_T} ++ \"\\n\"" | grep -v '^$' | head -1)"
  if [ -n "$nearest" ]; then
    # Descendant of an ancestor bookmark: "<nearest>:: @id" (no depth count).
    bmname="${nearest%% *}"; bmname="${bmname%'??'}"
    bookmark="${nearest}:: ${cid}"
  else
    # No bookmark anywhere: just the change id ("??" if divergent).
    bookmark="$cid"
    [ -n "$is_divergent" ] && bookmark="${bookmark}??"
  fi
fi

# --- $jj_status : "! ↑A↓D *N" --------------------------------------------
conflict=""; [ -n "$is_conflict" ] && conflict="!"

remote_group=""
if [ -n "$bmname" ] && revset_ok "${bmname}@${remote}"; then
  ahead=$(count "${bmname}@${remote}..${bmname}")
  behind=$(count "${bmname}..${bmname}@${remote}")
  [ "${ahead:-0}" -gt 0 ] 2>/dev/null && remote_group+="↑${ahead}"
  [ "${behind:-0}" -gt 0 ] 2>/dev/null && remote_group+="↓${behind}"
fi

dirty=""
if [ -z "$is_empty" ]; then
  files=$("${jj[@]}" diff -r '@' --summary 2>/dev/null | grep -c .)
  dirty="*${files}"
fi

# Assemble: conflict+remote joined tight; a space before dirty only when a remote
# group is present (e.g. "↓1 *1", but "!*2" and "*2").
sep=""; [ -n "$remote_group" ] && [ -n "$dirty" ] && sep=" "
status="${conflict}${remote_group}${sep}${dirty}"

printf '%s\t%s\n' "$bookmark" "$status"

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

# Bare bookmark name(s), with "??" appended for a conflicted bookmark. jj's own
# "*" out-of-sync marker is intentionally dropped — we compute precise ↑↓ instead.
BM_T='local_bookmarks.map(|b| b.name() ++ if(b.conflict(), "??", "")).join(" ")'

tmpl() { "${jj[@]}" log -r "$1" --no-graph -T "$2" 2>/dev/null; }

# Every fact about @ in one read (pipe-delimited so empty fields survive parsing;
# a tab IFS would collapse them). Includes the dirty file count. A failure here
# also means "not a jj repo".
at="$(tmpl '@' 'if(conflict,"1","") ++ "|" ++ if(empty,"1","") ++ "|" ++ if(divergent,"1","") ++ "|" ++ change_id.shortest() ++ "|" ++ self.diff().files().len() ++ "|" ++ '"$BM_T")" || exit 3
IFS='|' read -r is_conflict is_empty is_divergent changeid files bookmark <<<"$at"

# --- $jj_bookmark ---------------------------------------------------------
# bmname = the single bookmark used for remote comparison ("" if none).
bmname=""
if [ -n "$bookmark" ]; then
  # On one or more local bookmarks -> just the name(s), no change id.
  bmname="${bookmark%% *}"; bmname="${bmname%'??'}"
else
  # Off any bookmark: anchor on the current change id.
  nearest="$(tmpl 'heads(::@ & bookmarks())' "${BM_T} ++ \"\\n\"" | grep -v '^$' | head -1)"
  if [ -n "$nearest" ]; then
    # Descendant of an ancestor bookmark: "<nearest>:: @id" (no depth count).
    bmname="${nearest%% *}"; bmname="${bmname%'??'}"
    bookmark="${nearest}:: @${changeid}"
  else
    # No bookmark anywhere: just the change id ("??" if divergent).
    bookmark="@${changeid}"
    [ -n "$is_divergent" ] && bookmark="${bookmark}??"
  fi
fi

# --- $jj_status : "! ↑A↓D *N" --------------------------------------------
conflict=""; [ -n "$is_conflict" ] && conflict="!"

# Remote ahead/behind in a single call: over the union of both ranges, tag each
# commit by which side it's on. A failing call means the bookmark has no remote.
remote_group=""
if [ -n "$bmname" ]; then
  ahead_rs="${bmname}@${remote}..${bmname}"
  behind_rs="${bmname}..${bmname}@${remote}"
  if sides="$("${jj[@]}" log -r "${ahead_rs} | ${behind_rs}" --no-graph \
       -T 'if(self.contained_in("'"$ahead_rs"'"), "a\n", "b\n")' 2>/dev/null)"; then
    ahead=$(grep -c a <<<"$sides"); behind=$(grep -c b <<<"$sides")
    [ "$ahead" -gt 0 ] && remote_group+="↑${ahead}"
    [ "$behind" -gt 0 ] && remote_group+="↓${behind}"
  fi
fi

dirty=""; [ -z "$is_empty" ] && dirty="*${files}"

# Assemble: conflict+remote joined tight; a space before dirty only when a remote
# group is present (e.g. "↓1 *1", but "!*2" and "*2").
sep=""; [ -n "$remote_group" ] && [ -n "$dirty" ] && sep=" "
printf '%s\t%s\n' "$bookmark" "${conflict}${remote_group}${sep}${dirty}"

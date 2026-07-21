#!/usr/bin/env bash
# refresh.sh — short-lived. Report the jj bookmark/status tokens for one or all
# workspaces, then exit. herdr invokes this from [[events]] hooks and the
# [[actions]] entry; there is no long-lived process and nothing persists here.
#
# Event hook:  HERDR_PLUGIN_CONTEXT_JSON identifies the affected workspace, so we
#              refresh just that one (no api snapshot needed).
# Action/none: no context -> sweep every workspace via `herdr api snapshot`.

set -u

SOURCE="mroth.jj-status"
HERDR="${HERDR_BIN_PATH:-herdr}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPUTE="$HERE/../lib/compute.sh"
MAXLEN=48   # keep sidebar tokens compact

# report <workspace_id> <cwd>
report() {
  local wsid="$1" cwd="$2" line bookmark status
  [ -n "$wsid" ] || return 0

  if [ -z "$cwd" ] || ! line="$(bash "$COMPUTE" "$cwd")"; then
    # Not a jj repo (or no cwd): clear tokens so nothing stale lingers.
    "$HERDR" workspace report-metadata "$wsid" --source "$SOURCE" \
      --clear-token jj_bookmark --clear-token jj_status >/dev/null 2>&1
    return 0
  fi

  bookmark="${line%%$'\t'*}"
  status="${line#*$'\t'}"
  # Truncate overly long values (e.g. change-id + long description).
  [ "${#bookmark}" -gt "$MAXLEN" ] && bookmark="${bookmark:0:MAXLEN-1}…"

  "$HERDR" workspace report-metadata "$wsid" --source "$SOURCE" \
    --token "jj_bookmark=$bookmark" --token "jj_status=$status" >/dev/null 2>&1
}

# --- single workspace from the event context, if present ---
ctx="${HERDR_PLUGIN_CONTEXT_JSON:-}"
if [ -n "$ctx" ]; then
  wsid="$(printf '%s' "$ctx" | jq -r '.workspace_id // empty' 2>/dev/null)"
  if [ -n "$wsid" ]; then
    cwd="$(printf '%s' "$ctx" | jq -r '.workspace_cwd // .focused_pane_cwd // empty' 2>/dev/null)"
    report "$wsid" "$cwd"
    exit 0
  fi
fi

# --- sweep all workspaces (action / no context) ---
# Map each workspace to its focused pane's cwd (else its first pane's cwd).
snap="$("$HERDR" api snapshot 2>/dev/null)" || exit 0
printf '%s' "$snap" | jq -r '
  .result.snapshot as $s
  | ($s.panes // []) as $panes
  | ($s.workspaces // [])[]
  | .workspace_id as $w
  | ( [ $panes[] | select(.workspace_id == $w and .focused) ][0]
      // [ $panes[] | select(.workspace_id == $w) ][0] ) as $p
  | "\($w)\t\($p.cwd // "")"
' 2>/dev/null | while IFS=$'\t' read -r wsid cwd; do
  report "$wsid" "$cwd"
done

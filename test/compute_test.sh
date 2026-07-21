#!/usr/bin/env bash
# Dependency-free tests for lib/compute.sh (no bats needed).
# Creates throwaway jj repos in isolated temp dirs (own JJ_CONFIG, so your global
# jj config is never touched) and asserts the computed "<bookmark>\t<status>".
#
# Usage: bash test/compute_test.sh

set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
compute="$here/../lib/compute.sh"

pass=0
fail=0

cfg="$(mktemp -d)"
cat >"$cfg/config.toml" <<'EOF'
[user]
name = "Test"
email = "test@example.com"
EOF
export JJ_CONFIG="$cfg/config.toml"

tmp=()
cleanup() { rm -rf "$cfg" ${tmp[@]+"${tmp[@]}"}; }
trap cleanup EXIT

mktmp() { local d; d="$(mktemp -d)"; tmp+=("$d"); printf '%s' "$d"; }

# A repo. Use `j <dir> ...` for setup commands (these DO snapshot the working copy).
new_repo() { local d; d="$(mktmp)"; jj --no-pager git init "$d" >/dev/null 2>&1; printf '%s' "$d"; }
j() { local d="$1"; shift; jj --no-pager -R "$d" "$@" >/dev/null 2>&1; }
snap() { jj --no-pager -R "$1" status >/dev/null 2>&1; }   # force working-copy snapshot
cid() { jj --no-pager --ignore-working-copy -R "$1" log -r "$2" --no-graph -T 'change_id' 2>/dev/null; }

# A bare git remote wired as `origin`.
add_origin() { local d="$1" o; o="$(mktmp)/o.git"; git init --bare -q "$o"; j "$d" git remote add origin "$o"; }

run() { bash "$compute" "$1"; }

check() {
  local name="$1" expect="$2" got="$3"
  if [ "$got" = "$expect" ]; then printf 'ok   %s\n' "$name"; pass=$((pass+1))
  else printf 'FAIL %s\n       expected: [%s]\n       got:      [%s]\n' "$name" "$expect" "$got"; fail=$((fail+1)); fi
}
check_re() {
  local name="$1" re="$2" got="$3"
  if [[ "$got" =~ $re ]]; then printf 'ok   %s\n' "$name"; pass=$((pass+1))
  else printf 'FAIL %s\n       expected match: /%s/\n       got:            [%s]\n' "$name" "$re" "$got"; fail=$((fail+1)); fi
}

# --- bookmark resolution --------------------------------------------------

# 1. on a local bookmark, empty @ -> "feat\t"
r="$(new_repo)"; j "$r" describe -m init; j "$r" bookmark create feat -r @; snap "$r"
check "on bookmark, clean" $'feat\t' "$(run "$r")"

# 2. several local bookmarks on @ -> "feat wip\t"
r="$(new_repo)"; j "$r" describe -m init
j "$r" bookmark create feat -r @; j "$r" bookmark create wip -r @; snap "$r"
check "several bookmarks" $'feat wip\t' "$(run "$r")"

# 3. dirty descendant of bookmark (1 deep) -> "main:: @id\t*1"
r="$(new_repo)"; j "$r" describe -m init; j "$r" bookmark create main -r @
j "$r" new; echo x > "$r/a.txt"; snap "$r"
check_re "descendant (1 deep), dirty" '^main:: @[a-z0-9]+'$'\t''\*1$' "$(run "$r")"

# 4. deep descendant (still just "main:: @id", no count) -> clean @ on top
r="$(new_repo)"; j "$r" describe -m base; j "$r" bookmark create main -r @
j "$r" new -m c1; echo 1 > "$r/f1"; snap "$r"
j "$r" new -m c2; echo 2 > "$r/f2"; snap "$r"
j "$r" new; snap "$r"                    # empty @ several deep
check_re "descendant (deep), clean" '^main:: @[a-z0-9]+'$'\t''$' "$(run "$r")"

# 5. no bookmark -> just "@id" (no description, ever)
r="$(new_repo)"; j "$r" describe -m solo; snap "$r"
check_re "no bookmark -> @id only" '^@[a-z0-9]+'$'\t''$' "$(run "$r")"

# --- $jj_status: remote ahead/behind -------------------------------------

# 6. bookmark in sync with origin -> no ↑↓
r="$(new_repo)"; add_origin "$r"; j "$r" describe -m base; j "$r" bookmark create main -r @
j "$r" git push -b main; snap "$r"
check "remote in sync" $'main\t' "$(run "$r")"

# 7. 2 commits ahead of origin, sitting on main -> "main\t↑2"
# (empty commits so @ on main stays clean -> no *N; ahead count is topological)
r="$(new_repo)"; add_origin "$r"; j "$r" describe -m base; j "$r" bookmark create main -r @
j "$r" git push -b main
j "$r" new -m c1; j "$r" new -m c2                 # two empty commits
j "$r" bookmark set main -r @; snap "$r"           # main = c2 = @ (empty)
check "remote ahead" $'main\t↑2' "$(run "$r")"

# 8. behind origin -> "main\t↓2": push main at c2, rewind local main to base, sit on it
r="$(new_repo)"; add_origin "$r"; j "$r" describe -m base; base_id="$(cid "$r" @)"
j "$r" bookmark create main -r @
j "$r" new -m c1; echo 1 > "$r/f1"; snap "$r"
j "$r" new -m c2; echo 2 > "$r/f2"; snap "$r"
j "$r" bookmark set main -r @; j "$r" git push -b main             # origin main = c2
j "$r" bookmark set main -r "$base_id" --allow-backwards
j "$r" edit "$base_id" --ignore-immutable; snap "$r"              # @ = base = local main
check "remote behind" $'main\t↓2' "$(run "$r")"

# --- $jj_status: dirty + conflict ----------------------------------------

# 9. descendant with dirty @ + file count -> "main:: @id\t*1"
r="$(new_repo)"; j "$r" describe -m base; j "$r" bookmark create main -r @
j "$r" new -m c1; echo 1 > "$r/f1"; snap "$r"
j "$r" new -m c2; echo 2 > "$r/wip"; snap "$r"    # @ = c2, dirty
check_re "descendant, dirty + file count" '^main:: @[a-z0-9]+'$'\t''\*1$' "$(run "$r")"

# 10. conflicted @ (merge of two siblings that edit the same file) -> status has "!"
r="$(new_repo)"
j "$r" describe -m base; printf 'a\n' > "$r/c.txt"; snap "$r"
j "$r" bookmark create main -r @
j "$r" new main -m x; printf 'x\n' > "$r/c.txt"; snap "$r"; x_id="$(cid "$r" @)"
j "$r" new main -m y; printf 'y\n' > "$r/c.txt"; snap "$r"; y_id="$(cid "$r" @)"
j "$r" new "$x_id" "$y_id" -m merge; snap "$r"
out="$(run "$r")"
check_re "conflict marker present" $'\t''!' "$out"

# --- non-jj --------------------------------------------------------------
d="$(mktmp)"
out="$(run "$d")"; rc=$?
check "non-jj exit code" "3" "$rc"
check "non-jj no output" "" "$out"

echo
echo "----- $pass passed, $fail failed -----"
[ "$fail" -eq 0 ]

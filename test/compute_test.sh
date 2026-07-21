#!/usr/bin/env bash
# Dependency-free tests for lib/compute.sh.
# Creates throwaway jj repos in isolated temp dirs (own JJ_CONFIG, so your global
# jj config is never touched) and asserts the computed "<bookmark>\t<status>".
#
# Usage: bash test/compute_test.sh

set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
compute="$here/../lib/compute.sh"

pass=0
fail=0

# Isolated jj config so commits have an author and nothing reads the real config.
cfg="$(mktemp -d)"
cat >"$cfg/config.toml" <<'EOF'
[user]
name = "Test"
email = "test@example.com"
EOF
export JJ_CONFIG="$cfg/config.toml"

cleanup() { rm -rf "$cfg" "${repos[@]}"; }
repos=()
trap cleanup EXIT

new_repo() {
  local d; d="$(mktemp -d)"; repos+=("$d")
  jj --no-pager git init "$d" >/dev/null 2>&1
  printf '%s' "$d"
}

# jj() convenience that never blocks and targets $1's repo (rest are args)
jjr() { local d="$1"; shift; jj --no-pager -R "$d" "$@" >/dev/null 2>&1; }

# Force a working-copy snapshot so compute.sh (--ignore-working-copy) sees it.
snap() { jj --no-pager -R "$1" log -r @ >/dev/null 2>&1; }

check() {
  local name="$1" expect="$2" got="$3"
  if [ "$got" = "$expect" ]; then
    printf 'ok   %s\n' "$name"; pass=$((pass+1))
  else
    printf 'FAIL %s\n       expected: [%s]\n       got:      [%s]\n' "$name" "$expect" "$got"
    fail=$((fail+1))
  fi
}
check_re() {
  local name="$1" re="$2" got="$3"
  if [[ "$got" =~ $re ]]; then
    printf 'ok   %s\n' "$name"; pass=$((pass+1))
  else
    printf 'FAIL %s\n       expected match: /%s/\n       got:            [%s]\n' "$name" "$re" "$got"
    fail=$((fail+1))
  fi
}

# 1. local bookmark on @ (empty working copy) -> "feat\t"
r="$(new_repo)"
jjr "$r" describe -m init
jjr "$r" bookmark create feat -r @
snap "$r"
check "bookmark on @ (clean)" $'feat\t' "$(bash "$compute" "$r")"

# 2. ancestor bookmark + non-empty commits ahead -> "base\t+2"
r="$(new_repo)"
jjr "$r" describe -m base
jjr "$r" bookmark create base -r @
jjr "$r" new -m work1;  echo a > "$r/a.txt"; snap "$r"
jjr "$r" new -m work2;  echo b > "$r/b.txt"; snap "$r"
jjr "$r" new                      # fresh empty @ on top
snap "$r"
check "ancestor bookmark + ahead" $'base\t+2' "$(bash "$compute" "$r")"

# 3. no bookmark anywhere -> change-id fallback (8 lowercase alnum), empty status
r="$(new_repo)"
jjr "$r" describe -m solo
snap "$r"
check_re "no bookmark -> change id + desc" '^[a-z0-9]{8} solo'$'\t''$' "$(bash "$compute" "$r")"

# 4. dirty working copy (non-empty @) on a bookmark -> "feat\t*"
r="$(new_repo)"
jjr "$r" describe -m init
jjr "$r" bookmark create feat -r @
echo dirty > "$r/wip.txt"; snap "$r"
check "dirty working copy" $'feat\t*' "$(bash "$compute" "$r")"

# 5. not a jj repo -> exit 3, no output
d="$(mktemp -d)"; repos+=("$d")
out="$(bash "$compute" "$d")"; rc=$?
check "non-jj exit code" "3" "$rc"
check "non-jj no output" "" "$out"

echo
echo "----- $pass passed, $fail failed -----"
[ "$fail" -eq 0 ]

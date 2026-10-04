#!/usr/bin/env bash
. "$(dirname -- "$0")/self-test-env.sh" || exit 1
# test-harness-state-gc.sh — the GC removes what the harness left, and nothing a file name can point at.
#
# H2 found the marker sweep read `find` output line by line. A marker named "x<newline>victim"
# split into two lines, the second a relative path resolved against the hook's cwd (the project
# root), and `rm -rf` took it. `.git` is one component, so a hostile repo could ship that name.
#
#   bash scripts/test-harness-state-gc.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
GC="$HERE/harness-state-gc.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# $1 case dir. A project with .git, a victim dir, and the marker dir.
mkproj() {
  mkdir -p "$1/.git" "$1/.claude/state/bash-write" "$1/victim"
  printf 'keep\n' > "$1/victim/file"
}
run_gc() { ( cd "$1" && CLAUDE_PROJECT_DIR="$1" bash "$GC" "${@:2}" >/dev/null 2>&1 ); }

echo "== 1. a newline in a marker name cannot reach outside the marker dir =="
P="$TMP/nl"; mkproj "$P"
M="$P/.claude/state/bash-write/x
victim"
: > "$M"; touch -t 202001010000 "$M"
run_gc "$P"
[ -f "$P/victim/file" ] && ok "the project path named by the second line survives" \
  || bad "victim/ was deleted through a marker name"
[ -e "$M" ] && bad "the stale marker itself was left" || ok "the stale marker is removed"

echo "== 2. ordinary stale markers go, fresh ones stay =="
P="$TMP/plain"; mkproj "$P"
OLD="$P/.claude/state/bash-write/old-marker"; NEW="$P/.claude/state/bash-write/new-marker"
: > "$OLD"; : > "$NEW"; touch -t 202001010000 "$OLD"
run_gc "$P"
[ -e "$OLD" ] && bad "a marker older than a day was kept" || ok "a marker older than a day is removed"
[ -e "$NEW" ] && ok "a fresh marker is kept" || bad "a fresh marker was removed"

echo "== 3. --dry-run removes nothing =="
P="$TMP/dry"; mkproj "$P"
OLD="$P/.claude/state/bash-write/old-marker"; : > "$OLD"; touch -t 202001010000 "$OLD"
run_gc "$P" --dry-run
[ -e "$OLD" ] && ok "--dry-run keeps the stale marker" || bad "--dry-run removed a marker"

# Spec 098 R6: guard_announce stamps live under the git dir, one directory per session.
GN="$P/.git/claude-hook-notices"; mkdir -p "$GN/old-session" "$GN/new-session"
touch -t 202001010000 "$GN/old-session"
run_gc "$P"
[ ! -e "$GN/old-session" ] && ok "098-R6 a stale stamp directory in the git dir is swept" || bad "098-R6 the git-dir stamps are never collected"
[ -d "$GN/new-session" ] && [ -d "$GN" ] && ok "  a fresh one, and the base, stay" || bad "  the sweep removed a fresh session or the base"

printf '\npassed %d, failed %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

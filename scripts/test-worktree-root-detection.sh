#!/usr/bin/env bash
# Regression: a git worktree's .git is a FILE, and every project-root finder used `[ -d .../.git ]`, so in
# a worktree they walked to / and reported "not inside a git repository". template-autosync.sh --owed then
# exited 0 ("owed"), and the tick guard refused every tick in every worktree (msroute spec 028, 2026-11-03).
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d); trap 'rm -r "$work"' EXIT
git -C "$work" init -q main && git -C "$work/main" commit -q --allow-empty -m init
git -C "$work/main" worktree add -q "$work/wt" -b wt
[ -f "$work/wt/.git" ] || { echo "FAIL setup: worktree .git is not a file"; exit 1; }
fail=0
# No root finder may still test for a .git directory only.
if grep -nE '\[ -d "\$(DIR|ROOT|_RL_ROOT)/\.git" \]' "$here"/scripts/*.sh; then echo "FAIL a root finder still requires .git to be a directory"; fail=1; fi
# The predicate the finders now use accepts the worktree.
[ -e "$work/wt/.git" ] && echo "ok   a worktree root is found" || { echo "FAIL worktree root"; fail=1; }
exit $fail

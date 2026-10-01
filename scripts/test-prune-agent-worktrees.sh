#!/bin/bash
# Self-test for spec 082 R10 in scripts/prune-agent-worktrees.sh (F064).
#
#   bash scripts/test-prune-agent-worktrees.sh
#
# What is under test: a worktree is removed only when it provably holds nothing the main repo lacks —
# its HEAD commit (detached or not) is reachable from main's HEAD, nothing tracked is modified and
# nothing untracked exists outside .claude/agent-memory/. Anything else is KEEP, with the reason.
#
# Cases: 082-AC-4 (prune keeps unmerged or untracked agent work).
#
# Fixture-only: real `git worktree add` under a throwaway repo in mktemp. No network. bash 3.2-safe.

set -u

DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$DIR/prune-agent-worktrees.sh"
TMP=$(mktemp -d 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/prune-test.$$")
mkdir -p "$TMP"
TMP=$(cd "$TMP" && pwd -P)   # macOS /var -> /private/var: git reports worktrees by real path
PASS=0
FAIL=0
trap 'rm -rf "$TMP"' EXIT

ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"; }
expect_eq()       { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }
expect_contains() { if grep -Fq -e "$2" <<< "$3"; then ok "$1"; else bad "$1" "contains: $2" "$3"; fi; }
exists()  { if [ -d "$2" ]; then ok "$1"; else bad "$1" "directory exists" "gone: $2"; fi; }
gone()    { if [ -d "$2" ]; then bad "$1" "removed" "still there: $2"; else ok "$1"; fi; }

# The grace window (adversarial review F8) would keep every worktree these fixtures just made, so it is
# off by default here; the grace case below turns it back on.
export PRUNE_GRACE_HOURS=0
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

mkrepo() { # mkrepo NAME -> path, one commit, .claude/worktrees ignored like a real project
  local r="$TMP/$1"; mkdir -p "$r"
  ( cd "$r" && git init -q . && printf '.claude/worktrees/\nbin/\n' > .gitignore && echo a > a.txt \
    && git add . && git commit -q -m init )
  printf '%s' "$r"
}
wt() { # wt REPO NAME [git worktree add args...] — creates .claude/worktrees/agent-NAME
  local r="$1" n="$2"; shift 2
  ( cd "$r" && mkdir -p .claude/worktrees && git worktree add -q "$@" ".claude/worktrees/agent-$n" >/dev/null 2>&1 )
}
commit_in() { ( cd "$1" && echo "$2" > "$2.txt" && git add "$2.txt" && git commit -q -m "$2" ); }

echo "prune-agent-worktrees.sh (spec 082 R10)"

# --- 082-AC-4: detached HEAD with an unmerged commit, and an untracked-only worktree ------------
R=$(mkrepo ac4)
wt "$R" detached --detach
commit_in "$R/.claude/worktrees/agent-detached" unmerged
wt "$R" untracked -b agent-untracked
echo new > "$R/.claude/worktrees/agent-untracked/newfile.cs"
OUT=$(bash "$SCRIPT" --repo "$R" 2>&1); RC=$?
exists          "082-AC-4 detached HEAD with an unmerged commit is kept" "$R/.claude/worktrees/agent-detached"
exists          "082-AC-4 worktree with only an untracked file is kept"  "$R/.claude/worktrees/agent-untracked"
expect_contains "082-AC-4 detached worktree reported KEEP"   "KEEP .claude/worktrees/agent-detached" "$OUT"
expect_contains "082-AC-4 detached reason names the commit"  "not in HEAD" "$OUT"
expect_contains "082-AC-4 detached state is named"           "detached" "$OUT"
expect_contains "082-AC-4 untracked worktree reported KEEP"  "KEEP .claude/worktrees/agent-untracked" "$OUT"
expect_contains "082-AC-4 untracked reason names the file"   "untracked files outside agent-memory: newfile.cs" "$OUT"
expect_eq       "R10 something kept -> exit 1"              "1" "$RC"

# --- merged, clean branch worktree: removed ---------------------------------------------------
R=$(mkrepo merged)
wt "$R" merged -b agent-merged
OUT=$(bash "$SCRIPT" --repo "$R" 2>&1); RC=$?
gone            "R10 merged clean worktree removed"          "$R/.claude/worktrees/agent-merged"
expect_eq       "R10 nothing kept -> exit 0"                "0" "$RC"

# --- detached HEAD already in main's history: removed -----------------------------------------
R=$(mkrepo detmerged)
wt "$R" det --detach
bash "$SCRIPT" --repo "$R" >/dev/null 2>&1
gone            "R10 detached worktree at a merged commit removed" "$R/.claude/worktrees/agent-det"

# --- only untracked agent memory: salvaged, then removed --------------------------------------
R=$(mkrepo memory)
wt "$R" mem -b agent-mem
mkdir -p "$R/.claude/worktrees/agent-mem/.claude/agent-memory/reviewer"
echo "finding" > "$R/.claude/worktrees/agent-mem/.claude/agent-memory/reviewer/x.md"
OUT=$(bash "$SCRIPT" --repo "$R" 2>&1)
gone            "R10 agent-memory-only worktree removed"     "$R/.claude/worktrees/agent-mem"
expect_eq       "R10 its memory was salvaged first"          "finding" "$(cat "$R/.claude/agent-memory/reviewer/x.md" 2>/dev/null)"

# --- ignored build output does not keep a worktree --------------------------------------------
R=$(mkrepo ignored)
wt "$R" build -b agent-build
mkdir -p "$R/.claude/worktrees/agent-build/bin" && echo x > "$R/.claude/worktrees/agent-build/bin/out.dll"
bash "$SCRIPT" --repo "$R" >/dev/null 2>&1
gone            "R10 ignored bin/ output does not keep it"   "$R/.claude/worktrees/agent-build"

# --- modified tracked file keeps; a path with a space is named whole --------------------------
R=$(mkrepo modified)
( cd "$R" && echo s > "with space.txt" && git add . && git commit -q -m sp )
wt "$R" mod -b agent-mod
echo changed > "$R/.claude/worktrees/agent-mod/with space.txt"
OUT=$(bash "$SCRIPT" --repo "$R" 2>&1)
exists          "R10 modified tracked file keeps"            "$R/.claude/worktrees/agent-mod"
expect_contains "R10 a path with a space is named whole"     "with space.txt" "$OUT"

# --- branch with an unmerged commit keeps -----------------------------------------------------
R=$(mkrepo branch)
wt "$R" br -b agent-br
commit_in "$R/.claude/worktrees/agent-br" work
OUT=$(bash "$SCRIPT" --repo "$R" 2>&1)
exists          "R10 branch with an unmerged commit is kept" "$R/.claude/worktrees/agent-br"
expect_contains "R10 its reason names the commit"           "not in HEAD" "$OUT"

# --- a worktree git cannot read: kept, never guessed as empty ---------------------------------
R=$(mkrepo broken)
wt "$R" broken -b agent-broken
printf 'gitdir: %s\n' "$TMP/nowhere" > "$R/.claude/worktrees/agent-broken/.git"
OUT=$(bash "$SCRIPT" --repo "$R" 2>&1)
exists          "R10 unreadable worktree is kept"            "$R/.claude/worktrees/agent-broken"
expect_contains "R10 its reason says it cannot tell"         "cannot tell what is unique" "$OUT"

# --- --dry-run removes nothing ----------------------------------------------------------------
R=$(mkrepo dry)
wt "$R" dry -b agent-dry
OUT=$(bash "$SCRIPT" --repo "$R" --dry-run 2>&1)
exists          "R10 --dry-run removes nothing"              "$R/.claude/worktrees/agent-dry"
expect_contains "R10 --dry-run says what it would remove"    "would be removed" "$OUT"

# --- F8a: a symlinked agent-* entry is never followed or removed ------------------------------
R=$(mkrepo symlink)
( cd "$R" && git worktree add -q -b other "$TMP/symlink-other" >/dev/null 2>&1 )
mkdir -p "$R/.claude/worktrees" && ln -s "$TMP/symlink-other" "$R/.claude/worktrees/agent-link"
mkdir -p "$TMP/symlink-other/.claude/agent-memory" && echo planted > "$TMP/symlink-other/.claude/agent-memory/p.md"
bash "$SCRIPT" --repo "$R" >/dev/null 2>&1
exists          "F8a the symlink target worktree survives"   "$TMP/symlink-other"
if [ -L "$R/.claude/worktrees/agent-link" ]; then ok "F8a the symlinked entry is left alone"
else bad "F8a the symlinked entry is left alone" "symlink still there" "gone"; fi
if [ -e "$R/.claude/agent-memory/p.md" ]; then bad "F8a nothing salvaged through the symlink" "absent" "copied"
else ok "F8a nothing salvaged through the symlink"; fi

# --- F8b: the grace window keeps a worktree active within N hours ---------------------------------
R=$(mkrepo grace)
wt "$R" fresh -b agent-fresh
OUT=$(PRUNE_GRACE_HOURS=24 bash "$SCRIPT" --repo "$R" 2>&1)
exists          "F8b a fresh worktree is kept inside the grace window" "$R/.claude/worktrees/agent-fresh"
expect_contains "F8b its reason names the window"            "active within 24h" "$OUT"
GD=$(git -C "$R/.claude/worktrees/agent-fresh" rev-parse --git-dir)
touch -t 202001010000 "$R/.claude/worktrees/agent-fresh" "$GD/HEAD" "$GD/index"
PRUNE_GRACE_HOURS=24 bash "$SCRIPT" --repo "$R" >/dev/null 2>&1
gone            "F8b the same worktree, aged past the window, is removed" "$R/.claude/worktrees/agent-fresh"

# --- F8d: a memory path with a space cannot be word-split into a path outside the repo -------------
R=$(mkrepo split)
echo "outside secret" > "$TMP/secret.txt"
wt "$R" split -b agent-split
mkdir -p "$R/.claude/worktrees/agent-split/.claude/agent-memory/x .."
echo inside > "$R/.claude/worktrees/agent-split/.claude/agent-memory/x ../secret.txt"
bash "$SCRIPT" --repo "$R" >/dev/null 2>&1
if [ -e "$R/.claude/secret.txt" ]; then bad "F8d no file copied from outside the repo" "absent" "$(cat "$R/.claude/secret.txt")"
else ok "F8d no file copied from outside the repo"; fi
expect_eq       "F8d the real memory file is salvaged whole" "inside" "$(cat "$R/.claude/agent-memory/x ../secret.txt" 2>/dev/null)"

# --- GAP-3: a write between the first status read and the re-check keeps the worktree ---------------
R=$(mkrepo recheck)
wt "$R" recheck -b agent-recheck
W="$R/.claude/worktrees/agent-recheck"
OUT=$(PRUNE_TEST_BEFORE_RECHECK="echo late > '$W/late.txt'" bash "$SCRIPT" --repo "$R" 2>&1)
exists          "GAP-3 a file written before the re-check keeps the worktree" "$W"
expect_contains "GAP-3 it says the files changed" "its files changed while this ran" "$OUT"

# --- GAP-1: a write between the re-check and the removal is refused by git, not deleted -------------
R=$(mkrepo window)
wt "$R" window -b agent-window
W="$R/.claude/worktrees/agent-window"
OUT=$(PRUNE_TEST_BEFORE_REMOVE="echo late > '$W/late.txt'" bash "$SCRIPT" --repo "$R" 2>&1)
exists          "GAP-1 a file written after the re-check survives (no --force)" "$W"
expect_eq       "GAP-1 the late file is intact" "late" "$(cat "$W/late.txt" 2>/dev/null)"
expect_contains "GAP-1 it says git refused" "git refused the removal" "$OUT"

# --- GAP-1: agent-memory dirt (already salvaged) still lets a plain remove through ------------------
R=$(mkrepo memonly)
wt "$R" memonly -b agent-memonly
W="$R/.claude/worktrees/agent-memonly"
mkdir -p "$W/.claude/agent-memory"; echo note > "$W/.claude/agent-memory/n.md"
bash "$SCRIPT" --repo "$R" >/dev/null 2>&1
gone            "GAP-1 an agent-memory-only worktree is still removed without --force" "$W"
expect_eq       "GAP-1 its memory was salvaged first" "note" "$(cat "$R/.claude/agent-memory/n.md" 2>/dev/null)"

echo
echo "prune-agent-worktrees: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

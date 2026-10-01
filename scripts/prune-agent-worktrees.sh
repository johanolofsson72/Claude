#!/bin/bash
# Reclaim abandoned agent worktrees — WITHOUT eating the memory they hold.
#
# Agent worktrees (.claude/worktrees/agent-*, created by `isolation: worktree`)
# are meant to be disposable, but two things accumulate in them:
#
#   1. Disk. They are full checkouts. Eight of them in one repo is gigabytes.
#   2. Agent memory. A subagent running inside a worktree writes to that
#      worktree's .claude/agent-memory/, and nothing ever merges it back. In
#      originalilluminati the main repo had ZERO memory files while seven
#      throwaway directories held sixteen — including two OPEN security findings.
#      Deleting worktrees to reclaim disk destroys exactly the knowledge the
#      agents were run to produce.
#
# So this salvages first and deletes second, and it only deletes what is provably
# safe: a worktree whose HEAD commit (branch or detached) is reachable from the
# main repo's HEAD, with no modified tracked files and no untracked files outside
# .claude/agent-memory/. Anything else, including any question git cannot answer,
# is reported and left alone — an agent may still be working in it (spec 082).
#
# Usage:
#   prune-agent-worktrees.sh [--dry-run] [--repo <path>]
#     --dry-run   report what would be salvaged/removed, change nothing
#     --repo      operate on this repo (default: cwd's repo root)
#
# Exit codes: 0 = done (possibly nothing to do), 1 = something was left behind
# for a human to look at, 2 = usage error.
#
# bash 3.2-safe, cross-platform.

set -u

DRY=0
REPO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --repo)    shift; REPO="${1:-}" ;;
    -h|--help) grep -E '^#( |$)' "$0" | sed -e 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

[ -n "$REPO" ] || REPO=$(git rev-parse --show-toplevel 2>/dev/null)
[ -n "$REPO" ] && [ -d "$REPO/.git" ] || { echo "not a git repository: ${REPO:-$PWD}" >&2; exit 2; }
cd "$REPO" || exit 2

NAME=$(basename "$REPO")
ls -d .claude/worktrees/agent-* >/dev/null 2>&1 || { echo "$NAME: no agent worktrees"; exit 0; }

SALVAGED=0; REMOVED=0; KEPT=0

# ------------------------------------------------------------------- salvage
# Copy every memory file that exists ONLY inside a worktree into the main repo.
# Never overwrite: the main copy, if present, is the authority.
# Adversarial review F8. NUL-delimited, never `for f in $(find …)`: that word-split a memory path
# such as `x ../secret.txt` into `../secret.txt`, which cp then copied in from OUTSIDE the repo. And a
# symlinked worktree entry is never walked, so its target's files are never salvaged as "memory".
memory_files() { # memory_files -type f | -name MEMORY.md  -> NUL-delimited paths
  for _w in .claude/worktrees/*; do
    [ -d "$_w" ] && [ ! -L "$_w" ] && [ -d "$_w/.claude/agent-memory" ] || continue
    find "$_w/.claude/agent-memory" "$@" -print0 2>/dev/null
  done
}
while IFS= read -r -d '' f; do
  rel=${f#*/.claude/agent-memory/}
  case "$rel" in */MEMORY.md|MEMORY.md) continue ;; esac   # indexes merged below
  dest=".claude/agent-memory/$rel"

  # Absent from the main repo → straight copy.
  if [ ! -f "$dest" ]; then
    [ "$DRY" -eq 0 ] && { mkdir -p "$(dirname "$dest")" && cp "$f" "$dest"; }
    SALVAGED=$((SALVAGED + 1)); continue
  fi

  # Present and identical → nothing to do.
  cmp -s "$f" "$dest" && continue

  # Present but DIFFERENT: the worktree holds edits that exist nowhere else
  # (an agent updated a tracked memory file and never committed it). Overwriting
  # the main copy could drop what is already there, so keep both and let a human
  # reconcile — losing either side silently is the failure this script exists to
  # prevent. The suffix names the worktree the version came from.
  agent=$(printf '%s' "$f" | sed -n 's#.*/worktrees/\([^/]*\)/.*#\1#p')
  base=${dest%.*}; ext=${dest##*.}
  [ "$base" = "$dest" ] && side="$dest.from-$agent" || side="$base.from-$agent.$ext"
  if [ ! -f "$side" ]; then
    [ "$DRY" -eq 0 ] && { mkdir -p "$(dirname "$side")" && cp "$f" "$side"; }
    SALVAGED=$((SALVAGED + 1))
    DIVERGED="${DIVERGED:-}$(printf '\n    %s (kept as %s)' "$rel" "$(basename "$side")")"
  fi
done < <(memory_files -type f)

# Merge the per-worktree MEMORY.md index fragments into the main index, keeping
# every unique bullet. Each worktree only ever wrote its own run's line.
while IFS= read -r -d '' idx; do
  rel=${idx#*/.claude/agent-memory/}
  dest=".claude/agent-memory/$rel"
  [ "$DRY" -eq 1 ] && continue
  mkdir -p "$(dirname "$dest")"
  TMP="$dest.merge.$$"
  { [ -f "$dest" ] && cat "$dest"; cat "$idx"; } 2>/dev/null | grep '^- ' | sort -u > "$TMP.bullets"
  {
    if [ -f "$dest" ]; then grep -v '^- ' "$dest" 2>/dev/null; else
      printf '# MEMORY.md\n\nConsolidated from agent worktrees by scripts/prune-agent-worktrees.sh.\n\n'
    fi
    cat "$TMP.bullets"
  } > "$TMP" 2>/dev/null && mv "$TMP" "$dest"
  rm -f "$TMP" "$TMP.bullets" 2>/dev/null
done < <(memory_files -name MEMORY.md)

# ------------------------------------------------------ remove what is safe
# Spec 082 (F064). Every check below answers "is there anything here the main repo lacks?", and an
# answer git cannot give is KEEP. The old loop asked by BRANCH NAME: on a detached HEAD that name is
# the literal "HEAD", so `rev-list HEAD --not HEAD` ran in the main repo and counted zero, a failed
# rev-list also read as zero, untracked files were filtered out — and then `worktree remove --force`
# destroyed whatever an agent had not merged. Reachability is now asked of the worktree's HEAD
# commit, and untracked files outside agent-memory keep it like modified ones always did.
TAB=$(printf '\t')

# Adversarial review F8. A worktree an agent was given a moment ago sits at main's HEAD with a clean
# tree, so every check below calls it removable while the agent is still starting up. Anything active
# within PRUNE_GRACE_HOURS (default 24, matching project-maintenance.sh's window; 0 turns it off) is
# kept. Activity is the newest mtime of the worktree directory and its git dir's HEAD and index.
GRACE_H=${PRUNE_GRACE_HOURS:-24}
case "$GRACE_H" in ''|*[!0-9]*) GRACE_H=24 ;; esac
mtime_of() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }
newest_activity() { # newest_activity DIR -> epoch seconds (empty when nothing is readable)
  _gd=$(git -C "$1" rev-parse --absolute-git-dir 2>/dev/null)
  _n=""
  for _p in "$1" ${_gd:+"$_gd/HEAD"} ${_gd:+"$_gd/index"}; do
    [ -e "$_p" ] || continue
    _m=$(mtime_of "$_p"); case "$_m" in ''|*[!0-9]*) continue ;; esac
    [ -z "$_n" ] || [ "$_m" -gt "$_n" ] && _n=$_m
  done
  printf '%s' "$_n"
}
# The status read, as a function: it runs once to decide and once more just before the removal,
# so a file written between the two keeps the worktree.
# GIT_OPTIONAL_LOCKS=0: status must not refresh (rewrite) the index, which would move the activity
# timestamp the grace window reads and leave a lock file in an agent's worktree.
wt_status() { (set -o pipefail; GIT_OPTIONAL_LOCKS=0 git -C "$1" status --porcelain -z --untracked-files=all 2>/dev/null | tr '\0' '\n'); }

for d in .claude/worktrees/agent-*; do
  [ -d "$d" ] || continue
  if [ -L "$d" ]; then
    echo "  KEEP $d — a symlink, not a worktree this script made; never followed or removed"
    KEPT=$((KEPT + 1)); continue
  fi
  # Measured first: nothing below may touch the index before its mtime is read.
  if [ "$GRACE_H" -gt 0 ]; then
    LAST=$(newest_activity "$d")
    if [ -z "$LAST" ] || [ $(( $(date +%s) - LAST )) -lt $(( GRACE_H * 3600 )) ]; then
      echo "  KEEP $d — active within ${GRACE_H}h (an agent may still be starting; PRUNE_GRACE_HOURS=0 to override)"
      KEPT=$((KEPT + 1)); continue
    fi
  fi

  BR=$(git -C "$d" symbolic-ref --quiet --short HEAD 2>/dev/null)
  SHA=$(git -C "$d" rev-parse --verify --quiet HEAD 2>/dev/null)
  if [ -z "$SHA" ]; then
    echo "  KEEP $d — cannot tell what is unique (git cannot read its HEAD)"
    KEPT=$((KEPT + 1)); continue
  fi
  STATE=${BR:+branch $BR}; STATE=${STATE:-detached HEAD at $(printf '%.12s' "$SHA")}

  # Modified tracked files and untracked files both block removal — EXCEPT under
  # .claude/agent-memory/, which the salvage above has already preserved (identical, copied, or
  # kept side-by-side). Memory edits are the normal end state of an agent run; if they counted as
  # "still working", these worktrees could never be reclaimed at all. Ignored files (bin/, obj/,
  # node_modules/) never appear here, so build output does not keep a worktree.
  # -z output: one NUL-terminated record per path, so a space or an arrow in a name survives. A
  # rename carries its source as a second record with no status prefix; it is skipped, and if its
  # name happens to look like a prefixed record it can only add a KEEP, never remove one. pipefail
  # so a failed status is seen, not tr's exit 0. --untracked-files=all names each new file, not
  # just a new directory (`?? .claude/` would hide an agent-memory-only worktree behind a KEEP).
  if ! ST=$(wt_status "$d"); then
    echo "  KEEP $d — cannot tell what is unique (git status failed)"
    KEPT=$((KEPT + 1)); continue
  fi
  MODIFIED=""; UNTRACKED=""
  while IFS= read -r rec; do
    [ "${#rec}" -gt 3 ] && [ "${rec:2:1}" = " " ] || continue
    p=${rec:3}
    case "$p" in .claude/agent-memory/*) continue ;; esac
    case "$rec" in
      '?? '*) UNTRACKED="$UNTRACKED${UNTRACKED:+, }$p" ;;
      *)      MODIFIED="$MODIFIED${MODIFIED:+, }$p" ;;
    esac
  done <<EOF
$ST
EOF
  if [ -n "$MODIFIED" ]; then
    echo "  KEEP $d — modified outside agent-memory: $MODIFIED"
    KEPT=$((KEPT + 1)); continue
  fi
  if [ -n "$UNTRACKED" ]; then
    echo "  KEEP $d — untracked files outside agent-memory: $UNTRACKED"
    KEPT=$((KEPT + 1)); continue
  fi

  # 0 = reachable from main's HEAD, 1 = not, anything else (bad object, no HEAD) = cannot tell.
  git merge-base --is-ancestor "$SHA" HEAD >/dev/null 2>&1; ANC=$?
  if [ "$ANC" -eq 1 ]; then
    UNIQ=$(git rev-list --count "$SHA" --not HEAD 2>/dev/null)
    echo "  KEEP $d — $STATE has ${UNIQ:-some} commit(s) not in HEAD"
    KEPT=$((KEPT + 1)); continue
  elif [ "$ANC" -ne 0 ]; then
    echo "  KEEP $d — cannot tell what is unique ($STATE; git merge-base exit $ANC)"
    KEPT=$((KEPT + 1)); continue
  fi

  # A locked worktree means an agent claimed it. The lock reason carries the pid;
  # if that process is gone the lock is a crash leftover and the worktree is just
  # abandoned. If it is alive, an agent is working in there right now — leave it.
  LOCKREASON=$(git worktree list --porcelain 2>/dev/null | awk -v w="$PWD/$d" '
    $1=="worktree"{cur=$2} $1=="locked"{if(cur==w){$1="";print;exit}}')
  if [ -n "$LOCKREASON" ]; then
    LOCKPID=$(printf '%s' "$LOCKREASON" | sed -n 's/.*pid \([0-9][0-9]*\).*/\1/p')
    if [ -n "$LOCKPID" ] && kill -0 "$LOCKPID" 2>/dev/null; then
      echo "  KEEP $d — locked by a RUNNING agent (pid $LOCKPID)"
      KEPT=$((KEPT + 1)); continue
    fi
    echo "  (stale lock on $d — pid ${LOCKPID:-?} is gone; unlocking)"
    [ "$DRY" -eq 0 ] && git worktree unlock "$d" >/dev/null 2>&1
  fi

  if [ "$DRY" -eq 0 ]; then
    # Test seams (spec 082, GAP-3 and GAP-1): a command run just before the re-check, and one just
    # before the removal, so a test can play the agent writing into each window. Unset in normal use.
    [ -n "${PRUNE_TEST_BEFORE_RECHECK:-}" ] && eval "$PRUNE_TEST_BEFORE_RECHECK"
    if ! ST2=$(wt_status "$d") || [ "$ST2" != "$ST" ]; then
      echo "  KEEP $d — its files changed while this ran"
      KEPT=$((KEPT + 1)); continue
    fi
    # No --force (spec 082, GAP-1). PruneRace.tla found the last window: an agent idle past the grace
    # period writes between the re-check and the removal, and `remove --force` deletes it. Plain
    # `git worktree remove` makes git check for modified and untracked files itself, at removal time.
    # The one dirt this script accepts, .claude/agent-memory/, was salvaged above, so it is reset
    # first, and nothing else needs forcing.
    if [ -n "$ST2" ]; then
      git -C "$d" checkout -q -- .claude/agent-memory 2>/dev/null
      git -C "$d" clean -fdq -- .claude/agent-memory 2>/dev/null
    fi
    [ -n "${PRUNE_TEST_BEFORE_REMOVE:-}" ] && eval "$PRUNE_TEST_BEFORE_REMOVE"
    git worktree remove "$d" >/dev/null 2>&1 || { echo "  KEEP $d — git refused the removal (files changed, or the tree is not clean)"; KEPT=$((KEPT+1)); continue; }
    [ -n "$BR" ] && git branch -d "$BR" >/dev/null 2>&1
  fi
  REMOVED=$((REMOVED + 1))
done

[ "$DRY" -eq 0 ] && git worktree prune 2>/dev/null

printf '%s: %s memory file(s) salvaged · %s worktree(s) %s · %s kept\n' \
  "$NAME" "$SALVAGED" "$REMOVED" "$([ "$DRY" -eq 1 ] && echo 'would be removed' || echo removed)" "$KEPT"

[ "$SALVAGED" -gt 0 ] && [ "$DRY" -eq 0 ] && \
  echo "  → review + commit .claude/agent-memory/ — it was only in the worktrees until now"

[ -n "${DIVERGED:-}" ] && printf '  → %s\n%s\n' \
  "these memory files differed from the committed copy; BOTH versions kept, reconcile by hand:" "$DIVERGED"

[ "$KEPT" -gt 0 ] && exit 1
exit 0

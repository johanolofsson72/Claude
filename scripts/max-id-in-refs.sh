#!/bin/bash
# max-id-in-refs.sh — the highest id any lane has written, not just this checkout.
#
# WHY THIS EXISTS. Two allocators counted the LOCAL file and nothing else, and both collided the
# moment a second developer worked in parallel:
#
#   finding.sh (row 054)   numbered by counting ledger rows. agentcrm, 2026-09-17: origin/main held
#                          F141–F143 and the branch spec/044-named-refusals held three DIFFERENT
#                          F141–F143. merge=union on FINDINGS.md kept both sides without a conflict
#                          marker, so the collision was silent. A deleted line also freed its number.
#   scenario ids (060)     had no allocator at all. agentcrm measured 47 colliding SC-ids on
#                          2026-09-21; 26 of them were specs 052 and 055 both taking ids 1625..1650.
#
# The cure for both is the same: read the MAXIMUM id, never a count, and read it everywhere this
# clone can see — the working tree (uncommitted and untracked edits included) AND every local and
# remote-tracking branch. The other lane's pushed spec branch is a remote-tracking ref, so its ids
# are seen before its merge instead of at it.
#
# WHAT IT CANNOT SEE: ids the other lane has written but not pushed, and anything newer than this
# clone's last fetch. No local scan can; the residual is a push-early habit, and the stderr line
# says how old the fetch is so the reader can judge it.
#
# Usage:
#   bash scripts/max-id-in-refs.sh --regex '<ERE ending in the digits>' [--dir D] -- <pathspec>...
#
# Prints the highest id's digits exactly as written (padding kept, so a caller can keep the width),
# or nothing when no id exists anywhere. The digits are the trailing run of each match.
#
# --next <count> [--block <B>] prints instead the first id of a run of <count> free ids above the
# highest (row 110). With SPEC_LANE_SLOT=<k>/<n> (per machine, next to SPEC_OWNER) the id space is cut
# into blocks of B ids (block 0 = ids 1..B) and this lane only takes ids from blocks whose index is
# k-1 mod n, never crossing a block edge. Two lanes with different slots cannot draw the same id even
# when neither has pushed: the residual above, closed by construction. Unset: max + 1, as before.
# The --next output is bare digits; the caller pads.
#
# Exit: 0 ok (with or without a result) · 2 usage, a malformed SPEC_LANE_SLOT, or a run longer than B
set -uo pipefail
export LC_ALL=C

RE=""; DIR="."; NEXT=""; BLOCK=1
while [ $# -gt 0 ]; do
  case "$1" in
    --regex) RE="${2:-}"; shift 2 || { echo "max-id-in-refs.sh: --regex needs a pattern" >&2; exit 2; } ;;
    --dir)   DIR="${2:-.}"; shift 2 || { echo "max-id-in-refs.sh: --dir needs a path" >&2; exit 2; } ;;
    --next)  NEXT="${2:-}"; shift 2 || { echo "max-id-in-refs.sh: --next needs a count" >&2; exit 2; } ;;
    --block) BLOCK="${2:-}"; shift 2 || { echo "max-id-in-refs.sh: --block needs a size" >&2; exit 2; } ;;
    --)      shift; break ;;
    -h|--help) sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "max-id-in-refs.sh: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[ -n "$RE" ] || { echo "max-id-in-refs.sh: --regex is required" >&2; exit 2; }
case "$BLOCK" in ''|*[!0-9]*|0) echo "max-id-in-refs.sh: --block wants a positive integer, got '$BLOCK'" >&2; exit 2 ;; esac
SLOT_K=1; SLOT_N=1
if [ -n "$NEXT" ]; then
  case "$NEXT" in ''|*[!0-9]*|0) echo "max-id-in-refs.sh: --next wants a positive integer, got '$NEXT'" >&2; exit 2 ;; esac
  if [ -n "${SPEC_LANE_SLOT:-}" ]; then
    # Fail fast: a slot that silently fell back to max + 1 is the collision with no sign of it.
    case "$SPEC_LANE_SLOT" in
      [1-9]*/[1-9]*) SLOT_K=${SPEC_LANE_SLOT%%/*}; SLOT_N=${SPEC_LANE_SLOT#*/} ;;
      *) SLOT_K=x ;;
    esac
    case "$SLOT_K$SLOT_N" in *[!0-9]*)
      echo "max-id-in-refs.sh: SPEC_LANE_SLOT='$SPEC_LANE_SLOT' is not <k>/<n> (for example 1/2)" >&2; exit 2 ;; esac
    [ "$SLOT_K" -le "$SLOT_N" ] || {
      echo "max-id-in-refs.sh: SPEC_LANE_SLOT='$SPEC_LANE_SLOT' names lane $SLOT_K of $SLOT_N" >&2; exit 2; }
    [ "$NEXT" -le "$BLOCK" ] || {
      echo "max-id-in-refs.sh: a run of $NEXT does not fit a lane block of $BLOCK ids (raise --block)" >&2; exit 2; }
  fi
fi
[ $# -gt 0 ] || { echo "max-id-in-refs.sh: name at least one pathspec after --" >&2; exit 2; }

hits() {
  if ROOT=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null); then
    # Working tree first: an id minted a minute ago and not yet committed is the likeliest to be
    # handed out twice. --untracked, because a new ledger or map file is untracked until its commit.
    git -C "$ROOT" grep --untracked -ohE "$RE" -- "$@" 2>/dev/null
    local refs n=0 age=""
    refs=$(git -C "$ROOT" for-each-ref --format='%(refname)' refs/heads refs/remotes | grep -v '/HEAD$')
    if [ -n "$refs" ]; then
      n=$(printf '%s\n' "$refs" | grep -c .)
      # One call over every tree: git grep takes many revisions and -h drops the rev:path prefix.
      # shellcheck disable=SC2086
      git -C "$ROOT" grep -ohE "$RE" $refs -- "$@" 2>/dev/null
    fi
    local fh; fh="$(git -C "$ROOT" rev-parse --git-common-dir 2>/dev/null)/FETCH_HEAD"
    case "$fh" in /*) ;; *) fh="$ROOT/$fh" ;; esac
    [ -f "$fh" ] && age=" · last fetch $(( ( $(date +%s) - $(stat -c %Y "$fh" 2>/dev/null || stat -f %m "$fh") ) / 60 )) min ago"
    echo "max-id-in-refs: working tree + $n ref(s)${age:- · never fetched}" >&2
  else
    # Not a repository (a test fixture, a fresh scaffold): the files are all there is.
    ( cd "$DIR" && for p in "$@"; do for f in $p; do [ -f "$f" ] && grep -ohE "$RE" "$f"; done; done ) 2>/dev/null
    echo "max-id-in-refs: working tree only (not a git repository)" >&2
  fi
}

MAX=$(hits "$@" | sed -E 's/.*[^0-9]//' | grep -E '^[0-9]+$' |
  awk '{ n = $0 + 0; if (!seen || n > best) { best = n; raw = $0; seen = 1 } } END { if (seen) print raw }')
if [ -z "$NEXT" ]; then
  [ -n "$MAX" ] && printf '%s\n' "$MAX"
  exit 0
fi
# The first id past the max whose whole run sits inside one of this lane's blocks.
awk -v max="${MAX:-0}" -v c="$NEXT" -v b="$BLOCK" -v k="$((SLOT_K - 1))" -v n="$SLOT_N" 'BEGIN {
  s = max + 1
  if (n == 1) { print s; exit }
  blk = int((s - 1) / b)
  if (blk % n != k) { blk += (k - blk % n + n) % n; s = blk * b + 1 }
  if (s + c - 1 > (blk + 1) * b) { blk += n; s = blk * b + 1 }
  print s
}'
exit 0

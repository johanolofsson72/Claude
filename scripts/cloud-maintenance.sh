#!/bin/bash
# cloud-maintenance.sh — the cloud half of the maintenance pass, and the way its results come home (row 075).
#
# WHY THIS EXISTS. scripts/workload-placement.tsv puts the heavy jobs that need nothing local in
# Claude cloud. Running them there is the easy half. The hard half is that a cloud VM's
# .claude/state/ dies with the session, so on the Mac the job would stay "due" forever and the
# developer would run Stryker locally again -- the thing the placement exists to stop. A routine may
# push only to claude/* branches (code.claude.com/docs/en/routines, 2026-10-01), so the results
# travel on one: claude/maintenance-results. The default branch is never written.
#
# Usage:
#   bash scripts/cloud-maintenance.sh            # in a cloud session: setup, run the cloud-placed jobs, publish
#   bash scripts/cloud-maintenance.sh --pull     # on the developer's machine: import unseen results
#   bash scripts/cloud-maintenance.sh --force-local   # run the cloud half outside the cloud (tests)
#
# What travels: one file per run, .claude/cloud-results/<UTC timestamp>-<rand>.tsv, holding only the
# run's ledger lines (`ledger<TAB>` + the 9 ledger fields) and the stamps it wrote (`stamp<TAB>job
# <TAB>date<TAB>done<TAB>rows`). No job output: a log can carry a secret, a number cannot. The pull
# parses field by field against fixed job names and numeric fields; nothing in a results file is
# executed or sourced. Imported file names are kept in .claude/state/cloud-imported, so a second
# pull is a no-op. A stamp never moves backwards (maintenance-due.sh --stamp-as).
#
# Exit: 0 ok · 1 the pass reported findings (still published) · 2 could not run · 3 publish failed.
# CLOUD_RESULTS_REMOTE overrides the remote name (default origin). bash 3.2-safe.

set -u

BRANCH="claude/maintenance-results"
RESULTS_DIR=".claude/cloud-results"
REMOTE="${CLOUD_RESULTS_REMOTE:-origin}"
LEDGER_JOBS=" secrets traceability similarity mutation suite portability pass setup "
STAMP_JOBS=" secrets similarity mutation suite "

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "cloud-maintenance: not inside a git repository" >&2; exit 2; }
cd "$ROOT" || exit 2
LEDGER=".claude/state/maintenance-runs.tsv"
STATE=".claude/.maintenance-state"
IMPORTED=".claude/state/cloud-imported"

say() { echo "cloud-maintenance: $*" >&2; }
# Text from a results file is printed only after this: no escape sequences reach the terminal.
clean() { printf '%s' "$1" | LC_ALL=C tr -cd '[:alnum:]._:/+ -' | cut -c1-80; }
TAB=$(printf '\t')
NAME_RE='^[0-9]{8}T[0-9]{6}Z-[0-9a-f]+\.tsv$'
MAX_BYTES=65536
MAX_FILES=200

MODE=run
FORCE_LOCAL=0
for arg in "$@"; do
  case "$arg" in
    --pull) MODE=pull ;;
    --force-local) FORCE_LOCAL=1 ;;
    -h|--help) awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
    *) say "unknown argument '$arg' (try --help)"; exit 2 ;;
  esac
done

# ------------------------------------------------------------------------------------------ pull
if [ "$MODE" = pull ]; then
  if ! git fetch -q "$REMOTE" "+refs/heads/$BRANCH:refs/remotes/$REMOTE/$BRANCH" 2>/dev/null; then
    if git ls-remote --exit-code "$REMOTE" "refs/heads/$BRANCH" >/dev/null 2>&1; then
      say "could not fetch $BRANCH from $REMOTE"; exit 2
    fi
    echo "cloud-maintenance: no cloud results yet ($BRANCH does not exist on $REMOTE)."
    exit 0
  fi
  REF="refs/remotes/$REMOTE/$BRANCH"
  mkdir -p .claude/state
  touch "$IMPORTED"
  NEW=0; SKIPPED_LINES=0; LEFT=0
  # One entry per line from `ls-tree -l`: mode, type, size and path. Only plain files with the name a
  # run writes, under the size cap, are read; a symlink or a tree is not a results file (075
  # adversarial review, findings 2-4). A name is matched whole, so `-v` cannot reach grep as a flag.
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    meta=${entry%%"$TAB"*}; path=${entry#*"$TAB"}; name=${path##*/}
    set -- $meta
    if ! grep -qE "$NAME_RE" <<< "$name"; then
      say "skipped $(clean "$path") — unexpected file name"; continue
    fi
    grep -qxF -- "$name" "$IMPORTED" </dev/null && continue
    if [ "${1:-}" != 100644 ] || [ "${2:-}" != blob ]; then
      say "skipped $name — not a plain file"; continue
    fi
    if [ "${4:-0}" -gt "$MAX_BYTES" ] 2>/dev/null; then
      say "skipped $name — ${4} bytes, over the $MAX_BYTES-byte cap"; continue
    fi
    if [ "$NEW" -ge "$MAX_FILES" ]; then LEFT=$((LEFT + 1)); continue; fi
    # One awk pass validates the whole file. It prints L<TAB>ledger line, S<TAB>job<TAB>date<TAB>done
    # <TAB>rows, or X<TAB>line<TAB>reason. Nothing from the file is ever executed.
    PARSED=$(git show "$REF:$path" 2>/dev/null | tr -d '\r' | awk -F'\t' '
      function d4(x) { return x ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ }
      $1 == "" && NF <= 1 { next }
      $1 == "ledger" {
        if (NF == 10 && length($0) <= 300 &&
            $2 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]([+-][0-9][0-9]:[0-9][0-9]|Z)$/ &&
            $3 == "cloud" &&
            $4 ~ /^(secrets|traceability|similarity|mutation|suite|portability|pass|setup)$/ &&
            $5 ~ /^[0-9]+(\.[0-9]+)?$/ && $6 ~ /^-?[0-9]+$/ && $7 ~ /^[0-9]*$/ && $8 ~ /^[0-9]*$/ &&
            $9 ~ /^([0-9]+(\.[0-9]+)?)?$/ && $10 ~ /^[0-9]+$/) {
          sub(/^ledger\t/, ""); print "L\t" $0
        } else print "X\t" NR "\tnot a cloud ledger line"
        next
      }
      $1 == "stamp" {
        if (NF == 5 && $2 ~ /^(secrets|similarity|mutation|suite)$/ && d4($3) && $4 ~ /^[0-9]+$/ && $5 ~ /^[0-9]+$/ &&
            length($4) <= 6 && length($5) <= 6)
          print "S\t" $2 "\t" $3 "\t" $4 "\t" $5
        else print "X\t" NR "\tnot a stamp a cloud run writes"
        next
      }
      { print "X\t" NR "\tunknown kind" }') || { say "could not read $name"; continue; }
    while IFS="$TAB" read -r kind a b c d; do
      case "$kind" in
        L) printf '%s\t%s\t%s\t%s\n' "$a" "$b" "$c" "$d" >> "$LEDGER" ;;
        S) if bash scripts/maintenance-due.sh --stamp-as "$a" "$b" "$c" "$d"; then
             echo "cloud-maintenance: stamped $a from $name ($b, $c spec(s) done)"
           else
             say "skipped $name stamp $a — rejected"; SKIPPED_LINES=$((SKIPPED_LINES + 1))
           fi ;;
        X) say "skipped $name line $a — $b"; SKIPPED_LINES=$((SKIPPED_LINES + 1)) ;;
      esac
    done <<EOF_PARSED
$PARSED
EOF_PARSED
    echo "$name" >> "$IMPORTED"
    NEW=$((NEW + 1))
  done <<EOF_LIST
$(git ls-tree -l "$REF" "$RESULTS_DIR/" 2>/dev/null)
EOF_LIST
  echo "cloud-maintenance: imported $NEW result file(s)$([ "$SKIPPED_LINES" -gt 0 ] && printf ', %s line(s) skipped' "$SKIPPED_LINES")$([ "$LEFT" -gt 0 ] && printf '; %s more next pull (cap %s per pull)' "$LEFT" "$MAX_FILES")."
  exit 0
fi

# ------------------------------------------------------------------------------------------- run
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ] && [ "$FORCE_LOCAL" -ne 1 ]; then
  say "not a Claude cloud session (CLAUDE_CODE_REMOTE is not true). On this machine run:"
  say "  bash scripts/project-maintenance.sh --full --placed    and    bash scripts/cloud-maintenance.sh --pull"
  exit 2
fi

if [ -f scripts/cloud-setup.sh ]; then
  SETUP_OUT=$(bash scripts/cloud-setup.sh) || { say "setup failed — the dotnet jobs cannot run; publishing the failure"; SETUP_FAILED=1; }
  # Only the one line cloud-setup.sh is documented to print is honoured.
  PATH_LINE=$(printf '%s\n' "${SETUP_OUT:-}" | grep -E '^export PATH="[^"$`;|&]*:\$PATH"$' | tail -1)
  [ -n "$PATH_LINE" ] && eval "$PATH_LINE"
fi
SETUP_FAILED=${SETUP_FAILED:-0}
[ "${CLAUDE_CODE_REMOTE:-}" != "true" ] && say "--force-local: publishing to the real $REMOTE remote's $BRANCH."

mkdir -p .claude/state
LEDGER_BEFORE=0; [ -f "$LEDGER" ] && LEDGER_BEFORE=$(wc -l < "$LEDGER" | tr -d ' ')
STATE_BEFORE=""; [ -f "$STATE" ] && STATE_BEFORE=$(cat "$STATE")

PASS_RC=0
if [ "$SETUP_FAILED" -eq 1 ]; then
  PASS_RC=2
else
  CLAUDE_CODE_REMOTE=true bash scripts/project-maintenance.sh --full --suite --placed; PASS_RC=$?
fi

STAMP_UTC=$(date -u +%Y%m%dT%H%M%SZ)
RAND=$(od -An -N3 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
NAME="$STAMP_UTC-${RAND:-$$}.tsv"
OUT=$(mktemp "${TMPDIR:-/tmp}/cloud-results.XXXXXX") || exit 2
[ -f "$LEDGER" ] && tail -n +"$((LEDGER_BEFORE + 1))" "$LEDGER" | sed 's/^/ledger	/' >> "$OUT"
if [ "$SETUP_FAILED" -eq 1 ]; then
  printf 'ledger\t%s\tcloud\tsetup\t0.0\t1\t\t\t\t0\n' "$(date -u +%Y-%m-%dT%H:%M:%S+00:00)" >> "$OUT"
fi
if [ -f "$STATE" ]; then
  # Only stamps this run wrote: lines that were not in the state file before it started.
  while IFS= read -r sl; do
    grep -qxF -- "$sl" <<< "$STATE_BEFORE" || printf 'stamp\t%s\n' "$sl" >> "$OUT"
  done < "$STATE"
fi

# Publish with plumbing: the branch is never checked out, so nothing on it -- a symlink, a
# .gitattributes filter -- touches this machine, and the session's own checkout is never switched
# (075 adversarial review, finding 3). A private index holds the branch's tree plus one new blob.
IDX=$(mktemp "${TMPDIR:-/tmp}/cloud-results-idx.XXXXXX") || { rm -f "$OUT"; exit 2; }
trap 'rm -f "$OUT" "$IDX"' EXIT

publish() {
  local parent="" blob tree commit
  if git fetch -q "$REMOTE" "+refs/heads/$BRANCH:refs/remotes/$REMOTE/$BRANCH" 2>/dev/null; then
    parent=$(git rev-parse -q --verify "refs/remotes/$REMOTE/$BRANCH^{commit}") || return 1
    GIT_INDEX_FILE="$IDX" git read-tree "$parent" || return 1
  else
    rm -f "$IDX"; GIT_INDEX_FILE="$IDX" git read-tree --empty || return 1
  fi
  blob=$(git hash-object -w "$OUT") || return 1
  GIT_INDEX_FILE="$IDX" git update-index --add --cacheinfo "100644,$blob,$RESULTS_DIR/$NAME" || return 1
  tree=$(GIT_INDEX_FILE="$IDX" git write-tree) || return 1
  commit=$(git -c user.name="${GIT_AUTHOR_NAME:-claude-cloud-maintenance}" -c user.email="${GIT_AUTHOR_EMAIL:-noreply@anthropic.com}" \
    commit-tree "$tree" ${parent:+-p "$parent"} -m "chore: cloud maintenance results $STAMP_UTC") || return 1
  git push -q "$REMOTE" "$commit:refs/heads/$BRANCH" 2>/dev/null
}

# Another run may push first: start again from the branch as it is now. Once, then report.
if ! publish && ! publish; then
  say "could not publish $NAME to $REMOTE/$BRANCH — the results stay unpublished"
  exit 3
fi
echo "cloud-maintenance: published $RESULTS_DIR/$NAME to $REMOTE/$BRANCH (pass exit $PASS_RC)."
[ "$PASS_RC" -eq 0 ] && exit 0
[ "$PASS_RC" -eq 1 ] && exit 1
exit 2

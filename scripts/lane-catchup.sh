#!/bin/bash
# lane-catchup.sh — bring a second lane's machine level with the register.
#
# WHY THIS EXISTS. A two-lane project shares a git repo and nothing else. When
# one lane changes the config, the rules, or the shared machinery, the other
# lane finds out by pulling -- and on a lane that sets CLAUDE_TEMPLATE_AUTOSYNC=0
# (which .claude/rules/spec-register.md tells the second machine to do, so the
# two do not race each other's config commits) nothing arrives on its own.
#
# The alternative was a written list of steps sent to a person. That fails three
# ways and did, on the first draft: the step that stops permission prompts sat
# fourth, so the developer clicked through prompts to reach it; the paths were
# guesses about someone else's disk; and it ended with "report back", which makes
# a person the transport between two machines that already share a disk -- the
# exact anti-pattern .claude/rules/lane-handoff.md exists to remove.
#
# So: one command, ordered so each step clears the way for the next, and its
# findings are WRITTEN to specs/INDEX.pending.md rather than relayed by hand.
#
# Reports by default and changes nothing. --apply makes the two machine-local
# changes (permission denies, nightly cron); everything else is read-only.
#
# Usage:
#   bash scripts/lane-catchup.sh              # report only
#   bash scripts/lane-catchup.sh --apply      # also make the machine-local fixes
#   bash scripts/lane-catchup.sh --apply --at 03:00
#
# Exit: 0 nothing needs a human · 1 something does · 2 could not run

set -uo pipefail
export LC_ALL=C

APPLY=0; AT="02:30"
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --at) AT="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "lane-catchup.sh: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "lane-catchup: run this from inside the project repo." >&2; exit 2; }
cd "$ROOT" || exit 2

NEEDS_HUMAN=0
say()  { printf '%s\n' "$*"; }
head_() { printf '\n\033[1m%s\033[0m\n' "$*" 2>/dev/null || printf '\n%s\n' "$*"; }
todo() { NEEDS_HUMAN=1; printf '  → %s\n' "$*"; }

# ── 1. Permissions FIRST. Every step below runs shell commands, and if this is
#      unfixed the developer approves each one by hand on the way to the fix.
head_ "1. Permission prompts"
GS="$HOME/.claude/settings.json"
if [ ! -f "$GS" ]; then
  say "  no global settings at $GS — nothing to change"
else
  DENIES=$(python3 - "$GS" <<'PY' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
bad = [r for r in d.get("permissions", {}).get("deny", [])
       if r.startswith(("Read(~/", "Edit(~/"))]
print("\n".join(bad))
PY
)
  if [ -z "$DENIES" ]; then
    say "  no Read(~/…) deny rules — prompts are not coming from here"
  elif [ "$APPLY" -eq 1 ]; then
    python3 - "$GS" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
perm = d.setdefault("permissions", {})
before = perm.get("deny", [])
perm["deny"] = [r for r in before if not r.startswith(("Read(~/", "Edit(~/"))]
open(p, "w").write(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
print(f"  removed {len(before) - len(perm['deny'])} Read/Edit home-dir deny rule(s); "
      f"{len(perm['deny'])} deny rule(s) kept")
PY
    say "  every Bash deny is kept — rm -rf, sudo, force-push, hard reset"
  else
    say "  these deny rules are why ordinary commands prompt:"
    printf '    %s\n' $DENIES
    todo "run with --apply to remove them (Bash denies are kept)"
  fi
fi

# ── 2. Is the working tree even able to take an update?
head_ "2. Repository state"
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
DIRTY=$(git status --porcelain | wc -l | tr -d ' ')
say "  branch $BRANCH · $DIRTY uncommitted file(s)"
git fetch -q origin 2>/dev/null || true
BEHIND=$(git rev-list --count "HEAD..origin/$BRANCH" 2>/dev/null || echo 0)
AHEAD=$(git rev-list --count "origin/$BRANCH..HEAD" 2>/dev/null || echo 0)
if [ "${BEHIND:-0}" -gt 0 ]; then
  say "  $BEHIND commit(s) behind origin/$BRANCH"
  todo "git pull  — this is where the rules, scripts and settings arrive"
else
  say "  up to date with origin/$BRANCH"
fi
[ "${AHEAD:-0}" -gt 0 ] && todo "$AHEAD commit(s) not pushed — the other lane cannot see them"

# ── 3. Did the shared machinery actually land?
head_ "3. Shared machinery"
MISS=""
for f in .claude/rules/carve-budget.md scripts/register-convergence.sh \
         scripts/install-nightly-maintenance.sh scripts/archive-completed-rows.sh; do
  [ -f "$f" ] || MISS="$MISS $f"
done
if [ -n "$MISS" ]; then
  say "  missing:$MISS"
  todo "pull first, then re-run this"
else
  say "  carve-budget rule, convergence, nightly installer, archiver — all present"
  # -f, not -x. Eight CORE scripts in the template were shipped without their
  # executable bit and the sync copies modes faithfully, so an -x guard here
  # skipped this entire check in silence on all six projects. The SessionStart
  # hook already learned this and tests `-x || -f`; this is the same lesson.
  if [ -f scripts/template-autosync.sh ]; then
    OUT=$(timeout 240 bash scripts/template-autosync.sh --force --dry-run 2>&1)
    printf '%s\n' "$OUT" | grep -E '^\[check\] would' | sed 's/^/  /'
    SKIPS=$(printf '%s\n' "$OUT" | grep '^  SKIP' | sed 's/^  SKIP   //; s/ (differs.*//')
    if [ -n "$SKIPS" ]; then
      say "  locally-edited docs the sync will not touch:"
      printf '    %s\n' $SKIPS
      todo "these need /project-update (a prose merge) or --accept-local"
    fi
  fi
fi

# ── 4. The nightly pass. Per machine: a crontab entry is not in git.
head_ "4. Nightly maintenance"
if [ ! -f scripts/install-nightly-maintenance.sh ]; then
  say "  installer not present yet (pull first)"
elif bash scripts/install-nightly-maintenance.sh --list 2>/dev/null | grep -q "$ROOT"; then
  say "  already scheduled on this machine"
elif [ "$APPLY" -eq 1 ]; then
  bash scripts/install-nightly-maintenance.sh --at "$AT" 2>&1 | sed 's/^/  /'
else
  say "  not scheduled — the mutation gate has never run on this machine"
  todo "run with --apply to schedule it at $AT"
fi

# ── 5. Where the register stands, and what this lane owns.
head_ "5. This lane"
OWNER="${SPEC_OWNER:-}"
if [ -z "$OWNER" ]; then
  say "  SPEC_OWNER is unset — set it in .claude/settings.local.json so the"
  say "  guards resolve YOUR row and not the other lane's:"
  say '    { "env": { "SPEC_OWNER": "yourname", "CLAUDE_TEMPLATE_AUTOSYNC": "0" } }'
  todo "set SPEC_OWNER"
else
  say "  SPEC_OWNER=$OWNER"
  MINE=$(grep -E "^- \[[ /!]\].*@${OWNER}[[:space:]]*$" specs/INDEX.md 2>/dev/null | wc -l | tr -d ' ')
  say "  $MINE open row(s) owned by you:"
  grep -E "^- \[[ /!]\].*@${OWNER}[[:space:]]*$" specs/INDEX.md 2>/dev/null \
    | sed -E 's/^- \[([ \/!])\] +([^ —]+) — ([^—]+) —.*/    [\1] \2 — \3/' | head -10
fi
if [ -f scripts/register-convergence.sh ]; then
  # Capture the exit code from the SCRIPT, not from the `head` that trims it.
  # Piping first makes $? the trimmer's, which is always 0, so the convergence
  # stop never fires however badly the register diverges. Same defect as the one
  # fixed in spec-register-orientation-hook.sh the same day.
  CONV_RAW=$(bash scripts/register-convergence.sh 2>&1); RC=$?
  CONV=$(printf '%s\n' "$CONV_RAW" | head -1)
  say "  $CONV"
  [ "$RC" = 2 ] && todo "convergence stop — see .claude/rules/carve-budget.md before carving any row"
fi
HELD=$(grep -cE '^- \[!\]' specs/INDEX.md 2>/dev/null || echo 0)
[ "${HELD:-0}" -gt 0 ] && say "  $HELD held row(s) — read the Register history for why before starting one"

head_ "Summary"
if [ "$NEEDS_HUMAN" -eq 0 ]; then
  say "  Nothing needs a human. This lane is level."
else
  say "  The arrows above are what is left. Findings that concern the OTHER lane"
  say "  belong in specs/INDEX.pending.md or a new register row, committed and"
  say "  pushed — not in a chat message (.claude/rules/lane-handoff.md)."
fi
exit "$NEEDS_HUMAN"

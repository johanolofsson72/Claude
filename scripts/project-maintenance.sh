#!/bin/bash
# project-maintenance.sh — the recurring local maintenance pass.
#
# WHY THIS EXISTS. Three documents (.claude/docs/testing.md, spec-testing-checklist.md,
# .claude/rules/tests.md) describe the mutation gate as running "nightly/on-demand",
# and .claude/rules/github-actions.md correctly bans `schedule:` triggers after the
# iskvalp incident (3000 Actions minutes in four days). Net result: "nightly" ran
# never. Same for scripts/project-freshness.sh — a secret + CVE scan nobody schedules
# is a secret + CVE scan that does not happen. This script is the local, zero-minute
# answer: one command a recurring loop can call.
#
# ATTENTION MODE. A recurring job that reports at length when nothing changed teaches
# you to ignore it, and then you ignore the one run that mattered. Clean run → one
# line. Findings → the full report, loudest first. Exit code carries the verdict, so
# a scheduler can branch on it.
#
# Usage:
#   bash scripts/project-maintenance.sh            # report-only sweep (fast)
#   bash scripts/project-maintenance.sh --full     # also run the mutation pass (slow)
#   bash scripts/project-maintenance.sh --quiet    # findings only, no clean-run line
#
# MAINTENANCE_WORKTREE_GRACE_HOURS=N  how long an agent worktree may sit untouched
#   before it is reported as abandoned (default 24). Agent worktrees are not locked,
#   so recency of writes is the only signal that one is still in use; the window keeps
#   a healthy in-progress agent run from producing a finding.
#
# Wire it to a recurring run WITHOUT touching CI minutes:
#   /schedule  — a cloud routine, e.g. weekly Monday 08:00:
#                "run bash scripts/project-maintenance.sh and report only if it exits non-zero"
#   /loop 7d   — a session-bound repeat while you are working
#   crontab    — 0 8 * * 1 cd /path/to/repo && bash scripts/project-maintenance.sh
# NEVER as a GitHub Action `schedule:` trigger — that is the banned pattern.
#
# Exit codes: 0 = clean · 1 = findings reported · 2 = a requested step could not run.
#
# bash 3.2-safe (macOS system bash), cross-platform (macOS / Linux / Windows Git Bash).

set -uo pipefail

FULL=0
QUIET=0
for arg in "$@"; do
  case "$arg" in
    --full)  FULL=1 ;;
    --quiet) QUIET=1 ;;
    # Print the whole leading comment block, not a hardcoded line range: this header
    # has grown twice now, and a range silently truncates --help when it does.
    -h|--help) awk 'NR>1 && /^#/ {print; next} NR>1 {exit}' "$0"; exit 0 ;;
    *) echo "unknown flag: $arg (try --help)" >&2; exit 2 ;;
  esac
done

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
cd "$ROOT" || exit 2

FINDINGS=0
REPORT=""
add() { REPORT="${REPORT}$1
"; FINDINGS=$((FINDINGS + 1)); }

# ---------------------------------------------------------------- 1. secrets + CVEs
if [ -f scripts/project-freshness.sh ]; then
  FRESH_OUT=$(bash scripts/project-freshness.sh 2>&1)
  FRESH_RC=$?
  if [ "$FRESH_RC" -ne 0 ]; then
    add "[SECRETS/DEPS] scripts/project-freshness.sh reported findings:
$(printf '%s' "$FRESH_OUT" | tail -25)"
  fi
else
  add "[SETUP] scripts/project-freshness.sh missing — run /project-update to restore it."
fi

# ------------------------------------------------------- 2. per-spec-read file bloat
# Same 25 KB threshold as the SessionStart canary in spec-register-orientation-hook.sh.
for f in specs/INDEX.md specs/SCENARIOS.md; do
  [ -f "$f" ] || continue
  BYTES=$(wc -c < "$f" 2>/dev/null | tr -d ' ')
  case "$BYTES" in (''|*[!0-9]*) BYTES=0 ;; esac
  if [ "$BYTES" -gt 25600 ]; then
    add "[CONTEXT-COST] $f is $((BYTES / 1024)) KB — read on every spec. Trim: scripts/archive-spec-history.sh --keep 5"
  fi
done

# --------------------------------------------------------- 3. blocked / stalled rows
if [ -f specs/INDEX.md ]; then
  BLOCKED=$(grep -cE '^- \[!\]' specs/INDEX.md 2>/dev/null | tr -dc '0-9'); BLOCKED=${BLOCKED:-0}
  INPROG=$(grep -cE '^- \[/\]' specs/INDEX.md 2>/dev/null | tr -dc '0-9'); INPROG=${INPROG:-0}
  DONE=$(grep -cE '^- \[x\]' specs/INDEX.md 2>/dev/null | tr -dc '0-9'); DONE=${DONE:-0}
  [ "${BLOCKED:-0}" -gt 0 ] && add "[REGISTER] $BLOCKED row(s) marked blocked \`- [!]\` — a register-rewrite decision is pending."
  [ "${INPROG:-0}" -gt 1 ] && add "[REGISTER] $INPROG rows marked in-progress \`- [/]\` — only one spec runs at a time."
  # Integration-hardening checkpoint cadence (.claude/rules/spec-hardening.md).
  if [ "${DONE:-0}" -gt 0 ] && [ $((DONE % 5)) -eq 0 ]; then
    if ! grep -qiE '^- \[[ /]\].*checkpoint' specs/INDEX.md 2>/dev/null; then
      add "[HARDENING] $DONE specs done (multiple of 5) but no pending checkpoint row — insert an integration-hardening checkpoint before the next feature spec."
    fi
  fi
fi

# ------------------------------------------------------- 3b. spec-kit installation
# The blind spot this section closes. Nothing in the template ever noticed that a
# project's spec-kit was missing or years behind, because template-autosync.sh does
# not install spec-kit -- only /project-update does -- and no check compared the two.
# The result, measured across 42 projects: eight with no .specify at all (seven of
# them with zero speckit skills, so /speckit-specify could not run and the pipeline
# was decorative), one on 0.8.14, one on 0.9.1 -- versions predating the hyphenated
# skill names every rule in .claude/rules/ refers to. All of them looked healthy: the
# template sync reported "already at template" because the template half WAS current.
#
# Report-only. Installing spec-kit needs a real /project-update (it re-inits, merges
# CLAUDE.md and re-decides the tech stack), which is a judgment pass, not a sweep.
if [ -f specs/INDEX.md ] || [ -d .specify ]; then
  SK_SKILLS=$(find .claude/skills -maxdepth 1 -type d -name 'speckit*' 2>/dev/null | wc -l | tr -d ' ')
  case "$SK_SKILLS" in (''|*[!0-9]*) SK_SKILLS=0 ;; esac
  SK_VER=""
  if [ -f .specify/init-options.json ] && command -v python3 >/dev/null 2>&1; then
    SK_VER=$(python3 -c 'import json,sys
try: print(json.load(open(".specify/init-options.json")).get("speckit_version",""))
except Exception: print("")' 2>/dev/null)
  fi

  if [ ! -d .specify ]; then
    add "[SPECKIT] no .specify/ — spec-kit is not installed, so the pipeline's phases (/speckit-specify … /speckit-implement) cannot run. ${SK_SKILLS} speckit skill(s) on disk. Run /project-update."
  elif [ "$SK_SKILLS" -eq 0 ]; then
    add "[SPECKIT] .specify/ exists but no speckit skills are installed — the phases cannot be invoked. Run /project-update."
  elif [ -z "$SK_VER" ]; then
    add "[SPECKIT] .specify/init-options.json records no speckit_version — the install predates version stamping. Run /project-update to land a current spec-kit."
  else
    case "$SK_VER" in
      1.*) ;;                                   # current line
      0.16.*) ;;                                # previous line, still supported
      *) add "[SPECKIT] spec-kit $SK_VER is well behind the 1.x line — versions before 0.10 use unhyphenated phase names (/specify, not /speckit-specify), which every rule in .claude/rules/ assumes. Run /project-update." ;;
    esac
  fi
fi

# ------------------------------------------------------------ 4. stale attempt state
if [ -d .claude/state/attempts ]; then
  STALE=$(find .claude/state/attempts -type f -mtime +1 2>/dev/null | wc -l | tr -d ' ')
  case "$STALE" in (''|*[!0-9]*) STALE=0 ;; esac
  [ "$STALE" -gt 0 ] && find .claude/state/attempts -type f -mtime +1 -delete 2>/dev/null
fi

# ------------------------------------------------- 4b. abandoned agent worktrees
# WHY. scripts/prune-agent-worktrees.sh was written because agent worktrees
# (.claude/worktrees/agent-*, created by `isolation: worktree`) accumulate disk AND
# strand agent memory -- a subagent writes to ITS worktree's .claude/agent-memory/ and
# nothing merges it back. Nothing ever ran it, which is the same defect this whole
# script exists to end: see the header, "nightly ran never".
#
# Measured across ~/repos on 2026-08-26: 7 abandoned worktrees in 4 projects, 733 MB,
# the oldest 149 days, holding 6 memory files that existed nowhere else -- one of them
# a security-scanner adversarial review in a checkout twelve days dead.
#
# REPORT-ONLY, deliberately. Not one agent worktree in that fleet was locked, so
# nothing here can tell a live agent from a dead one with certainty, and an unattended
# job that deletes checkouts on that guess is a bad trade for 733 MB. Section 4 above
# is not a precedent: an attempt-state file is a byte-sized counter with nothing
# salvageable inside, and a worktree is the opposite on both counts.
#
# The grace window is the honest substitute for a lock. A worktree written to recently
# is presumed live and stays out of the report entirely, so a healthy agent run in
# progress never produces a finding -- which is what keeps this section from becoming
# the noise the header's attention-mode rule warns about.
if [ -d .claude/worktrees ]; then
  GRACE_H=${MAINTENANCE_WORKTREE_GRACE_HOURS:-24}
  case "$GRACE_H" in (''|*[!0-9]*) GRACE_H=24 ;; esac

  WT_N=0; WT_KB=0; WT_OLDEST=0; WT_MEM=0
  WT_NOW=$(date +%s 2>/dev/null); case "$WT_NOW" in (''|*[!0-9]*) WT_NOW=0 ;; esac

  # Does this host's find understand a RELATIVE -newermt at all? It matters more than it
  # looks: a find that cannot parse the expression prints to stderr and matches nothing,
  # which is indistinguishable from "no recent writes" -- so every worktree on the machine
  # would be declared abandoned at once. That is the noisiest possible failure for a
  # recurring job, and it would arrive looking like a real finding.
  #
  # The control is a hundred-year window, which must match the directory that is certainly
  # there. Empty means the option did not evaluate, not that the directory is old.
  if [ -z "$(find .claude/worktrees -maxdepth 0 -newermt "-876000 hours" -print 2>/dev/null)" ]; then
    add "[SETUP] this host's \`find\` cannot evaluate a relative \`-newermt\`, so a live agent worktree cannot be told from an abandoned one — worktree reporting skipped rather than guessed. Sweep by hand: bash scripts/prune-agent-worktrees.sh --dry-run"
  else

    for wt in .claude/worktrees/agent-*; do
      [ -d "$wt" ] || continue

      # Live #1 -- something was written in here inside the window. The heavy directories
      # are pruned so this stays milliseconds (18 ms on a 190 MB worktree, worst case: a
      # full walk that finds nothing), and -quit stops the positive case at the first hit.
      if [ -n "$(find "$wt" \( -name node_modules -o -name .git -o -name bin -o -name obj \
                               -o -name dist -o -name .stryker-tmp \) -prune \
                 -o -newermt "-${GRACE_H} hours" -print -quit 2>/dev/null)" ]; then
        continue
      fi

      # Live #2 -- a lock naming a process that still exists. In practice the harness does
      # not lock what it creates, so this rarely fires; it stays because
      # prune-agent-worktrees.sh honours it, and disagreeing about liveness with the very
      # tool this finding tells you to run would be worse than the cost of asking.
      WT_LOCK=$(git worktree list --porcelain 2>/dev/null | awk -v w="$PWD/$wt" '
        $1=="worktree"{cur=$2} $1=="locked"{if(cur==w){$1="";print;exit}}')
      if [ -n "$WT_LOCK" ]; then
        WT_PID=$(printf '%s' "$WT_LOCK" | sed -n 's/.*pid \([0-9][0-9]*\).*/\1/p')
        if [ -n "$WT_PID" ] && kill -0 "$WT_PID" 2>/dev/null; then continue; fi
      fi

      WT_N=$((WT_N + 1))

      # Everything below degrades rather than aborts. The secrets and CVE sections above
      # matter more than this one and must not be taken down by a `du` that failed.
      WT_SZ=$(du -sk "$wt" 2>/dev/null | cut -f1)
      case "$WT_SZ" in (''|*[!0-9]*) WT_SZ=0 ;; esac
      WT_KB=$((WT_KB + WT_SZ))

      # BSD form first (macOS), GNU second (Linux, Git Bash). If both fail the age is
      # omitted from the finding rather than printed as garbage.
      WT_MT=$(stat -f %m "$wt" 2>/dev/null || stat -c %Y "$wt" 2>/dev/null)
      case "$WT_MT" in (''|*[!0-9]*) WT_MT=0 ;; esac
      if [ "$WT_MT" -gt 0 ] && [ "$WT_NOW" -gt "$WT_MT" ]; then
        WT_AGE=$(( (WT_NOW - WT_MT) / 86400 ))
        [ "$WT_AGE" -gt "$WT_OLDEST" ] && WT_OLDEST=$WT_AGE
      fi

      # Memory that exists ONLY in here. MEMORY.md index fragments are excluded because
      # the sweep merges those rather than salvaging them, so counting them would
      # overstate what is actually at risk.
      while read -r wt_f; do
        [ -n "$wt_f" ] || continue
        wt_rel=${wt_f#*/.claude/agent-memory/}
        case "$wt_rel" in MEMORY.md|*/MEMORY.md) continue ;; esac
        [ -f ".claude/agent-memory/$wt_rel" ] || WT_MEM=$((WT_MEM + 1))
      done < <(find "$wt/.claude/agent-memory" -type f 2>/dev/null)
    done

    if [ "$WT_N" -gt 0 ]; then
      if [ ! -f scripts/prune-agent-worktrees.sh ]; then
        add "[SETUP] $WT_N abandoned agent worktree(s) under .claude/worktrees/ but scripts/prune-agent-worktrees.sh is missing — run /project-update to restore it."
      else
        WT_AGE_TXT=""
        [ "$WT_OLDEST" -gt 0 ] && WT_AGE_TXT=", oldest $WT_OLDEST days"
        add "[WORKTREES] $WT_N abandoned agent worktree(s) under .claude/worktrees/ — $((WT_KB / 1024)) MB${WT_AGE_TXT}, untouched for over ${GRACE_H}h.
  $WT_MEM agent-memory file(s) exist only inside them; removing the worktrees takes that with them.
  Sweep (salvages memory first, removes only what is provably safe):
    bash scripts/prune-agent-worktrees.sh --dry-run"
      fi
    fi
  fi
fi

# ------------------------------------------------------------- 5. mutation kill rate
MUTATION_CMD=""
# `find`, not a glob: bash globstar is off by default, so `./**/*.csproj` would
# silently only match one level deep — and would miss src/Foo/Foo.csproj.
if [ -n "$(find . -maxdepth 3 \( -name '*.sln' -o -name '*.csproj' \) -not -path '*/node_modules/*' -print -quit 2>/dev/null)" ]; then
  MUTATION_CMD="dotnet stryker"
elif [ -f package.json ] && grep -q '"@stryker-mutator/core"' package.json 2>/dev/null; then
  MUTATION_CMD="npx stryker run"
fi

if [ -n "$MUTATION_CMD" ]; then
  if [ "$FULL" -eq 1 ]; then
    MUT_OUT=$(eval "$MUTATION_CMD" 2>&1)
    MUT_RC=$?
    SCORE=$(printf '%s' "$MUT_OUT" | grep -oE 'mutation score[^0-9]*[0-9]+(\.[0-9]+)?' | tail -1 | grep -oE '[0-9]+(\.[0-9]+)?' | tail -1)
    if [ "$MUT_RC" -ne 0 ]; then
      add "[MUTATION] \`$MUTATION_CMD\` failed to complete:
$(printf '%s' "$MUT_OUT" | tail -15)"
    elif [ -n "$SCORE" ]; then
      INT_SCORE=${SCORE%%.*}
      if [ "${INT_SCORE:-0}" -lt 80 ]; then
        add "[MUTATION] kill rate ${SCORE}% — below the ~80% target on critical modules. The suite is green but does not bite (.claude/docs/testing.md)."
      fi
    fi
  else
    REPORT="${REPORT}[skipped] mutation pass — re-run with --full to execute \`$MUTATION_CMD\` (slow).
"
  fi
fi

# ------------------------------------------------------------------------ verdict
if [ "$FINDINGS" -eq 0 ]; then
  [ "$QUIET" -eq 1 ] && exit 0
  echo "project-maintenance: clean — no secrets, no CVEs, no register drift, no context bloat.$([ "$FULL" -eq 0 ] && [ -n "$MUTATION_CMD" ] && printf ' (mutation pass skipped — use --full)')"
  exit 0
fi

echo "project-maintenance: $FINDINGS finding(s) — $(date -u +%Y-%m-%d)"
echo
printf '%s' "$REPORT"
echo "Each finding needs an explicit fix / defer / dismiss decision per .claude/rules/validation-followup.md."
exit 1

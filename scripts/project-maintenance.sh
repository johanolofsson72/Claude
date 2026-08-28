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

# A second buffer, for sections that must REPORT without FAILING. `add` is both the finding
# counter and the only route to output, so a section using it can only speak by making the run
# red -- and a run that is red forever is a run nobody reads. `note` speaks without voting, and
# the verdict prints NOTES in BOTH branches (clean and findings), or a note would only ever
# surface when something else had already gone wrong.
NOTES=""
note() { NOTES="${NOTES}$1
"; }

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
#
# Spec 007bl added the second shape a scenario map can take: an index plus per-feature files
# under specs/scenarios/. Every one of those is read when its feature is worked, so each is
# measured on its own. They are never summed — nothing reads all of them in one spec, so a sum
# would fire forever on a map that is behaving exactly as designed, and an un-actionable
# warning is the thing this section exists to remove rather than reproduce. The glob simply
# matches nothing on the 41 projects that never split, so their output is unchanged.
for f in specs/INDEX.md specs/SCENARIOS.md specs/scenarios/*.md; do
  [ -f "$f" ] || continue
  BYTES=$(wc -c < "$f" 2>/dev/null | tr -d ' ')
  case "$BYTES" in (''|*[!0-9]*) BYTES=0 ;; esac
  if [ "$BYTES" -gt 25600 ]; then
    add "[CONTEXT-COST] $f is $((BYTES / 1024)) KB — read on every spec. Trim: scripts/archive-spec-history.sh --keep 5"
  fi
done

# ------------------------------------------------------------ 2b. SC-id traceability
# Both directions over the scenario map (spec 007bs):
#   uncovered  a row claims it is tested or validated, and no test names its id
#   dangling   a test names an id the map does not have
#
# UNCOVERED IS A NOTE, NOT A FINDING -- the deliberate asymmetry. On the project that built this
# gate the honest first report was 122 of 150, and closing the other 28 is a register row's worth
# of work per feature. Wiring that into the exit code would make maintenance permanently red, and
# .claude/rules/github-actions.md already argues that a permanently-red signal is an absent one.
# DANGLING IS A FINDING -- that direction is never a backlog. A test naming an id the map does not
# have is a typo or a row deleted out from under a test, and it is zero on a healthy repo, so the
# signal stays quiet until something actually breaks.
if [ -f scripts/validate-scenario-traceability.sh ] && [ -f specs/SCENARIOS.md ]; then
  TRACE_OUT=$(bash scripts/validate-scenario-traceability.sh --quiet 2>&1)
  TRACE_RC=$?
  case "$TRACE_RC" in
    0|1)
      TRACE_COV=$(printf '%s\n' "$TRACE_OUT" | grep '^coverage:' | head -1)
      [ -n "$TRACE_COV" ] && note "[TRACEABILITY] $TRACE_COV"
      TRACE_DANGL=$(printf '%s\n' "$TRACE_OUT" | sed -n 's/^dangling .*(\([0-9]*\)):$/\1/p')
      if [ -n "$TRACE_DANGL" ] && [ "$TRACE_DANGL" -gt 0 ]; then
        add "[TRACEABILITY] $TRACE_DANGL test reference(s) name an SC-id the scenario map does not have. Run: bash scripts/validate-scenario-traceability.sh"
      fi
      ;;
    *)
      # 2, 3 and 4 all mean "the gate could not answer" -- never reported as coverage.
      add "[TRACEABILITY] scripts/validate-scenario-traceability.sh could not run (exit $TRACE_RC):
$(printf '%s' "$TRACE_OUT" | tail -5)"
      ;;
  esac
fi

# --------------------------------------------- 2c. SIGPIPE assertions in self-tests
# `printf '%s' "$OUT" | grep -q PAT` under `set -o pipefail`: grep leaves at the match, printf keeps
# writing into a reader-less pipe, takes SIGPIPE, and the PIPELINE returns 141 rather than grep's 0. A
# positive assertion then reads a true claim as FALSE; a negated one reports PASS for exactly the state
# it forbids -- the silent direction, and 46 of the 215 sites the gate was first written against. Rows
# H7x and H7aw swept 52 such sites out of eight self-tests; nothing stops the idiom coming back, and a
# template is where one reintroduced line reaches every project on its next session start.
#
# A FINDING, NOT A NOTE -- deliberately the other side of 2b's asymmetry. Uncovered scenarios are a
# backlog and wiring a backlog into the exit code makes maintenance permanently red; this is not a
# backlog. Every hit has a one-line mechanical fix (a here-string), and the gate already declines to
# report what this tree cannot durably fix: downstream it exempts the sync-owned files because those are
# scanned in the template itself (row H7ax). So the number is zero on a healthy repo, and it cannot creep
# up merely because a project got large.
if [ -f scripts/validate-no-sigpipe-assertions.sh ]; then
  SIGPIPE_OUT=$(bash scripts/validate-no-sigpipe-assertions.sh 2>&1)
  SIGPIPE_RC=$?
  case "$SIGPIPE_RC" in
    0) : ;;   # clean, or NOT RUN because every self-test here is sync-owned. Attention mode: say nothing.
    1)
      add "[SIGPIPE] self-test assertion(s) pipe into an early-exit consumer. Under set -o pipefail a true
claim reads as false, and a NEGATED one passes for the state it forbids. Run: bash scripts/validate-no-sigpipe-assertions.sh
$(sed -n '1,6p' <<< "$SIGPIPE_OUT")"
      ;;
    *)
      # 2 is "nothing to scan" or "a boundary I refuse to guess" -- never reported as a clean tree.
      add "[SIGPIPE] scripts/validate-no-sigpipe-assertions.sh could not run (exit $SIGPIPE_RC):
$(tail -5 <<< "$SIGPIPE_OUT")"
      ;;
  esac
fi

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

# THREE THINGS THIS SECTION USED TO GET WRONG, all measured on a real project (2026-08-28) and all
# fixed below. They mattered because this is the ONLY command in a default project that asks for a
# mutation run at all, so whatever it says is the whole of what the developer hears.
#
#   1. THE NUMBER WAS STRYKER'S, THE LABEL WAS NOT. Stryker prints (Killed + Timeout) / valid; a Timeout
#      is not a kill. On one measured gate that gap was 2.31 points in the flattering direction (strict
#      97.69, Stryker 100.00). This section is generic template code and should NOT reimplement a strict
#      scorer -- but printing the generous number as "kill rate" against a strict target is a claim about
#      a measurement nobody made. It is now labelled with its provenance.
#
#   2. THE THRESHOLD WAS HARDCODED 80 WHILE THE CONFIG CARRIED ITS OWN. That project's root config has
#      `break: 79`, so a run at 79.5 PASSED its own gate and was reported as a finding, and a run at 79.0
#      failed nothing and was reported the same way. A config that states its threshold is the authority
#      on its threshold; 80 is the fallback for a config that states none.
#
#   3. A GATE FAILURE WAS REPORTED AS A TOOL CRASH. Stryker exits non-zero when the score is under
#      `break` -- i.e. on the exact outcome the gate exists to produce. "`dotnet stryker` failed to
#      complete:" followed by fifteen lines of tail describes a crash and buries a finding.
#
# And it names its own coverage. A bare `dotnet stryker` reads the config in the working directory, so a
# repo with forty-five committed configs gets exactly one of them measured. Reported without that ratio,
# one gate reads as a suite.
#
# WHAT IT DELIBERATELY DOES NOT DO: start a sweep. A maintenance pass that silently launches a multi-hour
# mutation run across every gate is a worse defect than the one it fixes -- a project that wants that
# owns its own rotation script and schedules it separately.
mutation_break_of() { # mutation_break_of <config path>; echoes the integer break, or nothing
  [ -f "$1" ] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  CFG="$1" python3 - <<'PY' 2>/dev/null
import json, os
try:
    d = json.load(open(os.environ["CFG"]))
except Exception:
    raise SystemExit(0)
d = d.get("stryker-config", d)
b = (d.get("thresholds") or {}).get("break")
if isinstance(b, (int, float)):
    print(int(b))
PY
}

if [ -n "$MUTATION_CMD" ]; then
  if [ "$FULL" -eq 1 ]; then
    # Which config this bare invocation will actually read, and how many exist. Both tools default to a
    # config in the working directory; the count is what turns "one gate" into an honest sentence.
    case "$MUTATION_CMD" in
      dotnet*) MUT_CFG="stryker-config.json" ;;
      *)       MUT_CFG="stryker.conf.json" ;;
    esac
    MUT_CFG_TOTAL=$(find . -type d \( -name node_modules -o -name StrykerOutput -o -name bin -o -name obj -o -name .git \) -prune -o \
                      -type f \( -name 'stryker-config*.json' -o -name 'stryker.conf*.json' \) -print 2>/dev/null | wc -l | tr -d ' ')
    case "$MUT_CFG_TOTAL" in (''|*[!0-9]*) MUT_CFG_TOTAL=1 ;; esac
    [ "$MUT_CFG_TOTAL" -lt 1 ] && MUT_CFG_TOTAL=1
    MUT_SCOPE="1 of $MUT_CFG_TOTAL config(s) — a bare \`$MUTATION_CMD\` reads only $MUT_CFG"

    MUT_OUT=$(eval "$MUTATION_CMD" 2>&1)
    MUT_RC=$?
    SCORE=$(printf '%s' "$MUT_OUT" | grep -oE 'mutation score[^0-9]*[0-9]+(\.[0-9]+)?' | tail -1 | grep -oE '[0-9]+(\.[0-9]+)?' | tail -1)
    INT_SCORE=${SCORE%%.*}

    MUT_BREAK=$(mutation_break_of "$MUT_CFG")
    if [ -n "$MUT_BREAK" ]; then
      MUT_LIMIT="$MUT_BREAK"; MUT_LIMIT_SRC="$MUT_CFG thresholds.break"
    else
      MUT_LIMIT=80;           MUT_LIMIT_SRC="the ~80% default target (this config states no break)"
    fi

    if [ "$MUT_RC" -ne 0 ] && [ -n "$SCORE" ]; then
      # A number came back, so the tool ran. Non-zero here is the gate doing its job.
      add "[MUTATION] GATE FAILED — Stryker's own score ${SCORE}% against $MUT_LIMIT_SRC ($MUT_LIMIT).
  This is the gate failing, not the tool crashing: Stryker exits non-zero when the score is under break.
  Scope: $MUT_SCOPE.
  NOTE: ${SCORE}% is Stryker's score, (Killed + Timeout) / valid. A Timeout is not a kill, so the strict
  score is this or lower — never higher (.claude/docs/testing.md)."
    elif [ "$MUT_RC" -ne 0 ]; then
      add "[MUTATION] \`$MUTATION_CMD\` failed to complete — no score was produced:
$(printf '%s' "$MUT_OUT" | tail -15)"
    elif [ -n "$SCORE" ]; then
      if [ "${INT_SCORE:-0}" -lt "$MUT_LIMIT" ]; then
        add "[MUTATION] Stryker's own score ${SCORE}% is below $MUT_LIMIT_SRC ($MUT_LIMIT).
  Scope: $MUT_SCOPE.
  NOTE: ${SCORE}% counts a Timeout as a kill; the strict score (Killed / valid) is this or lower."
      fi
    else
      # Exit 0 and no parseable score is not a pass -- it is a run this section cannot classify, and
      # saying nothing about it would report an unmeasured gate as a measured one.
      add "[MUTATION] \`$MUTATION_CMD\` exited 0 but printed no mutation score — the run cannot be classified.
  Scope: $MUT_SCOPE."
    fi
  else
    REPORT="${REPORT}[skipped] mutation pass — re-run with --full to execute \`$MUTATION_CMD\` (slow, and it covers only the working-directory config).
"
  fi
fi

# ------------------------------------------------------------------------ verdict
if [ "$FINDINGS" -eq 0 ]; then
  [ "$QUIET" -eq 1 ] && exit 0
  echo "project-maintenance: clean — no secrets, no CVEs, no register drift, no context bloat.$([ "$FULL" -eq 0 ] && [ -n "$MUTATION_CMD" ] && printf ' (mutation pass skipped — use --full)')"
  [ -n "$NOTES" ] && printf '%s' "$NOTES"
  exit 0
fi

echo "project-maintenance: $FINDINGS finding(s) — $(date -u +%Y-%m-%d)"
echo
printf '%s' "$REPORT"
[ -n "$NOTES" ] && printf '%s' "$NOTES"
echo "Each finding needs an explicit fix / defer / dismiss decision per .claude/rules/validation-followup.md."
exit 1

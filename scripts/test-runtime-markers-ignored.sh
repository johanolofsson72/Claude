#!/usr/bin/env bash
# test-runtime-markers-ignored.sh — every machine-local marker the hooks write is gitignored,
# every record they mean to commit is not, and a marker nobody classified is a failure.
#
# WHY THIS EXISTS (spec 007bq)
# ---------------------------
# Two hand-written lists decide which .claude/ runtime paths get ignored: this repository's own
# .gitignore, and section "3a. .gitignore additions" in .claude/skills/sync-template/SKILL.md, which
# is what seeds a project during /project-update. Neither was derived from the set of paths the
# hooks actually write, and by 2026-08-28 they had drifted from the hooks and from each other:
# .claude/.bash-write-marker was ignored in neither, and churned in 5 of the 7 repositories running
# the guard — the template among them. Its sibling .claude/.bash-write-blocked was ignored in 0 of
# 73. Both were found by a developer noticing a dirty `git status`, months apart.
#
# So the lists stop being the only thing standing between a new marker and permanent churn.
#
# WHAT IS DECLARED AND WHAT IS DERIVED
# ------------------------------------
# Declared: the two buckets below, with a reason per entry. Whether a path is churn or a record
# meant to be committed is a judgment, and a judgment belongs in an argued list a reviewer can
# contest — the same idiom as EXEMPTIONS in bash-write-detect-hook.sh and EXCLUDED in run-gates.sh.
# Derived: completeness. Assertion C reads scripts/*.sh and fails on any .claude/.<marker> that is
# in neither bucket, which is the only assertion here that protects against the NEXT marker rather
# than the last two.
#
# LIMIT, stated rather than implied: assertion C greps for literal `.claude/.name` text. All 16
# current paths are written that way, but one assembled from a variable would evade it. This is a
# strong net over the idiom in use, not a proof.
#
# ORACLE: `git check-ignore`, never a grep for a line in .gitignore. Nine .local-llm-* paths are
# covered by one glob, the answer is needed for paths with no file on disk, and a machine-local
# marker somebody committed by accident must fail rather than pass on a rule git no longer applies
# to it.
#
#   bash scripts/test-runtime-markers-ignored.sh              # check this repository
#   bash scripts/test-runtime-markers-ignored.sh --self-test  # prove the four assertions can fail

set -u

# --------------------------------------------------------------- the declared buckets
# path%reason.  Machine-local: MUST be gitignored.
MACHINE_LOCAL='.claude/.bash-write-marker%bash-write guard timestamp, re-stamped on every Bash write
.claude/.bash-write-blocked%bash-write guard escape-hatch record (the file set of the last block)
.claude/.template-sync-check%auto-sync rate-limit marker (mtime only; the manifest .template-sync is tracked)
.claude/.local-llm-cache%local-LLM response cache
.claude/.local-llm-commit-draft%local-LLM draft, regenerated on demand
.claude/.local-llm-pr-draft%local-LLM draft, regenerated on demand
.claude/.local-llm-readme-draft%local-LLM draft, regenerated on demand
.claude/.local-llm-env-example-draft%local-LLM draft, regenerated on demand
.claude/.local-llm-gitignore-draft%local-LLM draft, regenerated on demand
.claude/.local-llm-pr-context%local-LLM scratch context for one invocation
.claude/.local-llm-issue-context%local-LLM scratch context for one invocation
.claude/.local-llm-gh-run-context%local-LLM scratch context for one invocation
.claude/state/%repeat-failure guard attempt counters, TTL-pruned
.claude/validation/%Stop-hook validation timestamp'

# Tracked by design: MUST NOT be gitignored.
#
# Phrased "must not be ignored" rather than "must be tracked" on purpose. In the template these four
# do not exist at all — the template is the source, so it syncs from nothing and has no manifest of
# its own. "Not ignored" is true of an absent path; "tracked" is not, and would fail the test in the
# one repository that authors it.
TRACKED_BY_DESIGN='.claude/.template-sync%the sync manifest — a project commits it, it is how drift is detected
.claude/.sync-stack%the declared stack for this project, read by the guards
.claude/.sync-local%accepted intentional differences from the template
.claude/.template-sync-verify%the verify command this project declares for its sync commits'

SKILL_REL=".claude/skills/sync-template/SKILL.md"

# ------------------------------------------------------------------------- helpers
FAILURES=0
CHECKS=0
fail() { FAILURES=$((FAILURES + 1)); printf 'FAIL  %s\n' "$*"; }
pass() { CHECKS=$((CHECKS + 1)); }

col1() { printf '%s\n' "$1" | cut -d'%' -f1; }
reason_for() { printf '%s\n' "$1" | awk -F'%' -v p="$2" '$1==p{print $2; exit}'; }

# Does one section-3a pattern cover this path? Trailing slash is a directory prefix; everything
# else is a shell glob, which is what git means by these patterns too.
covered_by() { # $1=path $2=pattern
  case "$2" in
    */) case "$1" in "$2"*) return 0 ;; esac; [ "$1" = "$2" ] && return 0 ;;
    *)  case "$1" in $2) return 0 ;; esac ;;
  esac
  return 1
}

# The patterns section 3a tells a project to add, read out of the backticked bullets.
skill_patterns() { # $1=path to SKILL.md
  [ -f "$1" ] || return 0
  awk '/^### 3a\./{s=1; next} s && /^### /{exit} s' "$1" \
    | grep -oE '`\.claude/[^`]+`' | tr -d '`' | sort -u
}

# ------------------------------------------------------------------- the four assertions
run_checks() { # $1=repo root  $2=SKILL.md path (may be absent)
  local root="$1" skill="$2" p reason pat found line

  # --- A: every machine-local path is ignored.  The row's bug, and its sibling.
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if git -C "$root" check-ignore -q "$p" 2>/dev/null; then
      pass
    else
      reason=$(reason_for "$MACHINE_LOCAL" "$p")
      fail "[A] machine-local but NOT gitignored: $p"
      printf '        %s\n' "$reason"
      printf '        add it to %s/.gitignore — it is re-written during a normal session and\n' "$root"
      printf '        means nothing in another machine'"'"'s history.\n'
    fi
  done <<EOF
$(col1 "$MACHINE_LOCAL")
EOF

  # --- B: no tracked-by-design record is ignored.  A rule that swallowed the manifest.
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if git -C "$root" check-ignore -q "$p" 2>/dev/null; then
      reason=$(reason_for "$TRACKED_BY_DESIGN" "$p")
      fail "[B] tracked by design but IS gitignored: $p"
      printf '        %s\n' "$reason"
      printf '        an ignore rule here hides the record instead of the churn.\n'
    else
      pass
    fi
  done <<EOF
$(col1 "$TRACKED_BY_DESIGN")
EOF

  # --- C: every .claude/.<marker> the scripts write is classified.  The next marker.
  # --exclude this file: its header states the grep's limit using `.claude/.name`, and its
  # self-test fixture writes `.claude/.some-new-marker` on purpose. A gate that flagged its own
  # worked examples would have to be silenced, and a silenced gate is not one.
  found=$(grep -rhoE '\.claude/\.[A-Za-z0-9_-]+' \
            --exclude="$(basename "$0")" "$root"/scripts/*.sh 2>/dev/null | sort -u)
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if { col1 "$MACHINE_LOCAL"; col1 "$TRACKED_BY_DESIGN"; } | grep -qxF "$p"; then
      pass
    else
      fail "[C] a marker no bucket claims: $p"
      printf '        scripts/ writes this path and nothing in this test says what it is.\n'
      printf '        Classify it: MACHINE_LOCAL if it is churn — a timestamp, a cache, a draft,\n'
      printf '        anything re-written during a normal session and meaningless on another\n'
      printf '        machine — and then gitignore it. TRACKED_BY_DESIGN if it is a record this\n'
      printf '        project is meant to commit. That judgment is the one thing this test\n'
      printf '        cannot make for you, which is why it stops here.\n'
    fi
  done <<EOF
$found
EOF

  # --- D: section 3a seeds every machine-local path, so a NEW project inherits all of them.
  if [ -f "$skill" ]; then
    pat=$(skill_patterns "$skill")
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      found=no
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        covered_by "$p" "$line" && { found=yes; break; }
      done <<EOF2
$pat
EOF2
      if [ "$found" = yes ]; then
        pass
      else
        fail "[D] not seeded to new projects: $p"
        printf '        %s\n' "$(reason_for "$MACHINE_LOCAL" "$p")"
        printf '        add a bullet under "### 3a. .gitignore additions" in %s —\n' "$SKILL_REL"
        printf '        ignoring it here does nothing for the next project set up from the template.\n'
      fi
    done <<EOF3
$(col1 "$MACHINE_LOCAL")
EOF3
  else
    printf 'skip  [D] %s not present in this repository\n' "$SKILL_REL"
  fi
}

# ------------------------------------------------------------------------ self-test
# Four fixtures, one per assertion. A gate nobody has watched fail is a gate nobody knows the shape
# of — this register already carries a row for a falsification arm that falsified nothing (007br),
# so each arm here reverts one real thing and asserts THAT path is named.
self_test() {
  local st_fail=0 st_pass=0 d
  ST_TMP=$(mktemp -d) || { echo "cannot mktemp"; exit 2; }
  trap 'rm -rf "$ST_TMP"' EXIT

  arm() { # $1=name  $2=fixture dir  $3=expected substring
    local o
    o=$(FAILURES=0; CHECKS=0; run_checks "$2" "$2/$SKILL_REL" 2>&1)
    if printf '%s' "$o" | grep -q '^FAIL ' && printf '%s' "$o" | grep -qF "$3"; then
      st_pass=$((st_pass + 1)); printf 'ok    %s\n' "$1"
    else
      st_fail=$((st_fail + 1)); printf 'NOT OK %s — expected a failure naming: %s\n' "$1" "$3"
      printf '%s\n' "$o" | sed 's/^/         | /'
    fi
  }

  # A fixture repository carrying the full correct set, which each arm then breaks one way.
  mk() { # $1=name -> echoes path
    local d="$ST_TMP/$1"
    mkdir -p "$d/scripts" "$d/$(dirname "$SKILL_REL")"
    git -C "$d" init -q 2>/dev/null || git init -q "$d"
    printf '.claude/.bash-write-marker\n.claude/.bash-write-blocked\n.claude/.template-sync-check\n.claude/.local-llm-*\n.claude/state/\n.claude/validation/\n' > "$d/.gitignore"
    { echo '### 3a. .gitignore additions'
      echo '- `.claude/.bash-write-marker` (t)'
      echo '- `.claude/.bash-write-blocked` (t)'
      echo '- `.claude/.template-sync-check` (t)'
      echo '- `.claude/.local-llm-*` (t)'
      echo '- `.claude/state/` (t)'
      echo '- `.claude/validation/` (t)'
      echo '### 3b. next'; } > "$d/$SKILL_REL"
    printf '#!/usr/bin/env bash\n: > "$ROOT/.claude/.bash-write-marker"\n' > "$d/scripts/h.sh"
    printf '%s\n' "$d"
  }

  # A — a machine-local marker loses its ignore rule.  This is the bug in the row.
  d=$(mk a); grep -v '^\.claude/\.bash-write-marker$' "$d/.gitignore" > "$d/.g" && mv "$d/.g" "$d/.gitignore"
  arm "A: unignored machine-local marker is caught" "$d" "[A] machine-local but NOT gitignored: .claude/.bash-write-marker"

  # B — an ignore rule swallows a record meant to be committed.
  d=$(mk b); echo '.claude/.template-sync' >> "$d/.gitignore"
  arm "B: an ignored sync record is caught" "$d" "[B] tracked by design but IS gitignored: .claude/.template-sync"

  # C — a hook author adds a marker and classifies it nowhere.  The next marker.
  d=$(mk c); printf '#!/usr/bin/env bash\n: > "$ROOT/.claude/.some-new-marker"\n' > "$d/scripts/new.sh"
  arm "C: an unclassified new marker is caught" "$d" "[C] a marker no bucket claims: .claude/.some-new-marker"

  # D — the seeding list drops an entry, so new projects inherit an incomplete set.
  d=$(mk d); grep -v 'bash-write-blocked' "$d/$SKILL_REL" > "$d/.s" && mv "$d/.s" "$d/$SKILL_REL"
  arm "D: a dropped section-3a entry is caught" "$d" "[D] not seeded to new projects: .claude/.bash-write-blocked"

  printf '\nself-test: %d passed, %d failed\n' "$st_pass" "$st_fail"
  [ "$st_fail" -eq 0 ] || return 1
  return 0
}

# --------------------------------------------------------------------------- main
if [ "${1-}" = "--self-test" ]; then
  self_test; exit $?
fi

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || ROOT=""
if [ -z "$ROOT" ]; then
  # Labelled, never silent: a skip that reads like a pass is the exact shape this register keeps
  # recording (checkpoint F-11 — the gate reporting something other than what it measured).
  printf 'skip: not inside a git repository — `git check-ignore` has nothing to answer against.\n'
  exit 0
fi

run_checks "$ROOT" "$ROOT/$SKILL_REL"

if [ "$FAILURES" -eq 0 ]; then
  printf 'ok: %d runtime-marker checks passed (%d machine-local, %d tracked by design).\n' \
    "$CHECKS" "$(col1 "$MACHINE_LOCAL" | grep -c .)" "$(col1 "$TRACKED_BY_DESIGN" | grep -c .)"
  exit 0
fi
printf '\n%d of %d runtime-marker checks failed.\n' "$FAILURES" "$((FAILURES + CHECKS))"
exit 1

#!/bin/bash
# Self-test for scripts/project-maintenance.sh — the abandoned-agent-worktree section (spec 007bk).
#
# Travels with the script into every project, for the same reason test-project-freshness.sh and
# test-detect-verify-command.sh do: a report whose test stays behind is a report nobody can
# re-check where it actually runs.
#
#   bash scripts/test-project-maintenance.sh
#
# What is under test is the DECISION — which worktrees does the section call abandoned, what does
# it say about them, and does it still change nothing. Not the other five sections: every fixture
# gets a stub scripts/project-freshness.sh that exits 0, so the secrets/CVE pass is silent, and no
# fixture carries a manifest or a solution file, so the mutation section never arms. Nothing
# touches the network and the suite runs in about a second.
#
# H1/F-04 is the failure this exists to prevent recurring: prune-agent-worktrees.sh existed the
# whole time and ran only when somebody remembered, while the fleet accumulated 7 abandoned
# worktrees, 733 MB, and 6 agent-memory files that existed nowhere else.
#
# The single most load-bearing case here is C8. This section reports on a destructive tool, and
# the moment it starts calling that tool it stops being a report — so C8 hashes the whole fixture
# before and after and fails on any difference at all.
#
# bash 3.2-safe (macOS system bash): no associative arrays, no mapfile, no ${var,,}.

set -u

DIR=$(cd "$(dirname "$0")" && pwd)
MAINT="$DIR/project-maintenance.sh"
TMP=$(mktemp -d 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/project-maintenance-test.$$")
PASS=0
FAIL=0

cleanup() {
  # Registered worktrees inside the fixtures hold on after rm -rf; drop them first so the
  # temp dir actually goes away and nothing is left pointing into /var/folders.
  for wtrepo in "$TMP"/*; do
    [ -d "$wtrepo/.git" ] || continue
    ( cd "$wtrepo" && git worktree list --porcelain 2>/dev/null | awk '$1=="worktree"{print $2}' ) 2>/dev/null |
      while read -r w; do
        [ "$w" = "$wtrepo" ] && continue
        ( cd "$wtrepo" && git worktree unlock "$w" >/dev/null 2>&1; git worktree remove --force "$w" >/dev/null 2>&1 )
      done
  done
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}
trap cleanup EXIT

ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"; }

# $1 name · $2 substring that must appear · $3 output
expect_contains() {
  if printf '%s\n' "$3" | grep -Fq -e "$2"; then ok "$1"; else
    bad "$1" "output contains '$2'" "$(printf '%s' "$3" | tr '\n' '|')"; fi
}

# $1 name · $2 substring that must NOT appear · $3 output
expect_absent() {
  if printf '%s\n' "$3" | grep -Fq -e "$2"; then
    bad "$1" "output does NOT contain '$2'" "$(printf '%s' "$3" | tr '\n' '|')"; else ok "$1"; fi
}

# $1 name · $2 expected rc · $3 actual rc
expect_rc() {
  if [ "$3" = "$2" ]; then ok "$1"; else bad "$1" "exit $2" "exit $3"; fi
}

# A fixture is a git repo with the maintenance script's siblings stubbed out, so only the
# worktree section can speak.
mkfix() {
  d="$TMP/$1"
  mkdir -p "$d/scripts" "$d/.claude"
  ( cd "$d" && git init -q . >/dev/null 2>&1 )
  printf '#!/bin/bash\nexit 0\n' > "$d/scripts/project-freshness.sh"
  printf '#!/bin/bash\nexit 0\n' > "$d/scripts/prune-agent-worktrees.sh"
  printf '%s' "$d"
}

# A directory under .claude/worktrees that looks like an agent left it behind. `touch -t` is the
# reliable way to age a fixture: relying on a zero-hour grace window would be testing find's
# rounding rather than this script's decision.
mkstale() {
  mkdir -p "$1"
  printf 'work in progress\n' > "$1/file.txt"
  find "$1" -exec touch -t 202001010000 {} + 2>/dev/null
}

run() { ( cd "$1" && shift; env "$@" bash "$MAINT" 2>&1 ); }

snapshot() {
  ( cd "$1" && find . -type f -not -path './.git/*' -print0 2>/dev/null |
    xargs -0 shasum 2>/dev/null | sort )
}

printf 'project-maintenance self-test (abandoned agent worktrees)\n'

# --------------------------------------------------------------- C1 — no worktrees at all (AC1)
# The overwhelmingly common case: a project that never used worktree isolation. The section must
# not run, and must not contribute a reassurance line either — a weekly job that lists what did
# not happen is the noise attention mode exists to prevent.
D=$(mkfix c1)
OUT=$(run "$D"); RC=$?
expect_absent "C1 no .claude/worktrees — no WORKTREES finding" "[WORKTREES]" "$OUT"
expect_absent "C1 no .claude/worktrees — no reassurance line"  "worktree" "$OUT"
expect_rc     "C1 no .claude/worktrees — clean exit" 0 "$RC"

# -------------------------------------------------- C2 — the directory exists but is empty (AC2)
D=$(mkfix c2); mkdir -p "$D/.claude/worktrees"
OUT=$(run "$D"); RC=$?
expect_absent "C2 empty worktrees dir — no finding" "[WORKTREES]" "$OUT"
expect_rc     "C2 empty worktrees dir — clean exit" 0 "$RC"

# --------------------------------------------- C3 — a worktree an agent is using right now (AC3)
# The false positive that would make this section worthless. Agent worktrees are not locked, so
# the only signal is that something was written lately — and a run in progress must stay silent.
D=$(mkfix c3)
mkdir -p "$D/.claude/worktrees/agent-live"; printf 'fresh\n' > "$D/.claude/worktrees/agent-live/file.txt"
OUT=$(run "$D"); RC=$?
expect_absent "C3 worktree written to just now — presumed live, no finding" "[WORKTREES]" "$OUT"
expect_rc     "C3 worktree written to just now — clean exit" 0 "$RC"

# ------------------------------------------- C4 — an abandoned worktree, and what it says (AC4/5)
D=$(mkfix c4); mkstale "$D/.claude/worktrees/agent-dead"
OUT=$(run "$D"); RC=$?
expect_contains "C4 stale worktree — reported"            "[WORKTREES] 1 abandoned agent worktree(s)" "$OUT"
expect_contains "C4 stale worktree — age in days named"   "oldest " "$OUT"
expect_contains "C4 stale worktree — window named"        "untouched for over 24h" "$OUT"
expect_contains "C4 stale worktree — names the sweep"     "prune-agent-worktrees.sh --dry-run" "$OUT"
expect_rc       "C4 stale worktree — non-zero exit" 1 "$RC"

# ----------------------------------------------------- C5 — two worktrees, still one finding (AC4)
# One block regardless of count. Per-worktree detail is exactly what the sweep's --dry-run prints,
# and duplicating it here invites the two to disagree.
D=$(mkfix c5)
mkstale "$D/.claude/worktrees/agent-dead1"; mkstale "$D/.claude/worktrees/agent-dead2"
OUT=$(run "$D")
expect_contains "C5 two stale worktrees — counted together" "[WORKTREES] 2 abandoned agent worktree(s)" "$OUT"
expect_rc "C5 two stale worktrees — exactly one finding block" 1 \
  "$(printf '%s\n' "$OUT" | grep -c '\[WORKTREES\]')"

# ------------------------------------------------------ C6 — memory that exists only in here (AC6)
# The cost that is not disk. A file present in both places is already safe and must not inflate
# the number; a file present only in the worktree is what the developer needs to know about.
D=$(mkfix c6)
mkdir -p "$D/.claude/agent-memory/security-scanner" "$D/.claude/worktrees/agent-dead/.claude/agent-memory/security-scanner"
printf 'shared\n' > "$D/.claude/agent-memory/security-scanner/shared.md"
printf 'shared\n' > "$D/.claude/worktrees/agent-dead/.claude/agent-memory/security-scanner/shared.md"
printf 'only here\n' > "$D/.claude/worktrees/agent-dead/.claude/agent-memory/security-scanner/orphan.md"
printf '# index\n'  > "$D/.claude/worktrees/agent-dead/.claude/agent-memory/MEMORY.md"
find "$D/.claude/worktrees" -exec touch -t 202001010000 {} + 2>/dev/null
OUT=$(run "$D")
expect_contains "C6 counts only the file with no counterpart, MEMORY.md excluded" \
  "1 agent-memory file(s) exist only inside them" "$OUT"

# -------------------------------------------------------------- C7 — the grace window is real (AC7)
# Aged two hours: silent at the 24h default, reported when the window is narrowed to one hour.
D=$(mkfix c7)
mkdir -p "$D/.claude/worktrees/agent-recent"
printf 'two hours ago\n' > "$D/.claude/worktrees/agent-recent/file.txt"
TS=$(date -v-2H '+%Y%m%d%H%M' 2>/dev/null || date -d '2 hours ago' '+%Y%m%d%H%M' 2>/dev/null)
if [ -n "$TS" ]; then
  find "$D/.claude/worktrees" -exec touch -t "$TS" {} + 2>/dev/null
  OUT=$(run "$D")
  expect_absent "C7 two hours old — silent at the 24h default" "[WORKTREES]" "$OUT"
  OUT=$(run "$D" MAINTENANCE_WORKTREE_GRACE_HOURS=1)
  expect_contains "C7 two hours old — reported at GRACE_HOURS=1" "[WORKTREES] 1 abandoned" "$OUT"
  expect_contains "C7 the narrowed window is named in the finding" "untouched for over 1h" "$OUT"
else
  ok "C7 skipped — no portable way to stamp a relative timestamp on this host"
fi

# ------------------------------------------------ C8 — the section changes NOTHING (AC10)
# The load-bearing one. This section reports on a destructive tool; the day it starts calling that
# tool it stops being a report. Hash everything before and after.
D=$(mkfix c8)
mkstale "$D/.claude/worktrees/agent-dead"
mkdir -p "$D/.claude/worktrees/agent-dead/.claude/agent-memory"
printf 'orphan\n' > "$D/.claude/worktrees/agent-dead/.claude/agent-memory/orphan.md"
find "$D/.claude/worktrees" -exec touch -t 202001010000 {} + 2>/dev/null
BEFORE=$(snapshot "$D")
OUT=$(run "$D")
AFTER=$(snapshot "$D")
if [ "$BEFORE" = "$AFTER" ]; then ok "C8 report-only — fixture byte-identical afterwards"
else bad "C8 report-only — fixture byte-identical afterwards" "no change" "$(diff <(printf '%s' "$BEFORE") <(printf '%s' "$AFTER") | head -5)"; fi
expect_contains "C8 …and it still reported the worktree" "[WORKTREES] 1 abandoned" "$OUT"

# ------------------------------------------------ C9 — the sweep the finding points at is gone (AC9)
# Pointing a developer at a command that is not there would be worse than the silence being fixed.
D=$(mkfix c9); rm -f "$D/scripts/prune-agent-worktrees.sh"
mkstale "$D/.claude/worktrees/agent-dead"
OUT=$(run "$D"); RC=$?
expect_contains "C9 missing sweep script — [SETUP] finding" "[SETUP]" "$OUT"
expect_contains "C9 missing sweep script — names it"        "prune-agent-worktrees.sh is missing" "$OUT"
expect_absent   "C9 missing sweep script — no dangling command to run" "--dry-run" "$OUT"
expect_rc       "C9 missing sweep script — non-zero exit" 1 "$RC"

# ------------------------------------------- C10 — a non-agent directory is not ours to judge (AC2)
D=$(mkfix c10); mkstale "$D/.claude/worktrees/my-own-branch"
OUT=$(run "$D"); RC=$?
expect_absent "C10 non-agent worktree dir — not reported" "[WORKTREES]" "$OUT"
expect_rc     "C10 non-agent worktree dir — clean exit" 0 "$RC"

# ------------------------------- C11 — a stale worktree locked by a live process is live (AC8)
# This rarely fires in the wild — the harness does not lock what it creates — but the sweep
# honours locks, and a report that disagreed about liveness with the tool it recommends would be
# worse than useless. Needs a genuinely registered worktree, so this fixture gets a commit.
D=$(mkfix c11)
( cd "$D" && printf 'x\n' > seed.txt && git add -A >/dev/null 2>&1 &&
  git -c user.email=t@t -c user.name=t commit -qm seed >/dev/null 2>&1 &&
  git worktree add -q .claude/worktrees/agent-locked -b wt-locked >/dev/null 2>&1 &&
  git worktree lock --reason "agent pid $$" .claude/worktrees/agent-locked >/dev/null 2>&1 )
if [ -e "$D/.claude/worktrees/agent-locked/.git" ]; then
  find "$D/.claude/worktrees/agent-locked" -exec touch -t 202001010000 {} + 2>/dev/null
  OUT=$(run "$D")
  expect_absent "C11 stale but locked by a live pid — not reported" "[WORKTREES]" "$OUT"
else
  ok "C11 skipped — git worktree add unavailable on this host"
fi

# ----------------------------- C12 — a find that cannot answer must not be believed (AC14)
# The nastiest failure this section can have. A find that cannot parse a relative -newermt
# matches nothing and says so only on stderr, which is byte-for-byte what "no recent writes"
# looks like — so every worktree on the machine gets declared abandoned at once, on a machine
# where the evidence was never gathered. Shim find so it refuses -newermt and delegates
# everything else, and require the section to say it could not tell rather than guess.
D=$(mkfix c12); mkstale "$D/.claude/worktrees/agent-dead"
mkdir -p "$TMP/shim"
cat > "$TMP/shim/find" <<'SHIM'
#!/bin/bash
for a in "$@"; do
  if [ "$a" = "-newermt" ]; then echo "find: Can't parse date/time" >&2; exit 1; fi
done
exec /usr/bin/find "$@"
SHIM
chmod +x "$TMP/shim/find"
OUT=$( cd "$D" && PATH="$TMP/shim:$PATH" bash "$MAINT" 2>&1 ); RC=$?
expect_contains "C12 unparseable -newermt — says it could not tell" "cannot evaluate a relative" "$OUT"
expect_absent   "C12 unparseable -newermt — does NOT claim worktrees are abandoned" "[WORKTREES]" "$OUT"
expect_rc       "C12 unparseable -newermt — non-zero exit" 1 "$RC"

# ------------------------------- C13 — a memory path with a space is still counted (AC6)
# Word-splitting a find's output loses these silently, and a silent miscount is the exact
# class of failure this section was written to end. Agent-generated names are slugs today,
# which is why this needs a test rather than trust.
D=$(mkfix c13)
mkdir -p "$D/.claude/worktrees/agent-dead/.claude/agent-memory"
printf 'x\n' > "$D/.claude/worktrees/agent-dead/.claude/agent-memory/two words.md"
printf 'y\n' > "$D/.claude/worktrees/agent-dead/.claude/agent-memory/plain.md"
find "$D/.claude/worktrees" -exec touch -t 202001010000 {} + 2>/dev/null
OUT=$(run "$D")
expect_contains "C13 space in a memory filename — counted, not split" \
  "2 agent-memory file(s) exist only inside them" "$OUT"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1

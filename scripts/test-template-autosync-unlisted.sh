#!/bin/bash
# Tests the [unlisted] predicate in scripts/template-autosync.sh — unlisted_core_shaped (row H7bk).
#
# WHY THIS EXISTS
# ---------------
# The predicate shipped with spec 007ca calibrated (13 unmanaged / 1 flagged / 0 false positives on
# one tree, 18 / 4 / 0 replayed against the event it was built for) and with NO harness at all. It
# then fed scripts/core-owed-tick-guard-hook.sh, which denies a register tick on any finding — so a
# false positive is not a noisy line, it is a project that cannot tick a row.
#
# That is what happened. Two CORE scripts name consultpilots run-gates.sh in four WHOLE-LINE
# COMMENTS, and .claude/settings.json named its Stop hook. Neither is a dependency: a comment
# survives the sync as a comment, and settings.json is merged by sync-core-hooks.py rather than
# overwritten, with project-specific hooks preserved verbatim. The tick guard was therefore
# permanently red on that project, every row was ticked through ALLOW_TICK_WITH_CORE_OWED, and an
# override taken every time announces nothing.
#
# WHAT IS UNDER TEST, AND WHY IT IS FIVE OWNERSHIP CASES AND NOT ONE
# ------------------------------------------------------------------
# The predicate is "unmanaged, and named by a file whose bytes the next sync replaces". Getting it
# right means DISCRIMINATING, in one run, between five ways a script can be named. A harness that
# only proved the two silences would pass just as well against a predicate that reports nothing,
# which is the failure mode a detector fails into most quietly.
#
#   SC-1828  real code dependency in a CORE .sh          -> FLAG
#   SC-1829  whole-line comment in a CORE .sh            -> silent   (the H7bk defect)
#   SC-1830  instructional prose in a CORE .md rule      -> FLAG     (# is a heading in markdown)
#   SC-1831  hook command in .claude/settings.json       -> silent   (merged, not overwritten)
#   SC-1833  named by nobody                             -> silent
#   SC-1836  code with a trailing `# … scripts/x.sh`     -> FLAG     (the rule is exact, not clever)
#   SC-1837  whole-line comment in a CORE .py            -> silent
#
# SC-1832 replays 007cas own calibration corpus so the comment rule cannot silently cost recall, and
# SC-1834 is the sabotage arm: with the rule removed, the arm that demands silence must redden. A
# gate nobody has watched fail is a report.
#
# Run: bash scripts/test-template-autosync-unlisted.sh
# Exit: 0 all arms passed · 1 an arm failed

set -u
cd "$(dirname "$0")/.." || exit 1
SCRIPT="$PWD/scripts/template-autosync.sh"
[ -f "$SCRIPT" ] || { echo "FAIL: template-autosync.sh not found"; exit 1; }

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
skip() { SKIP=$((SKIP+1)); printf '  SKIP %s — %s\n' "$1" "$2"; }
has()   { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 (missing '$3' in: $(printf '%s' "$2" | tr '\n' '|'))" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1 (unexpected '$3' in: $(printf '%s' "$2" | tr '\n' '|'))" ;; *) ok "$1" ;; esac; }
same()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$3', got '$2')"; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# The referring files must be genuinely CORE. unlisted_core_shaped filters on the same
# $CORE_SCRIPTS / $CORE_RULES the rest of the script reads, so an invented `demo-hook.sh` would be
# invisible to it and every assertion below would pass against a broken predicate.
CORE_SH="scripts/bash-write-detect-hook.sh"
CORE_PY="scripts/sync-core-hooks.py"
CORE_RULE=".claude/rules/scenarios.md"

# ---------------------------------------------------------------------------------------------
# The five-way tree. One project, one run, every ownership case present at once — because the
# property under test is discrimination, and a per-case tree cannot show it.
# ---------------------------------------------------------------------------------------------
build_five_way() {
  R="$TMP/fiveway"; rm -rf "$R"
  mkdir -p "$R/.git" "$R/.claude/rules" "$R/scripts"

  # A manifest must exist: project mode treats "no manifest" as no evidence and returns nothing, so
  # without this the tree is silent for the wrong reason and every silence arm passes vacuously.
  printf 'sha=deadbeef\nsynced=2026-01-01T00:00:00Z\nsource=/dev/null\n# manifest\n' \
    > "$R/.claude/.template-sync"

  cat > "$R/$CORE_SH" <<'EOF'
#!/usr/bin/env bash
# Same idiom as EXCLUDED in scripts/prose-only-helper.sh: a reason is written down, never implied.
  # An indented comment is still a comment, and this one names scripts/indented-prose-helper.sh.
. "$(dirname "$0")/real-dep-helper.sh"
bash scripts/real-dep-helper.sh --check
bash scripts/trailing-comment-helper.sh   # see scripts/trailing-comment-helper.sh for why
EOF

  cat > "$R/$CORE_PY" <<'EOF'
#!/usr/bin/env python3
# Ported from scripts/py-prose-helper.sh; the shell version is gone.
import sys
sys.exit(0)
EOF

  # Markdown: `#` is a heading, and the sentence below is an instruction. Every finding in the
  # calibration corpus has this shape, which is why the comment rule must not touch .md.
  cat > "$R/$CORE_RULE" <<'EOF'
# Scenario map rule

Prove it mechanically: `scripts/rule-named-helper.sh` is that gate. Eyeballing a diff is not a check.
EOF

  cat > "$R/.claude/settings.json" <<'EOF'
{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR/scripts/settings-named-helper.sh\""}]}]}}
EOF

  for f in real-dep-helper prose-only-helper indented-prose-helper py-prose-helper \
           rule-named-helper settings-named-helper trailing-comment-helper nobody-names-me; do
    : > "$R/scripts/$f.sh"
  done
  printf '%s' "$R"
}

echo "== unlisted_core_shaped — five ownership cases in one run"
R=$(build_five_way)
OUT=$(CLAUDE_PROJECT_DIR="$R" bash "$SCRIPT" --unlisted 2>/dev/null); RC=$?

has   "SC-1828 real code dependency in a CORE .sh is flagged"        "$OUT" "scripts/real-dep-helper.sh"
hasnt "SC-1829 whole-line comment in a CORE .sh is not a dependency" "$OUT" "scripts/prose-only-helper.sh"
hasnt "SC-1829 an INDENTED whole-line comment is a comment too"      "$OUT" "scripts/indented-prose-helper.sh"
has   "SC-1830 instructional prose in a CORE .md rule is flagged"    "$OUT" "scripts/rule-named-helper.sh"
hasnt "SC-1831 a hook command in settings.json is not a referrer"    "$OUT" "scripts/settings-named-helper.sh"
hasnt "SC-1833 a script nobody names is silent"                      "$OUT" "scripts/nobody-names-me.sh"
has   "SC-1836 a trailing mid-line # does not excuse the code line"  "$OUT" "scripts/trailing-comment-helper.sh"
hasnt "SC-1837 whole-line comment in a CORE .py is not a dependency" "$OUT" "scripts/py-prose-helper.sh"
same  "SC-1828 findings exit 0"                                      "$RC"  "0"
has   "SC-1828 the referrer is named, not just the finding"          "$OUT" "bash-write-detect-hook.sh"

# The empty half of the contract. core-owed-tick-guard-hook.sh branches on the exit code, so "no
# findings" has to be 1 and not 0-with-empty-stdout.
echo
echo "== the empty answer is exit 1, not exit 0"
R2="$TMP/quiet"; rm -rf "$R2"; mkdir -p "$R2/.git" "$R2/.claude/rules" "$R2/scripts"
printf 'sha=deadbeef\nsynced=2026-01-01T00:00:00Z\nsource=/dev/null\n# manifest\n' > "$R2/.claude/.template-sync"
: > "$R2/scripts/nobody-names-me.sh"
OUT2=$(CLAUDE_PROJECT_DIR="$R2" bash "$SCRIPT" --unlisted 2>/dev/null); RC2=$?
same "SC-1833 no findings exits 1" "$RC2" "1"
same "SC-1833 no findings print nothing" "$OUT2" ""

# ---------------------------------------------------------------------------------------------
# SC-1832 — the calibration corpus. 007ca measured the predicate against msroute at 3e1d386, the
# commit of the event it was built for: 4 findings, 0 false positives. The comment rule must not
# move that number.
#
# The corpus needs its era: those four scripts were PROMOTED to CORE_SCRIPTS afterwards — which is
# the fix having worked — so with today's list the tree is correctly silent and proves nothing. The
# arm rebuilds the era by removing that one family from CORE_SCRIPTS in a copy of the sync.
#
# SKIP, never a silent pass. A harness whose only regression arm vanishes with the tree and still
# prints clean is reporting about nothing.
# ---------------------------------------------------------------------------------------------
echo
echo "== SC-1832 — 007ca calibration corpus, recall unchanged"
CORPUS_REPO="${UNLISTED_CORPUS_REPO:-$HOME/repos/msroute}"
CORPUS_REF="${UNLISTED_CORPUS_REF:-3e1d386}"
if [ ! -d "$CORPUS_REPO/.git" ]; then
  skip "SC-1832 corpus replay" "no repository at $CORPUS_REPO (set UNLISTED_CORPUS_REPO)"
elif ! git -C "$CORPUS_REPO" rev-parse --verify -q "$CORPUS_REF^{commit}" >/dev/null 2>&1; then
  skip "SC-1832 corpus replay" "$CORPUS_REPO has no commit $CORPUS_REF"
else
  C="$TMP/corpus"; mkdir -p "$C"
  git -C "$CORPUS_REPO" archive "$CORPUS_REF" | tar -x -C "$C"
  mkdir -p "$C/.git"
  git -C "$CORPUS_REPO" show "$CORPUS_REF:.claude/.template-sync" > "$C/.claude/.template-sync" 2>/dev/null

  # Era-correct membership: the scenario-map family out of CORE_SCRIPTS, nothing else touched.
  ERA="$TMP/era-autosync.sh"
  python3 - "$SCRIPT" "$ERA" <<'PYEOF'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src, encoding='utf-8').read()
m = re.search(r'^CORE_SCRIPTS="(.*?)"$', s, re.S | re.M)
names = [n for n in m.group(1).split()
         if 'scenario-map' not in n]
open(dst, 'w', encoding='utf-8').write(s[:m.start(1)] + '\n'.join(names) + s[m.end(1):])
PYEOF
  COUT=$(CLAUDE_PROJECT_DIR="$C" bash "$ERA" --unlisted 2>/dev/null)
  CN=$(printf '%s\n' "$COUT" | grep -c 'scripts/')
  same "SC-1832 corpus still yields four findings" "$CN" "4"
  has  "SC-1832 scenario-map-layout.sh"      "$COUT" "scripts/scenario-map-layout.sh"
  has  "SC-1832 scenario-map-rows.sh"        "$COUT" "scripts/scenario-map-rows.sh"
  has  "SC-1832 test-scenario-map-index.py"  "$COUT" "scripts/test-scenario-map-index.py"
  has  "SC-1832 test-scenario-map-split.sh"  "$COUT" "scripts/test-scenario-map-split.sh"
  has  "SC-1832 the .md referrer survives the comment rule" "$COUT" "scenarios.md"
fi

# ---------------------------------------------------------------------------------------------
# SC-1834 — sabotage. Delete the comment rule in a copy and the tree from the five-way arm must
# start reporting prose again. Without this arm every silence above is equally consistent with a
# predicate that reports nothing at all.
# ---------------------------------------------------------------------------------------------
echo
echo "== SC-1834 — the comment rule has teeth"
SAB="$TMP/sabotaged-autosync.sh"
python3 - "$SCRIPT" "$SAB" <<'PYEOF'
import sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src, encoding='utf-8').read()
needle = '            if (f ~ /\\.(sh|py)$/ && body ~ /^[ \\t]*#/) next\n'
if needle not in s:
    sys.stderr.write('SABOTAGE-ANCHOR-MISSING\n')
    sys.exit(3)
open(dst, 'w', encoding='utf-8').write(s.replace(needle, '', 1))
PYEOF
if [ $? -ne 0 ]; then
  bad "SC-1834 sabotage anchor not found — the rule was reworded and this arm can no longer aim"
else
  SOUT=$(CLAUDE_PROJECT_DIR="$R" bash "$SAB" --unlisted 2>/dev/null)
  has "SC-1834 without the rule, .sh prose is reported again"     "$SOUT" "scripts/prose-only-helper.sh"
  has "SC-1834 without the rule, .py prose is reported again"     "$SOUT" "scripts/py-prose-helper.sh"
  has "SC-1834 the real dependency is unaffected by the sabotage" "$SOUT" "scripts/real-dep-helper.sh"
fi

echo
printf 'unlisted: %d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ] || exit 1
exit 0

#!/bin/bash
# Harness for scripts/validate-sync-sandbox-declarations.sh (spec 010, landed from consultpilot H7bm).
#
# A gate nobody has watched fail is a report, not a gate — this project's own lesson (spec 007bs,
# where four comments cited a traceability script that did not exist as having "reported 100% and
# exit 0"). So most of what is below is negative: fixtures written to be WRONG, each asserting that
# the gate names them and refuses. The passing cases only prove it is not refusing everything.
#
# The last section is different in kind. It asserts the PROPERTY the query-mode exemption rests on —
# that all four query modes return from template-autosync.sh above the project-root resolution —
# rather than trusting a list of exempt files. Move any of those branches below the resolution and
# this reddens, and the exemption stops applying on its own. That is the difference between an exemption
# and a grandfather list.
#
# Offline, in both halves and for different reasons. The gate half builds fixture scripts as text
# and never starts anything. The interlock half DOES run the real sync — there is no other way to
# check an interlock — but always against a local fixture template, so `refresh_local_template`
# returns at its origin-URL check and no run touches the network. That is not a performance note:
# `CLAUDE.md` says a test that hits the network is a broken test, and the first draft of this file
# hit GitHub twenty times per run (71 s, of which 66 s was fetching).
#
# Scenario ids deliberately absent: this file is CORE and ships into projects whose SC numbering
# is their own (row 012). Labels AC-NN match consultpilot H7bm spec.md for cross-reference.
#
# Run: bash scripts/test-validate-sync-sandbox-declarations.sh

set -u
cd "$(dirname "$0")/.." || exit 1
GATE="$PWD/scripts/validate-sync-sandbox-declarations.sh"
SYNC="$PWD/scripts/template-autosync.sh"
[ -f "$GATE" ] || { echo "FAIL: gate not found: $GATE"; exit 1; }
[ -f "$SYNC" ] || { echo "FAIL: template-autosync.sh not found"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
has()   { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 (missing '$3')"; printf '       got: %s\n' "$(printf '%s' "$2" | tr '\n' '|' | cut -c1-220)" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1 (unexpected '$3')" ;; *) ok "$1" ;; esac; }
same()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$3', got '$2')"; fi; }

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

# A fixture repo the gate can be pointed at: only scripts/ matters to it.
fixture() {  # fixture <name> -> echoes the root
  _r="$TMP/$1"; rm -rf "$_r"; mkdir -p "$_r/scripts"
  cp "$SYNC" "$_r/scripts/template-autosync.sh"
  printf '%s' "$_r"
}
gate() { SANDBOX_GATE_ROOT="$1" bash "$GATE" 2>&1; }
gate_rc() { SANDBOX_GATE_ROOT="$1" bash "$GATE" >/dev/null 2>&1; }

echo "== AC-01: the six real drivers in this repository pass =="
OUT=$(bash "$GATE"); RC=$?
same "the gate exits 0 on the repo as it stands"  "$RC" "0"
has  "…and counts six drivers"                    "$OUT" "6 driver(s) named and declared"
has  "…and four query-mode exemptions"           "$OUT" "4 exempt (query modes only)"
for d in test-template-autosync-stranded test-core-owed-tick-guard test-sync-count-honesty \
         test-template-autosync-owed test-template-autosync-eol test-template-autosync-unlisted; do
  has "  names $d as ok"                          "$OUT" "ok   scripts/$d.sh"
done

echo "== AC-02: SABOTAGE — a driver with neither half is named and refused =="
# The arm that makes this a gate. Without it, every assertion above is satisfied by a script that
# prints "ok" unconditionally.
R=$(fixture sabotage)
cat > "$R/scripts/test-rogue.sh" <<'EOS'
#!/bin/bash
SYNC="$PWD/scripts/template-autosync.sh"
run() { ( cd "$1" && bash "$SYNC" --force ); }
run /tmp/whatever
EOS
OUT=$(gate "$R"); RC=$?
same "the gate exits 1"                           "$RC" "1"
has  "names the file and the line"                "$OUT" "scripts/test-rogue.sh:3"
has  "names the first missing half"               "$OUT" "CLAUDE_PROJECT_DIR"
has  "names the second"                           "$OUT" "CLAUDE_TEMPLATE_SYNC_SANDBOX"
has  "counts it"                                  "$OUT" "1 violation(s)"
has  "and shows the offending text"               "$OUT" 'bash "$SYNC" --force'

echo "== AC-03: half is not enough — target named, sandbox undeclared =="
R=$(fixture halfway)
cat > "$R/scripts/test-halfway.sh" <<'EOS'
#!/bin/bash
SYNC="$PWD/scripts/template-autosync.sh"
run() { ( cd "$1" && CLAUDE_PROJECT_DIR="$1" bash "$SYNC" --force ); }
EOS
OUT=$(gate "$R"); RC=$?
same "still exits 1"                              "$RC" "1"
has  "…naming only the missing half"              "$OUT" "without CLAUDE_TEMPLATE_SYNC_SANDBOX"
hasnt "…and not the half that is present"         "$OUT" "without CLAUDE_PROJECT_DIR and"

echo "== AC-04: the other half alone is not enough either =="
R=$(fixture halfway2)
cat > "$R/scripts/test-halfway2.sh" <<'EOS'
#!/bin/bash
SYNC="$PWD/scripts/template-autosync.sh"
run() { ( cd "$1" && CLAUDE_TEMPLATE_SYNC_SANDBOX="$TMP" bash "$SYNC" --force ); }
EOS
gate_rc "$R"; same "exits 1 with only the declaration" "$?" "1"

echo "== AC-05: both halves, and it passes =="
R=$(fixture compliant)
cat > "$R/scripts/test-good.sh" <<'EOS'
#!/bin/bash
SYNC="$PWD/scripts/template-autosync.sh"
run() { ( cd "$1" && CLAUDE_PROJECT_DIR="$1" CLAUDE_TEMPLATE_SYNC_SANDBOX="$TMP" bash "$SYNC" --force ); }
EOS
OUT=$(gate "$R"); RC=$?
same "exits 0"                                    "$RC" "0"
has  "names it ok"                                "$OUT" "ok   scripts/test-good.sh"

echo "== AC-06: the halves may sit on a continuation line above the invocation =="
R=$(fixture continued)
cat > "$R/scripts/test-wrapped.sh" <<'EOS'
#!/bin/bash
SYNC="$PWD/scripts/template-autosync.sh"
run() { ( cd "$1" \
    && CLAUDE_PROJECT_DIR="$1" CLAUDE_TEMPLATE_SYNC_SANDBOX="$TMP" \
       bash "$SYNC" --force ); }
EOS
gate_rc "$R"; same "a two-line env prefix counts"  "$?" "0"

echo "== AC-07: an --is-core-only caller is exempt, and counted as exempt =="
R=$(fixture iscore)
cat > "$R/scripts/test-iscore-only.sh" <<'EOS'
#!/bin/bash
SYNC="$PWD/scripts/template-autosync.sh"
bash "$SYNC" --is-core scripts/whatever.sh >/dev/null 2>&1
EOS
OUT=$(gate "$R"); RC=$?
same "exits 0"                                    "$RC" "0"
has  "counted as exempt, not as a driver"         "$OUT" "1 exempt (query modes only)"
hasnt "…and not listed as a checked driver"       "$OUT" "ok   scripts/test-iscore-only.sh"

echo "== AC-07b: the other three query modes are exempt the same way =="
# The template has four modes that return above the project-root resolution; consultpilot's copy of
# this gate knew only --is-core and reported the other three as violations here.
R=$(fixture querymodes)
cat > "$R/scripts/test-query-modes.sh" <<'EOS'
#!/bin/bash
TA="$PWD/scripts/template-autosync.sh"
N=$(bash "$TA" --list-core-scripts 2>/dev/null | wc -l)
done < <(bash "$TA" --list-core-rules 2>/dev/null)
TPL=$(bash scripts/template-autosync.sh --template-dir 2>/dev/null)
EOS
OUT=$(gate "$R"); RC=$?
same "exits 0"                                    "$RC" "0"
has  "counted as one exempt file"                 "$OUT" "1 exempt (query modes only)"

echo "== AC-08: one --is-core call does NOT exempt a script that also drives =="
# The exemption is per SCRIPT but earned per INVOCATION: a file that asks --is-core somewhere and
# syncs somewhere else is a driver.
R=$(fixture mixed)
cat > "$R/scripts/test-mixed.sh" <<'EOS'
#!/bin/bash
SYNC="$PWD/scripts/template-autosync.sh"
bash "$SYNC" --is-core scripts/x.sh >/dev/null 2>&1
( cd /tmp/sbx && bash "$SYNC" --force )
EOS
OUT=$(gate "$R"); RC=$?
same "exits 1"                                    "$RC" "1"
has  "…naming the syncing line, not the --is-core one" "$OUT" "scripts/test-mixed.sh:4"
hasnt "…and does not report line 3"               "$OUT" "test-mixed.sh:3"

echo "== AC-09: a script that only NAMES the sync is not a driver =="
# The measured case is test-template-clone-refresh.sh: it sed-extracts one function and passes the
# target as an argument, so it never resolves a project root. The first census of this defect got
# that file wrong by looking for a variable name instead of an invocation.
R=$(fixture mentions)
cat > "$R/scripts/test-mentions.sh" <<'EOS'
#!/bin/bash
SCRIPT="$PWD/scripts/template-autosync.sh"
[ -f "$SCRIPT" ] || { echo "FAIL: template-autosync.sh not found at $SCRIPT"; exit 1; }
sed -n '/^refresh_local_template() {$/,/^}$/p' "$SCRIPT" > /tmp/harness
grep -c 'template-autosync.sh' "$SCRIPT"
EOS
OUT=$(gate "$R"); RC=$?
same "exits 0 — extraction is not invocation"     "$RC" "0"
hasnt "…and it is not reported"                   "$OUT" "test-mentions.sh"

echo "== AC-10: a filename ending in .sh does not read as an interpreter =="
# A project's run-gates.sh GATES array lists dozens of scripts/*.sh and its comments name the sync. Before the
# word-boundary fix the trailing `sh` of every filename matched `(bash|sh)` and the array read as
# fifty invocations.
R=$(fixture listing)
cat > "$R/scripts/test-listing.sh" <<'EOS'
#!/bin/bash
WANT="scripts/foo.sh scripts/template-autosync.sh scripts/bar.sh"
GATES=(
  scripts/test-sync-count-honesty.sh   # a comment mentioning scripts/template-autosync.sh
)
EOS
OUT=$(gate "$R"); RC=$?
same "exits 0"                                    "$RC" "0"
hasnt "a list of filenames is not a driver"       "$OUT" "test-listing.sh"

echo "== AC-11: the gate starts nothing (FR-016) =="
# If the gate executed what it reads, a fixture whose "sync" is a tripwire would leave a mark.
R=$(fixture offline)
printf '#!/bin/bash\ntouch "%s/TRIPPED"\n' "$TMP" > "$R/scripts/template-autosync.sh"
cat > "$R/scripts/test-driver.sh" <<'EOS'
#!/bin/bash
SYNC="$PWD/scripts/template-autosync.sh"
( cd "$1" && CLAUDE_PROJECT_DIR="$1" CLAUDE_TEMPLATE_SYNC_SANDBOX="$2" bash "$SYNC" )
EOS
gate "$R" >/dev/null 2>&1
[ -f "$TMP/TRIPPED" ] && bad "the gate executed a script it read" || ok "no fixture script was run"

echo "== AC-12 (FR-013b): the query-mode exemption's PROPERTY, not its filenames — --is-core =="
# Everything above trusts that --is-core cannot resolve a project root. This is where that is
# checked. Two independent readings, because either alone can rot:
IS_CORE_LINE=$(grep -n 'IS_CORE_REL' "$SYNC" | tail -1 | cut -d: -f1)
RESOLVE_LINE=$(grep -n 'DIR="${CLAUDE_PROJECT_DIR:-\$PWD}"' "$SYNC" | head -1 | cut -d: -f1)
if [ -n "$IS_CORE_LINE" ] && [ -n "$RESOLVE_LINE" ]; then
  if [ "$IS_CORE_LINE" -lt "$RESOLVE_LINE" ]; then
    ok "--is-core handling ends above the project-root resolution ($IS_CORE_LINE < $RESOLVE_LINE)"
  else
    bad "--is-core now reaches the project-root resolution ($IS_CORE_LINE >= $RESOLVE_LINE) — the exemption in validate-sync-sandbox-declarations.sh is no longer sound"
  fi
else
  bad "could not locate the --is-core block or the resolution line in template-autosync.sh"
fi
# And behaviourally: --is-core answers identically whether or not a project root exists to resolve.
OUTSIDE=$(mktemp -d)
# The subject must be NON-CORE, and that is the whole subtlety. --is-core answers from the path
# alone, so its answer is location-independent — which is exactly the property being asserted, and
# why the assertion is "identical", not "different".
#
# It only discriminates with a non-CORE subject. On a CORE path the answer is 0, and a run outside
# any git repo also exits 0 via the quiet skip, so that comparison is 0 against 0 and would still
# pass with the --is-core branch moved BELOW the project-root resolution. On README.md the answer
# is 1; move the branch down and the outside-repo run reaches the quiet skip and returns 0 instead,
# and this reddens. Same shape, one word changed, and only one of the two can fail.
A=$( cd "$OUTSIDE" && bash "$SYNC" --is-core README.md >/dev/null 2>&1; echo $? )
B=$( bash "$SYNC" --is-core README.md >/dev/null 2>&1; echo $? )
rm -rf "$OUTSIDE"
same "--is-core answers the same in and outside a repo (non-CORE subject)" "$A" "$B"

echo "== AC-12b: the same property for --list-core-scripts, --list-core-rules, --template-dir =="
for flag in MODE_TEMPLATE_DIR MODE_LIST_SCRIPTS MODE_LIST_RULES; do
  L=$(grep -nE "^if \[ \"[\$]$flag\"[[:space:]]+-eq 1 \]" "$SYNC" | head -1 | cut -d: -f1)
  if [ -n "$L" ] && [ -n "$RESOLVE_LINE" ] && [ "$L" -lt "$RESOLVE_LINE" ]; then
    ok "$flag is answered above the project-root resolution ($L < $RESOLVE_LINE)"
  else
    bad "$flag is not answered above the resolution (line '${L:-?}') — its exemption is no longer sound"
  fi
done
OUTSIDE=$(mktemp -d)
A=$( cd "$OUTSIDE" && bash "$SYNC" --list-core-scripts 2>/dev/null | wc -l | tr -d ' ' )
B=$( bash "$SYNC" --list-core-scripts 2>/dev/null | wc -l | tr -d ' ' )
rm -rf "$OUTSIDE"
same "--list-core-scripts answers the same in and outside a repo" "$A" "$B"

echo "== the interlock itself: template-autosync.sh's CLAUDE_TEMPLATE_SYNC_SANDBOX =="
# The gate above makes callers declare. This section checks that declaring achieves anything —
# they are two halves of one mechanism and neither is worth much alone. Every case below runs the
# REAL sync, inside a sandbox it declares.
ILOCK="$TMP/ilock"; mkdir -p "$ILOCK"
# The template every interlock case syncs against. Local, so nothing resolves a remote.
FT="$ILOCK/template"; mkdir -p "$FT/scripts" "$FT/.claude/rules"
cp "$SYNC" "$FT/scripts/"; echo prompt > "$FT/scripts/sync-prompt.md"
printf 'rule v1\n' > "$FT/.claude/rules/demo-rule.md"
mkrepo() {  # mkrepo <dir>
  mkdir -p "$1/.claude" "$1/scripts"; cp "$SYNC" "$1/scripts/"; echo '{}' > "$1/package.json"
  git -C "$1" init -q -b main
  git -C "$1" config user.email a@a; git -C "$1" config user.name A
  git -C "$1" add -A >/dev/null 2>&1; git -C "$1" commit -qm init >/dev/null 2>&1
}
SBX="$ILOCK/sandbox"; mkdir -p "$SBX"
IN="$SBX/proj"; OUT_REPO="$ILOCK/outside"; mkrepo "$IN"; mkrepo "$OUT_REPO"
run_sync() {  # run_sync <sandbox> <project> [args...]
  _s="$1"; _p="$2"; shift 2
  ( cd "$_p" && CLAUDE_PROJECT_DIR="$_p" CLAUDE_TEMPLATE_SYNC_SANDBOX="$_s" \
      CLAUDE_TEMPLATE_DIR="$FT" bash scripts/template-autosync.sh "$@" 2>&1 )
}
rc_sync() { run_sync "$@" >/dev/null 2>&1; }
# The undeclared path — no sandbox variable at all, which is what every production run does. Two
# cases need it and neither can go through run_sync, which always sets one.
sync_undeclared() {  # sync_undeclared <project> [args...]
  _p="$1"; shift
  ( cd "$_p" && CLAUDE_PROJECT_DIR="$_p" CLAUDE_TEMPLATE_DIR="$FT" \
      bash scripts/template-autosync.sh "$@" 2>&1 )
}

echo "-- AC-13: a root inside the declared sandbox is allowed through"
rc_sync "$SBX" "$IN" --check; same "exits 0"      "$?" "0"

echo "-- AC-14: a root OUTSIDE it refuses, before writing, naming both paths"
BEFORE_FILES=$(git -C "$OUT_REPO" status --porcelain | wc -l | tr -d ' ')
BEFORE_LOG=$(git -C "$OUT_REPO" log --oneline | wc -l | tr -d ' ')
O=$(run_sync "$SBX" "$OUT_REPO"); RC=$?
same "exits 1"                                    "$RC" "1"
has  "says nothing was written"                   "$O" "Nothing was written"
has  "names the declared sandbox"                 "$O" "declared sandbox:"
has  "names the resolved project"                 "$O" "resolved project:"
same "the outside repo gained no dirty file"      "$(git -C "$OUT_REPO" status --porcelain | wc -l | tr -d ' ')" "$BEFORE_FILES"
same "…and no commit"                             "$(git -C "$OUT_REPO" log --oneline | wc -l | tr -d ' ')" "$BEFORE_LOG"
[ -f "$OUT_REPO/.claude/.template-sync" ] && bad "…and no stamp was written" || ok "…and no stamp was written"

echo "-- AC-15: it refuses under --quiet too"
# A refusal nobody sees is the warning that went unread on 2026-08-30.
O=$(run_sync "$SBX" "$OUT_REPO" --quiet)
has  "--quiet does not silence the refusal"       "$O" "[refused]"

echo "-- AC-16: a declaration that is SET BUT EMPTY refuses (spec 010 — consultpilot read it as undeclared)"
# An empty prefix contains every path, so it can never mean "/". It cannot mean "undeclared" either:
# a driver writing CLAUDE_TEMPLATE_SYNC_SANDBOX="$TMP" whose mktemp failed would pass the gate and run
# with no interlock. Refusing is the only reading that fails in the safe direction.
BEFORE_FILES=$(git -C "$OUT_REPO" status --porcelain | wc -l | tr -d ' ')
O=$(run_sync "" "$OUT_REPO" --force --no-commit); RC=$?
same "set-but-empty exits 1"                      "$RC" "1"
has  "…and says it is empty"                      "$O" "set but empty"
same "…and nothing was written"                   "$(git -C "$OUT_REPO" status --porcelain | wc -l | tr -d ' ')" "$BEFORE_FILES"

echo "-- AC-17: a declaration naming nothing is a refusal, not a pass"
O=$(run_sync "$ILOCK/does-not-exist" "$IN" --check); RC=$?
same "exits 1"                                    "$RC" "1"
has  "…and says which declaration"                "$O" "names no existing directory"

echo "-- AC-18: a declaration that is a FILE, not a directory"
printf 'x\n' > "$ILOCK/a-file"
rc_sync "$ILOCK/a-file" "$IN" --check; same "exits 1"  "$?" "1"

echo "-- AC-19: segments, not characters — /sandbox-evil is not inside /sandbox"
EVIL="$ILOCK/sandbox-evil"; mkdir -p "$EVIL"; mkrepo "$EVIL/proj"
rc_sync "$SBX" "$EVIL/proj" --check
same "the sibling with a shared prefix is refused" "$?" "1"

echo "-- AC-20: physical paths — macOS /var vs /private/var"
# mktemp -d hands out /var/folders/…; `pwd -P` reports /private/var/folders/…. A string comparison
# refuses every legitimate sandbox run on this platform, which is the difference between a guard
# and an obstacle.
MT=$(mktemp -d); mkrepo "$MT/proj"
rc_sync "$MT" "$MT/proj" --check
same "a symlinked sandbox path is accepted"       "$?" "0"
DECL_PHYS=$(cd "$MT" && pwd -P)
if [ "$MT" != "$DECL_PHYS" ]; then
  ok "…and the two spellings really did differ ($MT vs $DECL_PHYS)"
else
  ok "…(this platform does not symlink TMPDIR; the case is a no-op here)"
fi
rm -rf "$MT"

echo "-- AC-21: trailing slashes and .. segments in the declaration"
rc_sync "$SBX/" "$IN" --check;               same "trailing slash accepted"    "$?" "0"
rc_sync "$SBX/proj/.." "$IN" --check;        same "a .. segment resolves"      "$?" "0"

echo "-- AC-22: a path with a space and a non-ASCII name"
ODD="$ILOCK/en katalog med ÅÄÖ"; mkdir -p "$ODD"; mkrepo "$ODD/proj"
rc_sync "$ODD" "$ODD/proj" --check;          same "spaces and diacritics survive" "$?" "0"
rc_sync "$SBX" "$ODD/proj" --check;          same "…and are still refused when outside" "$?" "1"

echo "-- AC-23: the undeclared run is untouched (FR-006)"
# The load-bearing non-event. Every production run of this script takes this path.
A=$(sync_undeclared "$IN" --check)
B=$(run_sync "$SBX" "$IN" --check)
same "declared and undeclared produce identical output" "$A" "$B"
hasnt "…and the undeclared run says nothing new" "$A" "[refused]"

echo "-- AC-24: --is-core costs nothing extra with a declaration set (FR-013b, behavioural)"
sync_undeclared "$IN" --is-core scripts/x.sh >/dev/null 2>&1; C1=$?
rc_sync "$SBX" "$IN" --is-core scripts/x.sh; C2=$?
same "--is-core answers the same either way"      "$C1" "$C2"

echo "-- AC-25: outside a git repository the quiet skip stays quiet"
# FR-008. The interlock must not turn an existing silent exit 0 into a hard failure: the
# SessionStart hook runs this script in whatever directory a session opens in, and most of them are
# not projects.
NOGIT="$ILOCK/not-a-repo"; mkdir -p "$NOGIT"
O=$( cd "$NOGIT" && CLAUDE_PROJECT_DIR="$NOGIT" CLAUDE_TEMPLATE_SYNC_SANDBOX="$ILOCK" \
       CLAUDE_TEMPLATE_DIR="$FT" bash "$SYNC" --check 2>&1 ); RC=$?
same "still exits 0"                              "$RC" "0"
has  "…with the pre-existing message"             "$O" "not inside a git repository"
hasnt "…and not a refusal"                        "$O" "[refused]"

echo "== the adversarial review's findings, as permanent tests =="
# Every case below reproduced against the first implementation of this row and is now a regression
# test. They are grouped so it stays obvious that they came from a review pass, not from design:
# the design missed them, and the only reason they are not still there is that something adversarial
# looked.

echo "-- AC-26: a sandbox declared as / is refused"
# The single line that, alone, reopened the 2026-08-30 incident. `_within` had an explicit `/`
# branch written as a formatting concern ("never build //"), and nothing had asked what declaring
# the root MEANT: every path is inside it, so the interlock accepted and the run proceeded to
# write, commit and push. AC-16 covered the EMPTY declaration and read as though it covered this.
O=$(run_sync / "$OUT_REPO" --check); RC=$?
same "exits 1"                                    "$RC" "1"
has  "…and says why the root is not a sandbox"    "$O" "declares nothing and protects nothing"

echo "-- AC-31: an ambient CDPATH cannot steer the check away from the write (adversarial review, 010)"
# A relative project name plus CDPATH pointing into the sandbox: before the fix `cd` followed CDPATH,
# printed the decoy, and the check passed while the walk wrote to the real relative directory.
# Physical paths on purpose: on macOS the unfixed cd echoes the /var spelling while the sandbox
# resolves to /private/var, and that mismatch refused by accident — the arm passed against the bug.
CD_T="$(cd "$ILOCK" && pwd -P)/cdpath"; mkdir -p "$CD_T/sbx/proj" "$CD_T/real"; mkrepo "$CD_T/real/proj"
mkdir -p "$CD_T/sbx/proj/.git"
O=$( cd "$CD_T/real" && CDPATH="$CD_T/sbx" CLAUDE_PROJECT_DIR=proj CLAUDE_TEMPLATE_SYNC_SANDBOX="$CD_T/sbx" \
       CLAUDE_TEMPLATE_DIR="$FT" bash "$SYNC" --force --no-commit 2>&1 ); RC=$?
same "exits 1 — the real relative project is outside the sandbox" "$RC" "1"
same "…and the real project is untouched" "$(git -C "$CD_T/real/proj" status --porcelain | wc -l | tr -d ' ')" "0"

echo "-- AC-32: an inherited GIT_DIR cannot redirect a declared run's commit (adversarial review, 010)"
# Git exports GIT_DIR / GIT_INDEX_FILE to its hooks and both beat `git -C`. The root check passes
# (the project IS in the sandbox); only the unset makes the commit land there.
GD_T="$ILOCK/gitdir"; mkdir -p "$GD_T"; mkrepo "$GD_T/victim"; mkrepo "$SBX/gd-proj"
V_HEAD=$(git -C "$GD_T/victim" rev-parse HEAD)
GIT_DIR="$GD_T/victim/.git" GIT_INDEX_FILE="$GD_T/victim/.git/index" rc_sync "$SBX" "$SBX/gd-proj" --force
same "the victim repository's HEAD did not move"  "$(git -C "$GD_T/victim" rev-parse HEAD)" "$V_HEAD"
same "…and its tree is clean"                     "$(git -C "$GD_T/victim" status --porcelain | wc -l | tr -d ' ')" "0"
[ -f "$SBX/gd-proj/.claude/.template-sync" ] && ok "…and the sync landed in the sandboxed project" \
                                             || bad "the sandboxed project got no stamp"

echo "-- AC-27: the gate refuses a driver that declares / "
# Presence of the assignment was all the gate checked. A driver could therefore be certified
# compliant by the very tool built to prevent the bypass it was performing.
R=$(fixture rootdecl)
cat > "$R/scripts/test-rootdecl.sh" <<'EOS'
#!/bin/bash
SYNC="$PWD/scripts/template-autosync.sh"
run() { ( cd "$1" && CLAUDE_PROJECT_DIR="$1" CLAUDE_TEMPLATE_SYNC_SANDBOX=/ bash "$SYNC" --force ); }
EOS
O=$(gate "$R"); RC=$?
same "exits 1"                                    "$RC" "1"
has  "…naming the root declaration"               "$O" "filesystem root as its sandbox"

echo "-- AC-28: direct execution is an invocation, with or without an interpreter"
# template-autosync.sh carries a #! line, so `exec "$SYNC"` runs it. The first detector required a
# literal bash/sh token and was blind to this: the file was not reported as a driver, nor as
# exempt — simply absent, which is the worst of the three.
R=$(fixture execform)
cat > "$R/scripts/test-execform.sh" <<'EOS'
#!/bin/bash
SYNC="$PWD/scripts/template-autosync.sh"
( cd /some/other/repo && exec "$SYNC" --force )
EOS
O=$(gate "$R"); RC=$?
same "exits 1"                                    "$RC" "1"
has  "…and names the file and line"               "$O" "scripts/test-execform.sh:3"

echo "-- AC-29: a backtick is a command-word anchor too"
R=$(fixture backtick)
cat > "$R/scripts/test-backtick.sh" <<'EOS'
#!/bin/bash
SYNC="$PWD/scripts/template-autosync.sh"
OUT=`bash "$SYNC" --force`
EOS
O=$(gate "$R"); RC=$?
same "exits 1"                                    "$RC" "1"
has  "…and names the file and line"               "$O" "scripts/test-backtick.sh:3"

echo "-- AC-30: prose is still not an invocation"
# The two false positives the tightened detector had to shed, kept as fixtures so a future
# broadening of the anchors reintroduces them loudly. Both are real lines from this repository.
R=$(fixture prose)
cat > "$R/scripts/test-prose.sh" <<'EOS'
#!/bin/bash
MSG="STACK MARKER MISSING.

template-autosync.sh reads that marker to decide which testing docs to install."
echo "  (scripts/template-autosync.sh), is shared verbatim with every project that syncs it"
EOS
O=$(gate "$R"); RC=$?
same "exits 0"                                    "$RC" "0"
hasnt "a message string is not a driver"          "$O" "test-prose.sh"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]

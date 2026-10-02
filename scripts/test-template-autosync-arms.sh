#!/bin/bash
. "$(dirname -- "$0")/self-test-env.sh" || exit 1
# Surgical arms for the mutants H1 found alive in scripts/template-autosync.sh (spec 078).
#
# H1 ran a sampled operator-mutation pass over the most-changed CORE script and every suite that
# drives it killed 2 of 12. Spec 078 re-drew the sample (the six named sites plus six new ones) and
# measured 4 of 12. Two of the eight survivors are equivalent and have no arm (see spec.md). Each
# arm below exists for exactly one of the other six, and `--sabotage` proves it: it applies that
# mutant to a copy of the script, runs the arm against the copy, and expects red.
#
#   M01  template-mode --unlisted: the `[ -f "$_f" ] || continue` glob guard
#   M08  local_record: `[ -f "$LOCAL_RECORD" ] || return 1`
#   M09  --accept-local CORE refusal: the `[ "$_first" -eq 1 ]` prefix line
#   M10  --accept-local CORE refusal: `exit 1`
#   M11  --accept-local, template does not ship the path: `exit 1`
#   M12  the final core-hooks re-merge: `&& python3 -m json.tool` validity check
#
# Spec 085 (085-AC-3) re-measured the survivors with scripts/run-mutation-gate.sh and armed these:
#
#   M13  --template-dir with no local clone anywhere: `exit 1`
#   M15  fold_helper_writes: `[ "$_claimed" -ne "$_n" ]` drift check
#   M16  [held] gate: `[ -n "$SYNC_COMMIT" ]`
#   M17  [held] gate: the `||` between the two arms
#   M18  [held] gate: `[ "$IN_PROGRESS_ARM" -eq 1 ]`
#   M19  [held] cap: `[ "$N_HELD" -gt "$NAME_LIMIT" ]`
#
# Spec 092 (R4) armed the survivors the --lines re-measure left in template-autosync.sh, named by line:
#
#   M20-M22  L938   --owed in the template: `[ "$MODE_OWED" -eq 1 ] && exit 2`
#   M23-M24  L2002  matches_template_history: `[ "$OLD" = "$CUR" ] && return 0`
#   M25-M26  L2310  exec-bit-only difference: `[ "$MODE_CHECK" -eq 1 ] || mirror_exec_bit`
#   M27-M28  L2533  orphan the developer deleted: `[ -f "$PROJECT_ROOT/$_m" ] || continue`
#   M29-M31  L2613  [check] header: `[ -n "$STAMP_SHA" ] && echo … || echo "never synced"`
#   M32-M33  L3107  carried `# wrote` lines: `[ -n "$_cp" ] || continue`
#   M34      L3526  commit guard: `[ -n "$MSG" ] && [ -n "$COMMIT_PATHS" ]`
#   M35      L3764  [verify] hint: `[ -n "$VERIFY_CMD" ]`
#
# M14 (`[ -n "$_cands" ] || exit 0` in unlisted_core_shaped's project mode) has no arm: it is the
# exit status of a subshell whose stdout is empty either way, and every caller reads only the
# stdout. The line carries `# mutant-equivalent:`.
#
# Run:  bash scripts/test-template-autosync-arms.sh              # the arms against the real script
#       bash scripts/test-template-autosync-arms.sh --sabotage   # every arm against its mutant
# ARMS_TEST_SCRIPT selects the script under test (the sabotage mode sets it per mutant).

set -u
cd "$(dirname "$0")/.." || exit 1
SCRIPT="${ARMS_TEST_SCRIPT:-$PWD/scripts/template-autosync.sh}"
[ -f "$SCRIPT" ] || { echo "FAIL: template-autosync.sh not found at $SCRIPT"; exit 1; }
. "$PWD/scripts/drive-sync.sh"                 # the only way to the sync (spec 011)

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
has()   { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 (missing '$3' in: $(printf '%s' "$2" | tr '\n' '|'))" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1 (unexpected '$3' in: $(printf '%s' "$2" | tr '\n' '|'))" ;; *) ok "$1" ;; esac; }
same()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$3', got '$2')"; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------- sabotage mode
# One record per arm, fields separated by @@ because the texts contain `|`: id, the exact text to
# mutate (it must occur exactly once in the script, or the anchor is stale and the mode fails
# rather than skipping), the replacement, and the arm function that has to go red. An arm that stays green against its mutant is theatre.
MUTANTS='M01@@        [ -f "$_f" ] || continue@@        :@@arm_unlisted_glob
M08@@  [ -f "$LOCAL_RECORD" ] || return 1@@  [ -f "$LOCAL_RECORD" ] || return 0@@arm_no_record_is_not_stale
M09@@        if [ "$_first" -eq 1 ]; then warn "[accept-local] refused: $_l"; _first=0@@        if [ "$_first" -ne 1 ]; then warn "[accept-local] refused: $_l"; _first=0@@arm_accept_core
M10@@      done; }
      exit 1@@      done; }
      exit 0@@arm_accept_core
M11@@      warn "               differ from — this sync never looks at that path."
      exit 1@@      warn "               differ from — this sync never looks at that path."
      exit 0@@arm_accept_unshipped
M12@@     && python3 -m json.tool "$PROJECT_ROOT/.claude/settings.json" >/dev/null 2>&1; then
    cmp -s@@     || python3 -m json.tool "$PROJECT_ROOT/.claude/settings.json" >/dev/null 2>&1; then
    cmp -s@@arm_settings_stay_valid
M13@@CANDIDATES
  exit 1
fi@@CANDIDATES
  exit 0
fi@@arm_template_dir_none
M15@@    if [ "$_claimed" -ne "$_n" ]; then@@    if [ "$_claimed" -eq "$_n" ]; then@@arm_helper_count_drift
M16@@if [ -n "$SYNC_COMMIT" ] || [ "$IN_PROGRESS_ARM" -eq 1 ]; then@@if [ -z "$SYNC_COMMIT" ] || [ "$IN_PROGRESS_ARM" -eq 1 ]; then@@arm_held_gate
M17@@if [ -n "$SYNC_COMMIT" ] || [ "$IN_PROGRESS_ARM" -eq 1 ]; then@@if [ -n "$SYNC_COMMIT" ] && [ "$IN_PROGRESS_ARM" -eq 1 ]; then@@arm_held_gate
M18@@if [ -n "$SYNC_COMMIT" ] || [ "$IN_PROGRESS_ARM" -eq 1 ]; then@@if [ -n "$SYNC_COMMIT" ] || [ "$IN_PROGRESS_ARM" -ne 1 ]; then@@arm_held_gate
M19@@    if [ "$N_HELD" -gt "$NAME_LIMIT" ]; then@@    if [ "$N_HELD" -le "$NAME_LIMIT" ]; then@@arm_held_cap
M20@@  [ "$MODE_OWED" -eq 1 ] && exit 2@@  [ "$MODE_OWED" -ne 1 ] && exit 2@@arm_l938_owed_in_template
M21@@  [ "$MODE_OWED" -eq 1 ] && exit 2@@  [ "$MODE_OWED" -eq 1 ] || exit 2@@arm_l938_owed_in_template
M22@@  [ "$MODE_OWED" -eq 1 ] && exit 2@@  [ "$MODE_OWED" -eq 1 ] && exit 0@@arm_l938_owed_in_template
M23@@    [ "$OLD" = "$CUR" ] && return 0@@    [ "$OLD" = "$CUR" ] || return 0@@arm_l2002_template_history
M24@@    [ "$OLD" = "$CUR" ] && return 0@@    [ "$OLD" = "$CUR" ] && return 1@@arm_l2002_template_history
M25@@        [ "$MODE_CHECK" -eq 1 ] || mirror_exec_bit "$SRC" "$DEST"@@        [ "$MODE_CHECK" -ne 1 ] || mirror_exec_bit "$SRC" "$DEST"@@arm_l2310_exec_bit
M26@@        [ "$MODE_CHECK" -eq 1 ] || mirror_exec_bit "$SRC" "$DEST"@@        [ "$MODE_CHECK" -eq 1 ] && mirror_exec_bit "$SRC" "$DEST"@@arm_l2310_exec_bit
M27@@    [ -f "$PROJECT_ROOT/$_m" ] || continue@@    [ -f "$PROJECT_ROOT/$_m" ] && continue@@arm_l2533_deleted_orphan
M28@@    [ -f "$PROJECT_ROOT/$_m" ] || continue@@    [ ! -f "$PROJECT_ROOT/$_m" ] || continue@@arm_l2533_deleted_orphan
M29@@vs project $([ -n "$STAMP_SHA" ] && echo "$STAMP_SHA" || echo "never synced")@@vs project $([ -z "$STAMP_SHA" ] && echo "$STAMP_SHA" || echo "never synced")@@arm_l2613_check_header
M30@@vs project $([ -n "$STAMP_SHA" ] && echo "$STAMP_SHA" || echo "never synced")@@vs project $([ -n "$STAMP_SHA" ] || echo "$STAMP_SHA" || echo "never synced")@@arm_l2613_check_header
M31@@vs project $([ -n "$STAMP_SHA" ] && echo "$STAMP_SHA" || echo "never synced")@@vs project $([ -n "$STAMP_SHA" ] && echo "$STAMP_SHA" && echo "never synced")@@arm_l2613_check_header
M32@@    [ -n "$_cp" ] || continue@@    [ -z "$_cp" ] || continue@@arm_l3107_wrote_carry
M33@@    [ -n "$_cp" ] || continue@@    [ -n "$_cp" ] && continue@@arm_l3107_wrote_carry
M34@@    if [ -n "$MSG" ] && [ -n "$COMMIT_PATHS" ] \@@    if [ -n "$MSG" ] || [ -n "$COMMIT_PATHS" ] \@@arm_l3526_nothing_to_commit
M35@@  if [ -n "$VERIFY_CMD" ]; then@@  if [ -z "$VERIFY_CMD" ]; then@@arm_l3764_verify_hint'

if [ "${1:-}" = "--sabotage" ]; then
  RED=0; STILL_GREEN=""; STALE_ANCHOR=""
  # A record starts at an `Mnn@@` line; its anchor and replacement may span two lines, so the list
  # is parsed in Python rather than with `read`.
  MUTANTS="$MUTANTS" python3 - "$SCRIPT" "$TMP" <<'PYEOF' > "$TMP/plan" || { echo "FAIL: sabotage plan could not be built"; exit 1; }
import os, re, sys
src, tmp = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()
raw = os.environ["MUTANTS"]
records = re.split(r'\n(?=M\d\d@@)', raw)
for rec in records:
    mid, old, new, arm = rec.split("@@")
    n = text.count(old)
    if n != 1:
        print(f"{mid} STALE {arm} {n}")
        continue
    out = f"{tmp}/{mid}.sh"
    open(out, "w", encoding="utf-8").write(text.replace(old, new, 1))
    print(f"{mid} OK {arm} {out}")
PYEOF
  while read -r mid state arm path; do
    if [ "$state" = STALE ]; then
      STALE_ANCHOR="$STALE_ANCHOR $mid(matches:$path)"; continue
    fi
    if ARMS_TEST_SCRIPT="$path" ARMS_ONLY="$arm" bash "$0" >"$TMP/$mid.out" 2>&1; then
      STILL_GREEN="$STILL_GREEN $mid($arm)"
    else
      RED=$((RED+1)); printf '  ok   %s kills %s\n' "$arm" "$mid"
      grep '^  FAIL' "$TMP/$mid.out" | sed 's/^/         /'
    fi
  done < "$TMP/plan"
  [ -z "$STALE_ANCHOR" ] || echo "  FAIL stale mutant anchor(s) — the script moved under them:$STALE_ANCHOR"
  [ -z "$STILL_GREEN" ]  || echo "  FAIL arm(s) still green against their mutant:$STILL_GREEN"
  echo
  echo "sabotage: $RED killed"
  [ -z "$STALE_ANCHOR$STILL_GREEN" ]
  exit $?
fi

# ---------------------------------------------------------------------------- fixtures
# A template clone and a project, both git repositories. The template ships one CORE script
# (the sync itself), one ordinary rule and a project-owned doc; the project starts empty.
build() {
  R="$TMP/$1"; rm -rf "$R"; mkdir -p "$R"
  T="$R/template"; P="$R/project"
  mkdir -p "$T/scripts" "$T/.claude/rules" "$T/.claude/docs"
  cp "$SCRIPT" "$T/scripts/template-autosync.sh"
  echo prompt > "$T/scripts/sync-prompt.md"
  printf 'rule v1\n' > "$T/.claude/rules/demo-rule.md"
  git -C "$T" init -q -b main
  git -C "$T" config user.email t@t; git -C "$T" config user.name T

  mkdir -p "$P/.claude/rules" "$P/scripts"
  echo '{"name":"fake"}' > "$P/package.json"
  cp "$SCRIPT" "$P/scripts/template-autosync.sh"
  git -C "$P" init -q -b main
  git -C "$P" config user.email p@p; git -C "$P" config user.name P
}
commit_both() {
  git -C "$T" add -A; git -C "$T" commit -qm template
  git -C "$P" add -A; git -C "$P" commit -qm project
}

sync() { CLAUDE_TEMPLATE_DIR="$T" DRIVE_SYNC_SCRIPT="$SCRIPT" drive_sync "$P" "$TMP" "$@"; }

want() { [ -z "${ARMS_ONLY:-}" ] || [ "$ARMS_ONLY" = "$1" ]; }

# ---------------------------------------------------------------------------- M01
# In the template, `--unlisted` walks scripts/*.sh and scripts/*.py. A glob that matches nothing
# stays literal, and without the -f guard the literal pattern is reported as a script that ships
# to no project. The template has .py files today, which is why no suite ever saw it.
# Spec 091 R1: the template is recognised by its history. template_history <repo> borrows this clone's
# objects and moves the repo's branch onto the template's HEAD; 1 when this clone is not the template.
template_history() {
  _src=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null) || return 1
  git -C "$_src" cat-file -e d3cf8238372ce7a37d5d66b115cbcbf9d57bb2b9^{commit} 2>/dev/null || return 1
  printf '%s\n' "$(git -C "$_src" rev-parse --path-format=absolute --git-common-dir)/objects" >> "$1/.git/objects/info/alternates"
  git -C "$1" update-ref HEAD "$(git -C "$_src" rev-parse HEAD)"
}
arm_unlisted_glob() {
  echo "== M01 — template --unlisted: an empty glob is not a script"
  R="$TMP/m01"; rm -rf "$R"; mkdir -p "$R/scripts" "$R/.claude"
  git -C "$R" init -q -b main
  git -C "$R" remote add origin https://github.com/johanolofsson72/Claude.git
  template_history "$R" || { ok "M01 skipped: this clone is not the template, so template mode cannot be built"; return 0; }
  cp "$(dirname "$SCRIPT")/template-identity.sh" "$TMP/" 2>/dev/null
  [ -f "$(dirname "$SCRIPT")/template-identity.sh" ] || cp "$PWD/scripts/template-identity.sh" "$(dirname "$SCRIPT")/"
  : > "$R/scripts/not-in-core.sh"
  OUT=$(DRIVE_SYNC_SCRIPT="$SCRIPT" drive_sync "$R" "$TMP" --unlisted 2>&1)
  has   "M01 template mode is engaged (a real unlisted .sh is named)" "$OUT" "scripts/not-in-core.sh	absent from CORE_SCRIPTS"
  hasnt "M01 no literal scripts/*.py when there is no .py"            "$OUT" 'scripts/*.py'
}

# ---------------------------------------------------------------------------- M08
# local_record answers "is there an accepted difference for this path". With no .sync-local at
# all the answer is no. If it said yes, every file already identical to the template would be
# reported as a stale record the developer should drop from a file that does not exist.
arm_no_record_is_not_stale() {
  echo "== M08 — no .sync-local means no stale records"
  build m08
  cp "$T/.claude/rules/demo-rule.md" "$P/.claude/rules/demo-rule.md"   # identical before any sync
  commit_both
  OUT=$(sync --check 2>&1)
  has   "M08 the check ran"                              "$OUT" "[check] would update:"
  hasnt "M08 an identical file is not a stale record"    "$OUT" "stale:"

  # The control: a real record for an identical file IS stale, so the arm is not blind to the bucket.
  SHA=$(if command -v sha256sum >/dev/null 2>&1; then sha256sum "$P/.claude/rules/demo-rule.md"
        else shasum -a 256 "$P/.claude/rules/demo-rule.md"; fi | cut -d' ' -f1)
  printf '%s  %s  .claude/rules/demo-rule.md\n' "$SHA" "$SHA" > "$P/.claude/.sync-local"
  OUT=$(sync --check 2>&1)
  has   "M08 control: a record for an identical file is stale" "$OUT" "stale:1"
}

# ---------------------------------------------------------------------------- M09 / M10
# A CORE file cannot be accepted as a local difference: the sync would overwrite it anyway. The
# refusal has to fail (exit 1) and has to read as a refusal from its first line.
arm_accept_core() {
  echo "== M09/M10 — --accept-local refuses a CORE file"
  build m09
  commit_both
  sync --quiet >/dev/null 2>&1
  printf '# local edit\n' >> "$P/scripts/template-autosync.sh"
  ERR=$(sync --accept-local scripts/template-autosync.sh 2>&1 >/dev/null); RC=$?
  same "M10 refusing a CORE file exits 1"                   "$RC" "1"
  same "M09 the first line carries the refusal prefix"      "$(printf '%s\n' "$ERR" | head -1 | cut -c1-23)" "[accept-local] refused:"
  hasnt "M09 no later line repeats the prefix"              "$(printf '%s\n' "$ERR" | sed 1d)" "[accept-local] refused:"
  [ -f "$P/.claude/.sync-local" ] && bad "M10 a refused path wrote no record" || ok "M10 a refused path wrote no record"
}

# ---------------------------------------------------------------------------- M11
# A path the template does not ship has nothing to differ from; accepting it must fail too.
arm_accept_unshipped() {
  echo "== M11 — --accept-local refuses a path the template does not ship"
  build m11
  printf 'mine\n' > "$P/.claude/rules/project-only.md"
  commit_both
  sync --quiet >/dev/null 2>&1
  ERR=$(sync --accept-local .claude/rules/project-only.md 2>&1 >/dev/null); RC=$?
  same "M11 an unshipped path exits 1"      "$RC" "1"
  has  "M11 and says why"                   "$ERR" "the template does not ship '.claude/rules/project-only.md'"

  # The control: a shipped, non-CORE, differing path is accepted, so exit 1 is not the only answer.
  printf 'rule, locally\n' > "$P/.claude/rules/demo-rule.md"
  sync --accept-local .claude/rules/demo-rule.md >/dev/null 2>&1; RC=$?
  same "M11 control: a shipped differing rule is accepted" "$RC" "0"
}

# ---------------------------------------------------------------------------- M12
# The last core-hooks re-merge keeps the helper's output only if settings.json still parses. A
# helper that exits 0 after writing broken JSON must be rolled back, or every hook in the project
# stops loading at the next session start.
arm_settings_stay_valid() {
  echo "== M12 — a merge that breaks settings.json is rolled back"
  build m12
  printf '{"hooks":{}}\n' > "$T/.claude/settings.json"
  cat > "$T/scripts/sync-core-hooks.py" <<'EOF'
import sys
open(".claude/settings.json", "w").write("{ broken")
sys.exit(0)
EOF
  printf '{"hooks":{}}\n' > "$P/.claude/settings.json"
  commit_both
  sync --quiet >/dev/null 2>&1
  if python3 -m json.tool "$P/.claude/settings.json" >/dev/null 2>&1; then
    ok "M12 settings.json still parses after a helper wrote broken JSON"
  else
    bad "M12 settings.json still parses after a helper wrote broken JSON (got: $(head -c 40 "$P/.claude/settings.json"))"
  fi
}

# ---------------------------------------------------------------------------- M13
# 085-AC-3. `--template-dir` answers "where is a local template clone" and exits 1 when there is
# none, which is how the wizard and /project-update learn to fall back to the tarball. An exit 0
# with an empty stdout would send them to an empty path. HOME is moved so the real ~/repos/Claude on
# this machine is not a candidate.
arm_template_dir_none() {
  echo "== M13 — --template-dir with no clone anywhere exits 1 (085-AC-3)"
  build m13
  mkdir -p "$R/home"
  OUT=$(HOME="$R/home" CLAUDE_TEMPLATE_DIR="$R/nowhere" DRIVE_SYNC_SCRIPT="$SCRIPT" \
        drive_sync_readonly "$P" --template-dir 2>/dev/null); RC=$?
  same "M13 no clone: exit 1"            "$RC" "1"
  same "M13 no clone: nothing on stdout" "$OUT" ""

  # The control: the same run with a real clone named answers it, so exit 1 is not the only answer.
  OUT=$(HOME="$R/home" CLAUDE_TEMPLATE_DIR="$T" DRIVE_SYNC_SCRIPT="$SCRIPT" \
        drive_sync_readonly "$P" --template-dir 2>/dev/null); RC=$?
  same "M13 control: a clone is found, exit 0" "$RC" "0"
  same "M13 control: and its path is printed"  "$OUT" "$T"
}

# ---------------------------------------------------------------------------- M15
# 085-AC-3. fold_helper_writes cross-checks the helper's own "scripts: copied N, deleted M" against
# the `  + name` lines it parsed. When they agree there is nothing to say; a drift line on an honest
# helper is noise forwarded into every session start. The graphify helper is the one stood in here:
# the sync runs it from the project, so the fake sits in both repositories, identical.
fake_graphify() {  # <claimed copies> <writes settings>
  cat > "$1" <<EOF
import os
open("scripts/gfy-demo.sh", "w").write("#!/bin/bash\\n")
print("  + gfy-demo.sh")
print("scripts: copied $2, deleted 0")
EOF
}
arm_helper_count_drift() {
  echo "== M15 — a helper whose count matches its lines is not drift (085-AC-3)"
  build m15
  printf '{"hooks":{}}\n' > "$T/.claude/settings.json"
  printf '{"hooks":{}}\n' > "$P/.claude/settings.json"
  fake_graphify "$T/scripts/sync-graphify-wiring.py" 1
  cp "$T/scripts/sync-graphify-wiring.py" "$P/scripts/sync-graphify-wiring.py"
  commit_both
  OUT=$(sync 2>&1)
  has   "M15 the sync ran and committed"               "$OUT" "[synced] template"
  hasnt "M15 claimed 1, parsed 1: no drift line"        "$OUT" "output format drift"

  # The control: a helper that claims 2 and lists 1 IS drift, so the arm is not blind to the line.
  build m15c
  printf '{"hooks":{}}\n' > "$T/.claude/settings.json"
  printf '{"hooks":{}}\n' > "$P/.claude/settings.json"
  fake_graphify "$T/scripts/sync-graphify-wiring.py" 2
  cp "$T/scripts/sync-graphify-wiring.py" "$P/scripts/sync-graphify-wiring.py"
  commit_both
  OUT=$(sync 2>&1)
  has   "M15 control: claimed 2, parsed 1 is drift"     "$OUT" "reported 2 script write(s), 1 parsed — output format drift"
}

# ---------------------------------------------------------------------------- M16 / M17 / M18
# 085-AC-3. [held] names the paths that were already staged and are not the sync's. It renders after
# a commit (SYNC_COMMIT set) and on the rebase/merge arm, and on neither --no-commit nor a run that
# committed nothing: there the developer asked the sync to leave git alone.
stage_strangers() {  # <name>…
  for _s in "$@"; do printf 'mine\n' > "$P/$_s"; git -C "$P" add "$_s"; done
}
arm_held_gate() {
  echo "== M16/M17/M18 — [held] after a commit, not on --no-commit (085-AC-3)"
  build m16
  commit_both
  stage_strangers stranger.txt
  OUT=$(sync 2>&1)
  has   "M16/M17 a committing sync names the staged stranger" "$OUT" "[held] 1 path(s) were already staged"
  has   "M16/M17 by its path"                                 "$OUT" "       stranger.txt"
  hasnt "M19 one held path under the cap is not capped"       "$OUT" "more, not named"
  same  "M16 the stranger is still staged, not committed"     "$(git -C "$P" diff --cached --name-only)" "stranger.txt"

  build m18
  commit_both
  stage_strangers stranger.txt
  OUT=$(sync --no-commit 2>&1)
  has   "M18 the --no-commit sync ran and committed nothing"  "$OUT" "· not committed"
  hasnt "M18 --no-commit renders no [held]"                   "$OUT" "[held]"
}

# ---------------------------------------------------------------------------- M19
# 085-AC-3. Past TEMPLATE_AUTOSYNC_NAME_LIMIT the list stops and says how many it did not name.
arm_held_cap() {
  echo "== M19 — [held] past the name limit says how many are not named (085-AC-3)"
  build m19
  commit_both
  stage_strangers a.txt b.txt c.txt
  OUT=$(TEMPLATE_AUTOSYNC_NAME_LIMIT=1 sync 2>&1)
  has   "M19 three held paths are counted"                    "$OUT" "[held] 3 path(s)"
  has   "M19 the first is named"                              "$OUT" "       a.txt"
  hasnt "M19 the second is not"                               "$OUT" "       b.txt"
  has   "M19 the rest are counted and the cap named"          "$OUT" "… and 2 more, not named — capped at 1 (TEMPLATE_AUTOSYNC_NAME_LIMIT)"
}

# ---------------------------------------------------------------------------- 092 L938
# 092 R4. --owed asks about a manifest and the template has none: exit 2 ("cannot answer") and an
# empty stdout, never the `[skip]` prose under a success code. The template is recognised by its root
# commit, which no fixture can forge and the mutation gate's snapshot does not carry, so the script
# runs from a directory whose template-identity.sh is a stub that answers `template`.
arm_l938_owed_in_template() {
  echo "== 092 L938 — --owed in the template exits 2 with nothing on stdout"
  R="$TMP/l938"; rm -rf "$R"; mkdir -p "$R/bin" "$R/repo/.claude"
  cp "$SCRIPT" "$R/bin/template-autosync.sh"
  printf 'template_identity() { echo template; }\n' > "$R/bin/template-identity.sh"
  git -C "$R/repo" init -q -b main
  OUT=$(DRIVE_SYNC_SCRIPT="$R/bin/template-autosync.sh" drive_sync "$R/repo" "$TMP" --owed 2>/dev/null); RC=$?
  same "092 L938 --owed in the template exits 2"     "$RC" "2"
  same "092 L938 --owed in the template: empty stdout" "$OUT" ""

  # The control: a plain run in the same template skips and succeeds, so exit 2 is --owed's alone.
  OUT=$(DRIVE_SYNC_SCRIPT="$R/bin/template-autosync.sh" drive_sync "$R/repo" "$TMP" 2>&1); RC=$?
  same "092 L938 control: a plain run in the template exits 0" "$RC" "0"
  has  "092 L938 control: and says it is the template"         "$OUT" "[skip] this IS the template repo"
}

# ---------------------------------------------------------------------------- 092 L2002
# 092 R4. On a first sync (no manifest) a differing file is asked against the template's history:
# bytes that ever WERE a template version are adopted (updated), bytes no version had are a local
# edit and are left alone. The template carries two versions, so a match on the older one is needed.
arm_l2002_template_history() {
  echo "== 092 L2002 — an older template version is adopted, a local edit is not"
  build l2002
  printf 'other v1\n' > "$T/.claude/rules/other-rule.md"
  git -C "$T" add -A; git -C "$T" commit -qm v1
  printf 'rule v2\n'  > "$T/.claude/rules/demo-rule.md"
  printf 'other v2\n' > "$T/.claude/rules/other-rule.md"
  git -C "$T" add -A; git -C "$T" commit -qm v2
  printf 'rule v1\n'    > "$P/.claude/rules/demo-rule.md"    # the OLDER template version
  printf 'other mine\n' > "$P/.claude/rules/other-rule.md"   # no template version ever had these bytes
  git -C "$P" add -A; git -C "$P" commit -qm project
  sync --quiet >/dev/null 2>&1
  same "092 L2002 bytes of an older template version are updated" "$(cat "$P/.claude/rules/demo-rule.md")" "rule v2"
  same "092 L2002 a local edit is skipped, not overwritten"       "$(cat "$P/.claude/rules/other-rule.md")" "other mine"
}

# ---------------------------------------------------------------------------- 092 L2310
# 092 R4. Bytes agree and only the exec bit differs: --check lists the file as an update and leaves
# the mode alone; a real sync mirrors the template's mode.
arm_l2310_exec_bit() {
  echo "== 092 L2310 — an exec-bit-only difference: listed under --check, mirrored by a sync"
  build l2310
  chmod +x "$T/.claude/rules/demo-rule.md"
  cp "$T/.claude/rules/demo-rule.md" "$P/.claude/rules/demo-rule.md"
  chmod -x "$P/.claude/rules/demo-rule.md"
  commit_both
  OUT=$(sync --check 2>&1)
  has "092 L2310 --check lists the mode correction as an update" "$OUT" "[check] would update:1 ·"
  if [ -x "$P/.claude/rules/demo-rule.md" ]; then bad "092 L2310 --check leaves the mode on disk unchanged"
  else ok "092 L2310 --check leaves the mode on disk unchanged"; fi
  sync --quiet >/dev/null 2>&1
  if [ -x "$P/.claude/rules/demo-rule.md" ]; then ok "092 L2310 a real sync mirrors the exec bit"
  else bad "092 L2310 a real sync mirrors the exec bit"; fi
}

# ---------------------------------------------------------------------------- 092 L2533
# 092 R4. A path the stamp says the sync wrote, which the template no longer ships, is an orphan only
# while it is on disk. Once the developer has deleted it, there is nothing to act on and no line.
orphan_fixture() {  # <name> — a synced project whose stamp claims a rule the template does not ship
  build "$1"
  commit_both
  sync --quiet >/dev/null 2>&1
  printf '%s  %s\n' 0000000000000000000000000000000000000000000000000000000000000000 \
    .claude/rules/gone-rule.md >> "$P/.claude/.template-sync"
}
arm_l2533_deleted_orphan() {
  echo "== 092 L2533 — an orphan the developer deleted is not reported again"
  orphan_fixture l2533
  OUT=$(sync --force 2>&1)
  has   "092 L2533 the forced sync ran"                     "$OUT" "[synced] template"
  hasnt "092 L2533 a deleted orphan is not reported"        "$OUT" "gone-rule.md"
  hasnt "092 L2533 nor recorded in the stamp"               "$(cat "$P/.claude/.template-sync")" "# orphan"

  # The control: the same orphan still on disk IS reported, so the arm is not blind to the line.
  orphan_fixture l2533c
  printf 'old\n' > "$P/.claude/rules/gone-rule.md"
  OUT=$(sync --force 2>&1)
  has   "092 L2533 control: an orphan on disk is reported"  "$OUT" "gone-rule.md"
}

# ---------------------------------------------------------------------------- 092 L2613
# 092 R4. The [check] header names the project side: `never synced` with no stamp, the stamp's SHA
# when there is one, and never both.
arm_l2613_check_header() {
  echo "== 092 L2613 — [check] says never synced, or the stamp's SHA"
  build l2613
  commit_both
  OUT=$(sync --check 2>&1)
  TSHA=$(printf '%s\n' "$OUT" | sed -n 's/^\[check\] template \([^ ]*\) vs project .*/\1/p')
  same "092 L2613 no stamp: the header says never synced" \
       "$(printf '%s\n' "$OUT" | grep '^\[check\] template ')" "[check] template $TSHA vs project never synced"

  sync --quiet >/dev/null 2>&1
  SSHA=$(sed -n 's/^sha=//p' "$P/.claude/.template-sync" | head -1)
  printf 'rule v2\n' > "$T/.claude/rules/demo-rule.md"
  git -C "$T" commit -qam v2
  OUT=$(sync --check 2>&1)
  TSHA=$(printf '%s\n' "$OUT" | sed -n 's/^\[check\] template \([^ ]*\) vs project .*/\1/p')
  [ -n "$SSHA" ] && [ "$SSHA" != "$TSHA" ] && ok "092 L2613 the fixture has a stamp SHA behind the template" \
    || bad "092 L2613 the fixture has a stamp SHA behind the template (stamp '$SSHA', template '$TSHA')"
  same "092 L2613 with a stamp: the header names its SHA" \
       "$(printf '%s\n' "$OUT" | grep '^\[check\] template ')" "[check] template $TSHA vs project $SSHA"
  hasnt "092 L2613 with a stamp: never synced is not said" "$OUT" "never synced"
}

# ---------------------------------------------------------------------------- 092 L3107
# 092 R4. A stamp `# wrote <hash> <path>` record is carried to the next stamp while the file still has
# those bytes. A `# wrote <hash>` line with no path is dropped, and the carried entries stay intact.
arm_l3107_wrote_carry() {
  echo "== 092 L3107 — a pathless # wrote line is ignored, carried entries stay"
  build l3107
  printf 'mine\n' > "$P/notes.txt"
  commit_both
  sync --quiet >/dev/null 2>&1
  H=$(if command -v sha256sum >/dev/null 2>&1; then sha256sum "$P/notes.txt"
      else shasum -a 256 "$P/notes.txt"; fi | cut -d' ' -f1)
  printf '# wrote %s\n# wrote %s notes.txt\n' "$H" "$H" >> "$P/.claude/.template-sync"
  sync --force --quiet >/dev/null 2>&1
  STAMP_NOW=$(cat "$P/.claude/.template-sync")
  has  "092 L3107 the carried entry is still in the stamp" "$STAMP_NOW" "# wrote $H notes.txt"
  same "092 L3107 the pathless line is gone"               "$(grep -cx "# wrote $H" "$P/.claude/.template-sync")" "0"
}

# ---------------------------------------------------------------------------- 092 L3526
# 092 R4. The only run where the commit's two guards disagree: the sync's one staged change is a
# deletion (the graphify helper removed a script) and the stamp has no news, so there is no message
# but there IS a pathspec. That run says `nothing to commit` and HEAD does not move.
fake_graphify_deleter() {
  cat > "$1" <<'EOF'
import os
if os.path.exists("scripts/gfy-old.sh"):
    os.remove("scripts/gfy-old.sh")
    print("  - gfy-old.sh")
    print("scripts: copied 0, deleted 1")
EOF
}
arm_l3526_nothing_to_commit() {
  echo "== 092 L3526 — a run with no message makes no commit, HEAD unchanged"
  build l3526
  printf '{"hooks":{}}\n' > "$T/.claude/settings.json"
  printf '{"hooks":{}}\n' > "$P/.claude/settings.json"
  fake_graphify_deleter "$T/scripts/sync-graphify-wiring.py"
  cp "$T/scripts/sync-graphify-wiring.py" "$P/scripts/sync-graphify-wiring.py"
  commit_both
  sync --quiet >/dev/null 2>&1
  printf '#!/bin/bash\n' > "$P/scripts/gfy-old.sh"
  git -C "$P" add scripts/gfy-old.sh; git -C "$P" commit -qm "a script the helper will delete"
  HEAD0=$(git -C "$P" rev-parse HEAD)
  OUT=$(sync --force 2>&1)
  [ -f "$P/scripts/gfy-old.sh" ] && bad "092 L3526 the helper deleted its script" || ok "092 L3526 the helper deleted its script"
  has  "092 L3526 the run says there is nothing to commit" "$OUT" "nothing to commit"
  same "092 L3526 HEAD did not move"                       "$(git -C "$P" rev-parse HEAD)" "$HEAD0"
}

# ---------------------------------------------------------------------------- 092 L3764
# 092 R4. After a committing sync the [verify] obligation names the declared command, and with no
# declaration it says how to declare one instead of naming an empty command. The obligation needs a
# commit that carries more than the stamp, so the project holds an older template version of the rule.
verify_fixture() {  # <name>
  build "$1"
  git -C "$T" add -A; git -C "$T" commit -qm v1
  printf 'rule v2\n' > "$T/.claude/rules/demo-rule.md"
  printf 'rule v1\n' > "$P/.claude/rules/demo-rule.md"
}
arm_l3764_verify_hint() {
  echo "== 092 L3764 — [verify] names the declared command, or says how to declare one"
  verify_fixture l3764
  commit_both
  OUT=$(sync 2>&1)
  has   "092 L3764 no declaration: the obligation is raised"   "$OUT" "[verify]"
  has   "092 L3764 no declaration: says how to declare one"   "$OUT" ".claude/.template-sync-verify"
  hasnt "092 L3764 no declaration: no empty command is named" "$OUT" "run scripts/template-sync-verify.sh   ("

  verify_fixture l3764d
  printf '# how this project proves it works\nmake test\n' > "$P/.claude/.template-sync-verify"
  commit_both
  OUT=$(sync 2>&1)
  has   "092 L3764 declared: the command is named"            "$OUT" "run scripts/template-sync-verify.sh   (make test)"
  hasnt "092 L3764 declared: no how-to-declare text"          "$OUT" "no declaration"
}

want arm_unlisted_glob          && arm_unlisted_glob
want arm_no_record_is_not_stale && arm_no_record_is_not_stale
want arm_accept_core            && arm_accept_core
want arm_accept_unshipped       && arm_accept_unshipped
want arm_settings_stay_valid    && arm_settings_stay_valid
want arm_template_dir_none      && arm_template_dir_none
want arm_helper_count_drift     && arm_helper_count_drift
want arm_held_gate              && arm_held_gate
want arm_held_cap               && arm_held_cap
want arm_l938_owed_in_template  && arm_l938_owed_in_template
want arm_l2002_template_history && arm_l2002_template_history
want arm_l2310_exec_bit         && arm_l2310_exec_bit
want arm_l2533_deleted_orphan   && arm_l2533_deleted_orphan
want arm_l2613_check_header     && arm_l2613_check_header
want arm_l3107_wrote_carry      && arm_l3107_wrote_carry
want arm_l3526_nothing_to_commit && arm_l3526_nothing_to_commit
want arm_l3764_verify_hint      && arm_l3764_verify_hint

echo
echo "test-template-autosync-arms.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

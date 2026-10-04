#!/usr/bin/env bash
. "$(dirname -- "$0")/self-test-env.sh" || exit 1
# test-core-machinery-guard.sh — the guard that refuses an edit the sync would revert.
#
# Spec 007ao. `scripts/core-machinery-guard-hook.sh` denies Edit/Write/MultiEdit
# against the CORE set — the files `template-autosync.sh` overwrites unconditionally.
# Getting the deny right is the easy half; the half that decides whether the guard
# survives contact with a developer is everything it must NOT do. So the arms below
# are weighted that way: two prove it bites, seven prove it stays quiet, and one
# proves the classifier underneath is cheap enough to sit in front of every edit.
#
# Everything here runs the real hook against real throwaway git repositories, feeding
# it the same PreToolUse JSON Claude Code does. Nothing greps the hook's source.
#
# Exit 0 = every assertion held. Exit 1 = a real failure.

set -u

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
HOOK="$SELF_DIR/core-machinery-guard-hook.sh"
# Spec 029: read the verdict the way the CLI does — a deny without hookEventName is "dropped".
. "$SELF_DIR/hook-verdict.sh"
SYNC="$SELF_DIR/template-autosync.sh"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok    %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$*"; }
info() { printf '        %s\n' "$*"; }

[ -f "$HOOK" ] || { echo "missing: $HOOK"; exit 1; }
[ -f "$SYNC" ] || { echo "missing: $SYNC"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 1; }

WORK=$(mktemp -d 2>/dev/null || mktemp -d -t coreguard)
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------- the fixture
# A project as the guard expects to find one: a git root, a .claude/, and its own copy
# of the sync script — which is what makes the classifier reachable. `origin` is set to
# something that is emphatically not the template, because the template check is one of
# the arms and a repo with no origin at all would pass it for the wrong reason.
make_project() {
  _p="$WORK/$1"
  mkdir -p "$_p/scripts" "$_p/.claude/rules"
  git -C "$_p" init -q 2>/dev/null || { git init -q "$_p"; }
  git -C "$_p" remote add origin "https://github.com/someone/not-the-template.git" 2>/dev/null
  cp "$SYNC" "$_p/scripts/template-autosync.sh"
  : > "$_p/scripts/spec_active.py"                      # CORE
  : > "$_p/scripts/project-specific-thing.sh"           # not CORE
  : > "$_p/.claude/rules/feature-pipeline.md"           # CORE
  : > "$_p/.claude/rules/sqlite.md"                     # not CORE
  printf '%s' "$_p"
}

# Run the hook exactly as the harness does: JSON on stdin, decision on stdout.
run_hook() {          # $1 = file path, rest = VAR=VAL environment overrides
  _f="$1"; shift
  env "$@" bash "$HOOK" <<JSON 2>/dev/null
{"tool_name":"Edit","tool_input":{"file_path":"$_f"}}
JSON
}

decision() { hook_verdict "$1"; }
reason()   { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null; }

PROJ=$(make_project proj)

printf '\n[deny] the two paths the sync owns\n'

# ---- A1: a CORE script is refused, and the refusal is usable -----------------
OUT=$(run_hook "$PROJ/scripts/spec_active.py")
if [ "$(decision "$OUT")" = "deny" ]; then
  ok "a CORE script is denied (scripts/spec_active.py)"
  R=$(reason "$OUT")
  # A deny that names no next step is an obstacle. Each of these is a separate
  # promise the spec makes about the message (FR-005), so each is asserted alone.
  case "$R" in *"scripts/spec_active.py"*) ok "  the reason names the path" ;;
    *) bad "  the reason does not name the path" ;; esac
  case "$R" in *"CORE machinery"*"overwrites it unconditionally"*|*"CORE machinery, which this sync overwrites unconditionally"*)
      ok "  the reason states the mechanism" ;;
    *) bad "  the reason does not state the mechanism"; info "$R" ;; esac
  case "$R" in *"ALLOW_CORE_MACHINERY_EDIT"*) ok "  the reason names the override" ;;
    *) bad "  the reason does not name the override" ;; esac
  case "$R" in *"--is-core"*) ok "  the reason says how to ask about any other path" ;;
    *) bad "  the reason does not mention --is-core" ;; esac
else
  bad "a CORE script was NOT denied"; info "$OUT"
fi

# ---- A2: a CORE rule is refused on the same terms ----------------------------
OUT=$(run_hook "$PROJ/.claude/rules/feature-pipeline.md")
[ "$(decision "$OUT")" = "deny" ] \
  && ok "a CORE rule is denied (.claude/rules/feature-pipeline.md)" \
  || bad "a CORE rule was NOT denied"

printf '\n[silent] everywhere it has no business speaking\n'

# ---- A3 / A4: the project's own files ----------------------------------------
OUT=$(run_hook "$PROJ/scripts/project-specific-thing.sh")
[ -z "$OUT" ] && ok "a non-CORE script is untouched" || { bad "a non-CORE script was judged"; info "$OUT"; }

OUT=$(run_hook "$PROJ/.claude/rules/sqlite.md")
[ -z "$OUT" ] && ok "a project-only rule is untouched" || { bad "a project rule was judged"; info "$OUT"; }

# ---- A5: the template repository itself --------------------------------------
# The whole deny message says "go and edit it in the template". Denying it there too
# would leave the instruction with nowhere to be followed.
# Spec 091 R1: the template is recognised by its history, so the fixture borrows this clone's objects
# and moves its branch onto the template's HEAD. Returns 1 when this clone is not the template (a
# project runs this test too), and the arm then checks only that a URL alone exempts nothing.
template_history() {
  _src=$(git -C "$SELF_DIR" rev-parse --show-toplevel 2>/dev/null) || return 1
  git -C "$_src" cat-file -e d3cf8238372ce7a37d5d66b115cbcbf9d57bb2b9^{commit} 2>/dev/null || return 1
  printf '%s\n' "$(git -C "$_src" rev-parse --path-format=absolute --git-common-dir)/objects" >> "$1/.git/objects/info/alternates"
  git -C "$1" update-ref HEAD "$(git -C "$_src" rev-parse HEAD)"
}
TPL=$(make_project tpl)
git -C "$TPL" remote set-url origin "https://github.com/johanolofsson72/Claude.git"
OUT=$(run_hook "$TPL/scripts/spec_active.py")
[ -n "$OUT" ] && ok "the template's URL alone exempts nothing (spec 091 R1)" \
              || bad "a project became the template by naming its URL"
if template_history "$TPL"; then
  OUT=$(run_hook "$TPL/scripts/spec_active.py")
  [ -z "$OUT" ] && ok "the template repository is exempt — that is where the change belongs" \
                || { bad "the guard fired inside the template repo"; info "$OUT"; }
else
  info "skip: this clone's history is not the template's, so the exempt arm cannot be built"
fi

# ---- A6: a project with no sync ----------------------------------------------
# No sync script means no sync, which means nothing is coming to overwrite the file.
# A guard with no threat to point at has no claim to make.
NOSYNC=$(make_project nosync)
rm -f "$NOSYNC/scripts/template-autosync.sh"
OUT=$(run_hook "$NOSYNC/scripts/spec_active.py")
[ -z "$OUT" ] && ok "a project with no template-autosync.sh is exempt" \
             || { bad "the guard fired with no sync script present"; info "$OUT"; }

# ---- A7: outside a repository -------------------------------------------------
mkdir -p "$WORK/loose/scripts"
OUT=$(run_hook "$WORK/loose/scripts/spec_active.py")
[ -z "$OUT" ] && ok "a path outside any git repository is exempt" \
             || { bad "the guard fired outside a repository"; info "$OUT"; }

# ---- A8: a nested scripts/ directory that only shares a basename --------------
# .claude/skills/<skill>/scripts/detect-stack.sh is somebody else's file. The sync
# would never write it, so the guard must not claim it either.
mkdir -p "$PROJ/.claude/skills/x/scripts"
: > "$PROJ/.claude/skills/x/scripts/detect-stack.sh"
OUT=$(run_hook "$PROJ/.claude/skills/x/scripts/detect-stack.sh")
[ -z "$OUT" ] && ok "a nested scripts/ dir sharing a CORE basename is untouched" \
             || { bad "the guard claimed a file the sync does not own"; info "$OUT"; }

printf '\n[escape] the ways through, and the way it breaks\n'

# ---- A9: the override ---------------------------------------------------------
OUT=$(run_hook "$PROJ/scripts/spec_active.py" ALLOW_CORE_MACHINERY_EDIT=1)
if [ "$(decision "$OUT")" = "deny" ]; then
  bad "ALLOW_CORE_MACHINERY_EDIT=1 did not permit the edit"
else
  ok "ALLOW_CORE_MACHINERY_EDIT=1 permits the edit"
  # Permitting is not the same as saying nothing. A silent override is a bypass
  # nobody can see in the transcript afterwards.
  case "$OUT" in *ALLOW_CORE_MACHINERY_EDIT*) ok "  and still says what was overridden" ;;
    *) bad "  but says nothing about what was overridden"; info "$OUT" ;; esac
fi

# ---- A10: the classifier is broken -------------------------------------------
# Fail OPEN, and indistinguishably from "not CORE": if the machinery is not working,
# no sync is coming, and blocking every script edit in the meantime is how a guard
# gets deleted along with the protection it was carrying.
BROKEN=$(make_project broken)
printf '#!/bin/bash\nexit 77\n' > "$BROKEN/scripts/template-autosync.sh"
OUT=$(run_hook "$BROKEN/scripts/spec_active.py")
# Spec 083 (GAP-1): open, but no longer silent — an additionalContext notice, never a decision.
[ "$(decision "$OUT")" = none ] && ok "a classifier that errors fails open (announced, spec 083)" \
             || { bad "a broken classifier produced a decision"; info "$OUT"; }

# ---- A11: the classifier hangs ------------------------------------------------
# The bound is the difference between a guard and a hang in front of the editor.
if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
  SLOW=$(make_project slow)
  printf '#!/bin/bash\nsleep 30\n' > "$SLOW/scripts/template-autosync.sh"
  T0=$(date +%s)
  OUT=$(run_hook "$SLOW/scripts/spec_active.py")
  T1=$(date +%s)
  if [ $((T1 - T0)) -lt 15 ]; then ok "a hanging classifier is bounded ($((T1 - T0))s)"
  else bad "a hanging classifier was not bounded ($((T1 - T0))s)"; fi
  [ "$(decision "$OUT")" = none ] && ok "  and the timeout fails open" || bad "  but produced a decision"
else
  info "no timeout(1) available — the bound arm is skipped, not passed"
fi

printf '\n[cost] the classifier sits in front of every edit\n'

# ---- A12: --is-core is in the millisecond class, with no template present -----
# Both halves matter. The wall clock is the budget; the missing template directory is
# the proof that it never resolves one, which is what keeps a 20 s bounded git fetch
# out of the path (research.md M7).
T0=$(date +%s)
i=0
while [ "$i" -lt 20 ]; do
  env -u CLAUDE_TEMPLATE_DIR HOME="$WORK/no-home" bash "$SYNC" --is-core scripts/spec_active.py >/dev/null 2>&1
  i=$((i + 1))
done
T1=$(date +%s)
if [ $((T1 - T0)) -le 4 ]; then ok "20 --is-core calls in $((T1 - T0))s with no template reachable"
else bad "20 --is-core calls took $((T1 - T0))s — something below it is resolving a template"; fi

env -u CLAUDE_TEMPLATE_DIR HOME="$WORK/no-home" bash "$SYNC" --is-core scripts/spec_active.py >/dev/null 2>&1
[ $? -eq 0 ] && ok "--is-core still answers CORE with no template directory anywhere" \
             || bad "--is-core needs a template to answer"

env -u CLAUDE_TEMPLATE_DIR HOME="$WORK/no-home" bash "$SYNC" --is-core scripts/project-specific-thing.sh >/dev/null 2>&1
[ $? -eq 1 ] && ok "--is-core exits 1 for a file the template does not own" \
             || bad "--is-core did not exit 1 for a non-CORE path"

bash "$SYNC" --is-core >/dev/null 2>&1
[ $? -eq 2 ] && ok "--is-core exits 2 with no path" || bad "--is-core did not exit 2 with no path"

bash "$SYNC" --is-core --quiet >/dev/null 2>&1
[ $? -eq 2 ] && ok "--is-core exits 2 rather than swallowing the next flag as a path" \
             || bad "--is-core swallowed a flag as its path argument"

printf '\n[install] a write that leaves the file equal to the template copy (spec 039)\n'

# A first sync places every CORE file with the template's own bytes, and the guard used to refuse
# that on the path alone. These arms feed it the bytes and a template to compare them with. HOME
# points away from the real clone, so the fixture template is the only one it can find.
FTPL="$WORK/fixture-template"
mkdir -p "$FTPL/scripts" "$FTPL/.claude/rules"
: > "$FTPL/scripts/sync-prompt.md"
printf '#!/usr/bin/env python3\nprint("template")\nprint("tail")\n' > "$FTPL/scripts/spec_active.py"
printf 'rule — åäö ✓\n' > "$FTPL/.claude/rules/feature-pipeline.md"
TPL_BYTES=$(cat "$FTPL/scripts/spec_active.py"; printf x); TPL_BYTES=${TPL_BYTES%x}

INST=$(make_project inst)

# Run the hook with a full tool_input object. $1 = tool name, $2 = tool_input JSON, rest = env.
run_tool() {
  _t="$1"; _i="$2"; shift 2
  jq -cn --arg t "$_t" --argjson i "$_i" '{tool_name: $t, tool_input: $i}' \
    | env CLAUDE_TEMPLATE_DIR="$FTPL" HOME="$WORK/no-home" "$@" bash "$HOOK" 2>/dev/null
}
write_input() { jq -cn --arg f "$1" --arg c "$2" '{file_path: $f, content: $c}'; }

# ---- SC-039-01: Write, identical bytes ----------------------------------------
OUT=$(run_tool Write "$(write_input "$INST/scripts/spec_active.py" "$TPL_BYTES")")
[ -z "$OUT" ] && ok "SC-039-01 a Write equal to the template copy passes silently" \
             || { bad "SC-039-01 a byte-identical Write was judged"; info "$OUT"; }

# ---- SC-039-02: one trailing newline short ------------------------------------
OUT=$(run_tool Write "$(write_input "$INST/scripts/spec_active.py" "${TPL_BYTES%?}")")
[ "$(decision "$OUT")" = "deny" ] && ok "SC-039-02 a Write missing the final newline is denied" \
                                  || { bad "SC-039-02 one byte short was allowed"; info "$OUT"; }

# ---- SC-039-03: different content ---------------------------------------------
OUT=$(run_tool Write "$(write_input "$INST/scripts/spec_active.py" "local change")")
if [ "$(decision "$OUT")" = "deny" ]; then
  ok "SC-039-03 a Write with different bytes is denied"
  case "$(reason "$OUT")" in *"byte-identical"*) ok "  and the reason says an identical copy would pass" ;;
    *) bad "  the reason does not mention the byte-identical pass (FR-08)" ;; esac
else
  bad "SC-039-03 a changing Write was allowed"; info "$OUT"
fi

# ---- SC-039-04 / 05 / 06: Edit ------------------------------------------------
printf '#!/usr/bin/env python3\nprint("drifted")\nprint("tail")\n' > "$INST/scripts/spec_active.py"
EI=$(jq -cn --arg f "$INST/scripts/spec_active.py" '{file_path: $f, old_string: "drifted", new_string: "template"}')
OUT=$(run_tool Edit "$EI")
[ -z "$OUT" ] && ok "SC-039-04 an Edit that restores the template copy passes silently" \
             || { bad "SC-039-04 a restoring Edit was judged"; info "$OUT"; }

EI=$(jq -cn --arg f "$INST/scripts/spec_active.py" '{file_path: $f, old_string: "drifted", new_string: "mine"}')
OUT=$(run_tool Edit "$EI")
[ "$(decision "$OUT")" = "deny" ] && ok "SC-039-05 an Edit that leaves a difference is denied" \
                                  || { bad "SC-039-05 a diverging Edit was allowed"; info "$OUT"; }

printf 'a\nb\na\n' > "$FTPL/scripts/spec_active.py"
printf 'z\nb\nz\n' > "$INST/scripts/spec_active.py"
EI=$(jq -cn --arg f "$INST/scripts/spec_active.py" '{file_path: $f, old_string: "z", new_string: "a", replace_all: true}')
OUT=$(run_tool Edit "$EI")
[ -z "$OUT" ] && ok "SC-039-06 replace_all is applied to every occurrence" \
             || { bad "SC-039-06 replace_all result was judged"; info "$OUT"; }
EI=$(jq -cn --arg f "$INST/scripts/spec_active.py" '{file_path: $f, old_string: "z", new_string: "a"}')
OUT=$(run_tool Edit "$EI")
[ "$(decision "$OUT")" = "deny" ] && ok "  and without replace_all only the first is, so it is denied" \
                                  || { bad "  a single replacement was treated as replace_all"; info "$OUT"; }

# ---- SC-039-07: MultiEdit ------------------------------------------------------
printf 'z\nb\ny\n' > "$INST/scripts/spec_active.py"
EI=$(jq -cn --arg f "$INST/scripts/spec_active.py" \
  '{file_path: $f, edits: [{old_string: "z", new_string: "a"}, {old_string: "y", new_string: "a"}]}')
OUT=$(run_tool MultiEdit "$EI")
[ -z "$OUT" ] && ok "SC-039-07 a MultiEdit whose result equals the template passes silently" \
             || { bad "SC-039-07 a restoring MultiEdit was judged"; info "$OUT"; }

# ---- SC-039-08: no template anywhere -------------------------------------------
OUT=$(jq -cn --arg f "$INST/scripts/spec_active.py" '{tool_name: "Write", tool_input: {file_path: $f, content: "a\nb\na\n"}}' \
  | env -u CLAUDE_TEMPLATE_DIR HOME="$WORK/no-home" bash "$HOOK" 2>/dev/null)
[ "$(decision "$OUT")" = "deny" ] && ok "SC-039-08 identical bytes with no template reachable are denied (fail closed)" \
                                  || { bad "SC-039-08 allowed with nothing to compare against"; info "$OUT"; }

# ---- SC-039-09: template has no such file --------------------------------------
mv "$FTPL/scripts/spec_active.py" "$FTPL/scripts/spec_active.py.away"
OUT=$(run_tool Write "$(write_input "$INST/scripts/spec_active.py" "a
b
a
")")
[ "$(decision "$OUT")" = "deny" ] && ok "SC-039-09 a template with no copy of the file denies" \
                                  || { bad "SC-039-09 allowed against a missing template file"; info "$OUT"; }
mv "$FTPL/scripts/spec_active.py.away" "$FTPL/scripts/spec_active.py"

# ---- SC-039-10: the Bash route carries a path and no bytes ----------------------
OUT=$(jq -cn --arg f "$INST/scripts/spec_active.py" '{tool_input: {file_path: $f}}' \
  | env CLAUDE_TEMPLATE_DIR="$FTPL" HOME="$WORK/no-home" bash "$HOOK" 2>/dev/null)
[ "$(decision "$OUT")" = "deny" ] && ok "SC-039-10 a path-only payload (Bash delegation) is still denied" \
                                  || { bad "SC-039-10 a payload with no bytes was allowed"; info "$OUT"; }

# ---- SC-039-11: non-ASCII bytes -------------------------------------------------
RULE_BYTES=$(cat "$FTPL/.claude/rules/feature-pipeline.md"; printf x); RULE_BYTES=${RULE_BYTES%x}
OUT=$(run_tool Write "$(write_input "$INST/.claude/rules/feature-pipeline.md" "$RULE_BYTES")")
[ -z "$OUT" ] && ok "SC-039-11 a non-ASCII rule equal to the template passes silently" \
             || { bad "SC-039-11 non-ASCII identical content was judged"; info "$OUT"; }

# ---- SC-039-12: Edit against a file that does not exist -------------------------
rm -f "$INST/scripts/spec_active.py"
EI=$(jq -cn --arg f "$INST/scripts/spec_active.py" '{file_path: $f, old_string: "", new_string: "a\nb\na\n"}')
OUT=$(run_tool Edit "$EI")
[ "$(decision "$OUT")" = "deny" ] && ok "SC-039-12 an Edit on a missing file is denied" \
                                  || { bad "SC-039-12 an Edit with no current content was allowed"; info "$OUT"; }

# ---- spec 098 R3 (F141): a synced project whose sync script is gone ------------
printf '\n[098-R3] the sync script deleted from a synced project  (098-AC-3)\n'
S3=$(make_project s3); rm -f "$S3/scripts/template-autosync.sh"; : > "$S3/.claude/.template-sync"
OUT=$(run_hook "$S3/scripts/project-specific-thing.sh")
if [ "$(decision "$OUT")" = "deny" ]; then
  ok "098-AC-3 the stamp present, the sync gone: a scripts/ edit is denied"
  R=$(reason "$OUT")
  case "$R" in *"template-autosync.sh is missing"*) ok "  the reason names the missing file" ;; *) bad "  the reason does not name the file"; info "$R" ;; esac
  case "$R" in *"! git checkout HEAD -- scripts/template-autosync.sh"*) ok "  and the developer's route" ;; *) bad "  no route in the reason" ;; esac
else bad "098-AC-3 the guard went silent with the sync deleted"; info "$OUT"; fi
S3R=$(make_project s3r); rm -f "$S3R/scripts/template-autosync.sh"; mkdir -p "$S3R/specs"; : > "$S3R/specs/INDEX.md"
[ "$(decision "$(run_hook "$S3R/.claude/rules/sqlite.md")")" = "deny" ] && ok "a register is evidence too" || bad "a register did not count as evidence"
# Threat model #4: delete the stamp and the register as well; the hook running from the project's own
# scripts/ is evidence nothing in the tree can take away without disabling the guard.
S3H=$(make_project s3h); rm -f "$S3H/scripts/template-autosync.sh"
for f in "$SELF_DIR"/*.sh "$SELF_DIR"/*.py; do case "$f" in */template-autosync.sh) ;; *) cp "$f" "$S3H/scripts/" ;; esac; done
OUT=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$S3H/scripts/project-specific-thing.sh" | bash "$S3H/scripts/core-machinery-guard-hook.sh" 2>/dev/null)
[ "$(decision "$OUT")" = "deny" ] && ok "threat #4: no stamp, no register, the guard installed here: denied" || { bad "threat #4: a project-installed guard went silent"; info "$OUT"; }
OUT=$(run_hook "$NOSYNC/scripts/project-specific-thing.sh")
[ -z "$OUT" ] && ok "098-AC-3 a .claude/ with no stamp and no register stays silent (A6 unchanged)" || { bad "an unrelated .claude/ repo is now guarded"; info "$OUT"; }
if [ -n "${TPL:-}" ] && template_history "$TPL" 2>/dev/null; then
  rm -f "$TPL/scripts/template-autosync.sh"; : > "$TPL/.claude/.template-sync"
  OUT=$(run_hook "$TPL/scripts/spec_active.py")
  [ -z "$OUT" ] && ok "098-AC-3 the template stays exempt with its sync gone" || { bad "098-AC-3 the template is denied"; info "$OUT"; }
else
  info "skip: the template half needs this clone's template history"
fi
SAB3="$WORK/sab3"; mkdir -p "$SAB3"; cp "$SELF_DIR"/*.sh "$SELF_DIR"/*.py "$SAB3"/
sed 's/^  if guard_core_synced .*then$/  if false; then/' "$HOOK" > "$SAB3/core-machinery-guard-hook.sh"
if cmp -s "$HOOK" "$SAB3/core-machinery-guard-hook.sh"; then bad "098-R3 sabotage target not found"; else
  OUT=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$S3/scripts/project-specific-thing.sh" | bash "$SAB3/core-machinery-guard-hook.sh" 2>/dev/null)
  [ -z "$OUT" ] && ok "098-R3 sabotage: without the rule the deleted sync silences the guard again" || bad "098-R3 sabotage: the mutant still speaks"
fi

# ---- spec 098 R4 (F142): the root walk cannot ask git ------------------------------
printf '\n[098-R4] a linked worktree on a PATH without git  (098-AC-4)\n'
W4=$(make_project w4)
git -C "$W4" -c user.email=t@example.invalid -c user.name=t -c commit.gpgsign=false commit -qm init --allow-empty
git -C "$W4" worktree add -q "$W4/.claude/worktrees/wt" 2>/dev/null
NOGIT="$WORK/nogit"; mkdir -p "$NOGIT"
for d in /usr/bin /bin /usr/local/bin /opt/homebrew/bin; do
  [ -d "$d" ] || continue
  for x in "$d"/*; do b=${x##*/}; [ "$b" = git ] || [ -e "$NOGIT/$b" ] || ln -s "$x" "$NOGIT/$b" 2>/dev/null; done
done
# The stamp the pre-098 code would have read for exactly this notice, planted first (098-AC-4).
SID="s098-$$"; F4="$(cd -P "$W4" && pwd)/.claude/worktrees/wt/scripts/spec_active.py"
KEY=$(printf '%s' "guard-announce:core-machinery-guard:the root walk could not ask git (git is not on PATH), so $F4 was not checked" | cksum | tr -d ' ' | cut -c1-24)
mkdir -p "${TMPDIR:-/tmp}/claude-hook-notices/$SID" && : > "${TMPDIR:-/tmp}/claude-hook-notices/$SID/$KEY"
OUT=$(printf '{"session_id":"%s","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$SID" "$W4/.claude/worktrees/wt/scripts/spec_active.py" \
      | (cd "$W4/.claude/worktrees/wt" && env PATH="$NOGIT" CLAUDE_PROJECT_DIR="$W4/.claude/worktrees/wt" bash "$HOOK") 2>/dev/null)
if [ -d "$W4/.claude/worktrees/wt" ]; then
  case "$OUT" in *"could not ask git"*"git is not on PATH"*) ok "098-AC-4 the CORE guard allows aloud, naming git, past a planted TMPDIR stamp" ;; *) bad "098-AC-4 no announcement"; info "$OUT" ;; esac
  [ "$(decision "$OUT")" = "deny" ] && bad "  …but it denied" || ok "  and it does not deny (fail open, O3)"
  [ -n "$(ls -A "$W4/.git/worktrees/wt/claude-hook-notices/$SID" 2>/dev/null)" ] && ok "  its stamp is in the worktree's git dir" || bad "  no stamp in the git dir"
  OUT2=$(printf '{"session_id":"%s","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$SID" "$W4/.claude/worktrees/wt/scripts/spec_active.py" \
        | (cd "$W4/.claude/worktrees/wt" && env PATH="$NOGIT" CLAUDE_PROJECT_DIR="$W4/.claude/worktrees/wt" TMPDIR="${TMPDIR:-/tmp}" bash "$HOOK") 2>/dev/null)
  [ -z "$OUT2" ] && ok "  the second call in the session is deduplicated (by the git-dir stamp)" || bad "  the second call repeated the notice"
else
  info "skip: git worktree add failed here"
fi
rm -rf "${TMPDIR:-/tmp}/claude-hook-notices/$SID"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0

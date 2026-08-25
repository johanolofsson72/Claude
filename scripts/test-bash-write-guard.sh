#!/usr/bin/env bash
# Harness for the two Bash enforcement layers (row H7b).
#
# WHY THIS EXISTS
# ---------------
# The three pipeline guards were wired to Edit|Write|MultiEdit and to nothing else, so for 18 days the
# answer to "may I write this source file?" depended on which tool was asked. 56 register rows shipped
# through the shell while every Edit was denied. This harness is what stops that from being true again.
#
# BOTH LAYERS, AND THE SEAM BETWEEN THEM
# --------------------------------------
# The interesting fixture is not "the pre-layer blocks sed -i" — it is `bound`, which proves the pre-layer
# CANNOT see a python-heredoc write and that the post-layer catches exactly that. A declared coverage bound
# with no executable demonstration is prose, and prose is what failed in this row's own subject.
#
# Usage:
#   bash scripts/test-bash-write-guard.sh            # all fixtures
#   bash scripts/test-bash-write-guard.sh bound      # one fixture
#
# Exit: 0 all expectations met · 1 an expectation failed · 2 the harness broke.
# Three states on purpose (spec 007l): "the suite is red" and "the harness fell over" are different facts.
#
# Scenario map: SC-1437..SC-1442 (row H7b) and SC-1678..SC-1682 (row H7t) in specs/SCENARIOS.md.

set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PRE="$SCRIPT_DIR/bash-write-guard-hook.sh"
POST="$SCRIPT_DIR/bash-write-detect-hook.sh"
for h in "$PRE" "$POST"; do
  [ -f "$h" ] || { echo "HARNESS ERROR: hook not found: $h" >&2; exit 2; }
done
command -v jq >/dev/null 2>&1 || { echo "HARNESS ERROR: jq is required" >&2; exit 2; }

FILTER="${1:-}"
want() { [ -z "$FILTER" ] || [ "$FILTER" = "$1" ]; }

WORK=$(mktemp -d 2>/dev/null) || { echo "HARNESS ERROR: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

CHECKS=0
FAILURES=0
ok()  { CHECKS=$((CHECKS + 1)); echo "  ✓ $1"; }
bad() { CHECKS=$((CHECKS + 1)); FAILURES=$((FAILURES + 1)); echo "  ✗ $1"; }

# A fixture project whose ACTIVE register row has no artifacts at all, so all three pipeline guards deny
# a source-file write. That is the precondition; everything below tests whether the shell can dodge it.
make_fixture() {
  local name="$1"
  local root="$WORK/$name"
  mkdir -p "$root/.git" "$root/src" "$root/scripts" "$root/specs" "$root/.claude"
  : > "$root/package.json"
  {
    echo "# Spec register"; echo; echo "## Specs"; echo
    echo '- [x] 007 — preview — full track — done'
    echo '- [/] 007z — active-spec — full track — IN PROGRESS, no artifacts at all'
  } > "$root/specs/INDEX.md"
  echo "class App {}" > "$root/src/App.cs"
  echo "notes" > "$root/notes.md"
  printf '%s' "$root"
}

# A fixture root that also carries the sync script, so scripts/core-machinery-guard-hook.sh can ask
# --is-core about it (row H7t). Without the sync present that guard exits early by design — "no sync, so
# no owner to defer to" — which would make every CORE assertion below pass for the wrong reason.
#
# The real script is copied rather than stubbed: the CORE lists ARE the thing under test, and a stub with
# a hand-written list here would be the fourth copy of exactly the policy this row refuses to duplicate.
make_core_fixture() {
  local name="$1" root
  root=$(make_fixture "$name")
  cp "$SCRIPT_DIR/template-autosync.sh" "$root/scripts/template-autosync.sh" 2>/dev/null || return 1
  mkdir -p "$root/.claude/rules"
  echo "# a core rule" > "$root/.claude/rules/spec-register.md"
  echo "#!/bin/bash" > "$root/scripts/thing.sh"
  printf '%s' "$root"
}

# Run the PreToolUse layer. Echoes "ALLOW" or "DENY <first line of reason>".
run_pre() {
  local root="$1" cmd="$2"
  local out
  out=$(jq -n --arg c "$cmd" --arg w "$root" '{tool_input:{command:$c}, cwd:$w}' \
        | CLAUDE_PROJECT_DIR="$root" bash "$PRE" 2>/dev/null)
  if [ -z "$out" ]; then printf 'ALLOW'; return 0; fi
  # The whole reason is flattened onto one line: the decision is on line 1 but the target path is on
  # line 3, and an assertion that can only see line 1 would have passed a guard that named the wrong file.
  printf '%s' "$out" | python3 -c '
import json,sys
try:
    h = json.load(sys.stdin).get("hookSpecificOutput", {})
    r = " ".join(h.get("permissionDecisionReason","").split())
    print(h.get("permissionDecision","?").upper() + " " + r)
except Exception:
    print("UNPARSEABLE")' 2>/dev/null || printf 'UNPARSEABLE'
}

# run_pre with ALLOW_CORE_MACHINERY_EDIT=1 in the environment. The override is the only sanctioned way
# past the CORE guard, and it is the half that is easy to lose: a delegation that ignored it would read as
# "stricter", and would break the one path spec 007al needed to restore work a sync had deleted.
run_pre_override() {
  local root="$1" cmd="$2" out
  out=$(jq -n --arg c "$cmd" --arg w "$root" '{tool_input:{command:$c}, cwd:$w}' \
        | CLAUDE_PROJECT_DIR="$root" ALLOW_CORE_MACHINERY_EDIT=1 bash "$PRE" 2>/dev/null)
  if [ -z "$out" ]; then printf 'ALLOW'; return 0; fi
  printf '%s' "$out" | python3 -c '
import json,sys
try:
    h = json.load(sys.stdin).get("hookSpecificOutput", {})
    if not h.get("permissionDecision"):
        print("ALLOW"); raise SystemExit
    r = " ".join(h.get("permissionDecisionReason","").split())
    print(h.get("permissionDecision","?").upper() + " " + r)
except Exception:
    print("UNPARSEABLE")' 2>/dev/null || printf 'UNPARSEABLE'
}

# Full reason text of the PreToolUse layer (for the secrets assertion).
run_pre_raw() {
  local root="$1" cmd="$2"
  jq -n --arg c "$cmd" --arg w "$root" '{tool_input:{command:$c}, cwd:$w}' \
    | CLAUDE_PROJECT_DIR="$root" bash "$PRE" 2>/dev/null
}

# Run the PostToolUse layer. Echoes "BLOCK <reason+systemMessage flattened>" or "SILENT".
#
# It reports through JSON rather than exit 2 on purpose (FR-016): exit 2 hands stderr to the model alone,
# and a detection only the model sees is one that can be summarised away. So the harness asserts on the
# decision AND on both audiences being addressed, not on an exit code.
run_post() {
  local root="$1" cmd="$2" out
  out=$(jq -n --arg c "$cmd" --arg w "$root" '{tool_input:{command:$c}, cwd:$w}' \
        | CLAUDE_PROJECT_DIR="$root" bash "$POST" 2>/dev/null)
  if [ -z "$out" ]; then printf 'SILENT'; return 0; fi
  printf '%s' "$out" | python3 -c '
import json,sys
try:
    d = json.load(sys.stdin)
    if d.get("decision") != "block":
        print("SILENT"); raise SystemExit
    body = " ".join((d.get("reason","") + " " + d.get("systemMessage","")).split())
    print(("BLOCK+MSG " if d.get("systemMessage") else "BLOCK-NOMSG ") + body)
except Exception:
    print("UNPARSEABLE")' 2>/dev/null || printf 'UNPARSEABLE'
}

expect_block()  { case "$2" in BLOCK+MSG*) ok "$1" ;;
                               BLOCK-NOMSG*) bad "$1 — blocked but emitted no systemMessage: the developer never sees it (FR-016)" ;;
                               *) bad "$1 — expected a block, got: $(printf '%s' "$2" | cut -c1-90)" ;; esac; }
expect_silent() { case "$2" in SILENT) ok "$1" ;; *) bad "$1 — expected silence, got: $(printf '%s' "$2" | cut -c1-90)" ;; esac; }

expect_deny() {
  local label="$1" actual="$2" needle="${3:-}"
  case "$actual" in
    DENY*)
      if [ -z "$needle" ]; then ok "$label — DENY"; return; fi
      case "$actual" in *"$needle"*) ok "$label — DENY (names $needle)" ;;
                        *) bad "$label — denied but did not name \"$needle\": $(printf '%s' "$actual" | cut -c1-90)" ;; esac ;;
    *) bad "$label — expected DENY, got: $(printf '%s' "$actual" | cut -c1-90)" ;;
  esac
}

expect_allow() {
  local label="$1" actual="$2"
  if [ "$actual" = "ALLOW" ]; then ok "$label — ALLOW"; else bad "$label — expected ALLOW, got: $(printf '%s' "$actual" | cut -c1-90)"; fi
}

# --------------------------------------------------------------- FORMS (SC-1437)
if want forms; then
  echo "FIXTURE forms — the six shell write forms the pre-layer claims, against a gated source file"
  ROOT=$(make_fixture forms)
  expect_deny "sed -i"       "$(run_pre "$ROOT" "sed -i '' 's/a/b/' src/App.cs")"        "App.cs"
  expect_deny "redirect >"   "$(run_pre "$ROOT" "echo 'class App {}' > src/App.cs")"     "App.cs"
  expect_deny "append >>"    "$(run_pre "$ROOT" "echo x >> src/App.cs")"                 "App.cs"
  expect_deny "heredoc"      "$(run_pre "$ROOT" "$(printf 'cat > src/App.cs <<%sEOF%s\nclass App {}\nEOF\n' "'" "'")")" "App.cs"
  expect_deny "tee"          "$(run_pre "$ROOT" "echo x | tee src/App.cs")"              "App.cs"
  expect_deny "cp"           "$(run_pre "$ROOT" "cp /tmp/other.cs src/App.cs")"          "App.cs"
  expect_deny "mv"           "$(run_pre "$ROOT" "mv /tmp/other.cs src/App.cs")"          "App.cs"
  # The reason must be the guard's own, passed through — not a second opinion written here.
  RAW=$(run_pre_raw "$ROOT" "sed -i '' 's/a/b/' src/App.cs")
  case "$RAW" in
    *"pipeline phases incomplete"*|*"cannot determine which spec is active"*|*"no spec register"*)
      ok "the delegated guard's own reason is passed through" ;;
    *) bad "the deny reason is not the guard's — the layer is deciding instead of delegating" ;;
  esac
fi

# --------------------------------------------------------------- QUIET (SC-1439)
if want quiet; then
  echo "FIXTURE quiet — a read-only command, an allowlisted path, a non-source extension: no output"
  ROOT=$(make_fixture quiet)
  expect_allow "read-only grep"        "$(run_pre "$ROOT" "grep -rn TODO src/")"
  expect_allow "read-only build"       "$(run_pre "$ROOT" "dotnet build 2>&1 | tail -5")"
  expect_allow "write under scripts/"  "$(run_pre "$ROOT" "echo x > scripts/thing.sh")"
  expect_allow "write under specs/"    "$(run_pre "$ROOT" "echo x > specs/INDEX.md")"
  expect_allow "non-source extension"  "$(run_pre "$ROOT" "echo x > notes.md")"
  expect_allow "redirect to /dev/null" "$(run_pre "$ROOT" "ls src/ > /dev/null")"
  expect_allow "fd duplication only"   "$(run_pre "$ROOT" "make all 2>&1")"
fi

# --------------------------------------------------------------- SECRETS (SC-1442)
if want secrets; then
  echo "FIXTURE secrets — neither layer may echo the command string"
  ROOT=$(make_fixture secrets)
  NEEDLE="hunter2-do-not-print-me"
  RAW=$(run_pre_raw "$ROOT" "sed -i '' 's/x/$NEEDLE/' src/App.cs")
  case "$RAW" in
    *"$NEEDLE"*) bad "pre-layer leaked the command string into its deny reason" ;;
    *)           ok  "pre-layer output holds no part of the command string" ;;
  esac
  : > "$ROOT/.claude/.bash-write-marker"
  sleep 1
  echo "changed" > "$ROOT/src/App.cs"
  RAW=$(run_post "$ROOT" "python3 -c \"open('src/App.cs','w').write('$NEEDLE')\"")
  case "$RAW" in
    *"$NEEDLE"*) bad "post-layer leaked the command string into its report" ;;
    *)           ok  "post-layer output holds no part of the command string" ;;
  esac
fi

# --------------------------------------------------------------- CAP (FR-006a)
if want cap; then
  echo "FIXTURE cap — more distinct write groups than the layer will check unverified"
  ROOT=$(make_fixture cap)
  CMD=""
  i=1
  while [ "$i" -le 9 ]; do
    mkdir -p "$ROOT/src/d$i"
    CMD="${CMD}echo x > src/d$i/F.cs; "
    i=$((i + 1))
  done
  expect_deny "nine groups" "$(run_pre "$ROOT" "$CMD")" "cap"
  # ...and eight is still checked properly rather than waved through.
  CMD=""
  i=1
  while [ "$i" -le 8 ]; do CMD="${CMD}echo x > src/d$i/F.cs; "; i=$((i + 1)); done
  expect_deny "eight groups (at the cap, still delegated)" "$(run_pre "$ROOT" "$CMD")" "F.cs"
fi

# --------------------------------------------------------------- BOUND (SC-1438 + FR-010)
# The fixture this whole design turns on. The pre-layer is a string parser and CANNOT see these writes;
# the post-layer must. If this fixture ever goes green on the pre-layer arm, the bound in the header is
# wrong. If it ever goes red on the post-layer arm, the coverage claim is wrong.
if want bound; then
  echo "FIXTURE bound — writes no string parser can see: pre-layer MISSES (declared), post-layer CATCHES"
  ROOT=$(make_fixture bound)

  PY_CMD="python3 - <<'PY'
open('src/App.cs','w').write('mutated')
PY"
  expect_allow "pre-layer cannot see a python-heredoc write (the declared bound)" "$(run_pre "$ROOT" "$PY_CMD")"

  # The pre-layer stamped the marker on its way past — which is exactly what makes the next step possible.
  [ -f "$ROOT/.claude/.bash-write-marker" ] && ok "pre-layer stamped the before-marker even while allowing" \
    || bad "pre-layer allowed without stamping a marker — the post-layer is now blind"

  sleep 1
  printf 'mutated\n' > "$ROOT/src/App.cs"        # what the python heredoc would have done
  OUT=$(run_post "$ROOT" "$PY_CMD")
  expect_block "post-layer caught it on the outcome, and told the developer as well as the model" "$OUT"
  case "$OUT" in *"src/App.cs"*) ok "post-layer names the changed file" ;;
                 *) bad "post-layer blocked without naming the file" ;; esac

  # eval — same story, different spelling.
  ROOT=$(make_fixture bound2)
  EVAL_CMD='CMD="sed -i \"\" s/a/b/ src/App.cs"; eval "$CMD"'
  expect_allow "pre-layer cannot see an eval-assembled write" "$(run_pre "$ROOT" "$EVAL_CMD")"
  sleep 1
  printf 'mutated\n' > "$ROOT/src/App.cs"
  OUT=$(run_post "$ROOT" "$EVAL_CMD")
  expect_block "post-layer caught the eval write" "$OUT"
fi

# --------------------------------------------------------------- ESCAPE (SC-1440)
if want escape; then
  echo "FIXTURE escape — the post-layer blocks once per finding, then lets the session move"
  ROOT=$(make_fixture escape)
  : > "$ROOT/.claude/.bash-write-marker"; sleep 1
  printf 'mutated\n' > "$ROOT/src/App.cs"
  OUT=$(run_post "$ROOT" "true")
  expect_block "first encounter blocks" "$OUT"

  : > "$ROOT/.claude/.bash-write-marker"; sleep 1
  printf 'mutated again\n' > "$ROOT/src/App.cs"
  OUT=$(run_post "$ROOT" "true")
  expect_silent "same finding again is silent — the session is not trapped" "$OUT"

  mkdir -p "$ROOT/src/other"
  : > "$ROOT/.claude/.bash-write-marker"; sleep 1
  printf 'new\n' > "$ROOT/src/other/New.cs"
  OUT=$(run_post "$ROOT" "true")
  expect_block "a DIFFERENT finding arms it again" "$OUT"
fi

# --------------------------------------------------------------- EXEMPT (SC-1441)
if want exempt; then
  echo "FIXTURE exempt — tree-moving git verbs are exempt; content-carrying ones are not"
  for verb in "git checkout -- ." "git stash pop" "git pull --rebase" "git reset --hard HEAD"; do
    ROOT=$(make_fixture "exempt$(printf '%s' "$verb" | tr -cd 'a-z')")
    : > "$ROOT/.claude/.bash-write-marker"; sleep 1
    printf 'mutated\n' > "$ROOT/src/App.cs"
    OUT=$(run_post "$ROOT" "$verb")
    expect_silent "exempt: $verb" "$OUT"
  done
  for verb in "git apply /tmp/p.patch" "git cherry-pick abc123"; do
    ROOT=$(make_fixture "notexempt$(printf '%s' "$verb" | tr -cd 'a-z')")
    : > "$ROOT/.claude/.bash-write-marker"; sleep 1
    printf 'mutated\n' > "$ROOT/src/App.cs"
    OUT=$(run_post "$ROOT" "$verb")
    expect_block "NOT exempt: $verb" "$OUT"
  done
fi

# --------------------------------------------------------------- NOMARKER
if want nomarker; then
  echo "FIXTURE nomarker — with no before-time the post-layer says nothing rather than inventing a finding"
  ROOT=$(make_fixture nomarker)
  printf 'mutated\n' > "$ROOT/src/App.cs"
  OUT=$(run_post "$ROOT" "true")
  expect_silent "no marker → silent" "$OUT"
fi

# --------------------------------------------------------------- CORE (SC-1678..SC-1681, row H7t)
if want core; then
  echo "FIXTURE core — the CORE-ownership question is asked on the Bash route too, not only on Edit"
  if ! ROOT=$(make_core_fixture core); then
    bad "harness could not stage the sync script into the fixture"
  else
    # SC-1678 — the defect this fixture exists for. Before H7t: Edit denied, sed -i was silent.
    expect_deny "sed -i against a CORE script" \
      "$(run_pre "$ROOT" "sed -i '' 's/a/b/' scripts/template-autosync.sh")" "core-machinery-guard-hook.sh"
    expect_deny "redirect against a CORE script" \
      "$(run_pre "$ROOT" "echo x > scripts/spec_active.py")" "core-machinery-guard-hook.sh"
    expect_deny "redirect against a CORE rule" \
      "$(run_pre "$ROOT" "echo x > .claude/rules/spec-register.md")" "core-machinery-guard-hook.sh"

    # SC-1679 — without this the whole fixture is compatible with a guard that denies everything under
    # scripts/, which would break the three pipeline guards' deliberate scripts/** exemption.
    expect_allow "sed -i against a NON-core script under scripts/" \
      "$(run_pre "$ROOT" "sed -i '' 's/a/b/' scripts/thing.sh")"
    expect_allow "redirect to a new script nobody owns" \
      "$(run_pre "$ROOT" "echo x > scripts/brand-new-thing.sh")"

    # SC-1680 — the override. Named in the deny text, so it has to work on this route as well.
    expect_allow "ALLOW_CORE_MACHINERY_EDIT=1 on the same CORE write" \
      "$(run_pre_override "$ROOT" "sed -i '' 's/a/b/' scripts/template-autosync.sh")"

    # SC-1681 — the provenance line must name the right gate. A CORE file under scripts/ is not "a source
    # file", and the pipeline guards never see it, so the pipeline header would send the reader to run a
    # pipeline phase that has nothing to do with why they were stopped.
    RAW=$(run_pre_raw "$ROOT" "sed -i '' 's/a/b/' scripts/template-autosync.sh")
    case "$RAW" in
      *"a file the TEMPLATE owns"*) ok "the provenance line names template ownership, not the pipeline" ;;
      *) bad "the CORE deny wears the pipeline guard's header — it names the wrong gate" ;;
    esac
    case "$RAW" in
      *"a source file the pipeline guard denies"*)
        bad "the CORE deny still carries the pipeline header text" ;;
      *) ok "the pipeline header does not appear on a CORE deny" ;;
    esac
    # The delegate's own words, passed through rather than restated here.
    case "$RAW" in
      *"is not this project's file to edit"*) ok "the CORE guard's own reason is passed through verbatim" ;;
      *) bad "the CORE reason is not the guard's — the layer is deciding instead of delegating" ;;
    esac
    # Secrets (FR-006) holds on this arm too, not just on the pipeline arm.
    NEEDLE="hunter2-core-do-not-print-me"
    RAW2=$(run_pre_raw "$ROOT" "sed -i '' 's/x/$NEEDLE/' scripts/template-autosync.sh")
    case "$RAW2" in
      *"$NEEDLE"*) bad "the CORE arm leaked the command string into its deny reason" ;;
      *)           ok  "the CORE arm's output holds no part of the command string" ;;
    esac
  fi
fi

# ------------------------------------------------- FALSIFICATION (SC-1682, row H7t)
#
# Everything above is compatible with a guard that was already denying for some other reason. This block
# removes the one delegate under test and demands that the suite notices. A gate that is green both with
# and without its fix measures nothing — which is the whole subject of the row this fixture belongs to.
#
# The mutant runs from its OWN directory with every sibling guard copied beside it, so HOOK_DIR resolves
# and the ONLY difference between control and mutant is the name in the delegation list. Running the
# mutant from $WORK with no siblings would "pass" by finding no guards at all.
if want falsify; then
  echo "== falsification: removing the CORE delegate must turn this fixture red =="
  if ! ROOT=$(make_core_fixture falsify); then
    bad "harness could not stage the sync script into the fixture"
  else
    MUT="$WORK/mutant"
    mkdir -p "$MUT"
    for f in bash_write_targets.py core-machinery-guard-hook.sh spec-register-guard-hook.sh \
             pipeline-state-guard-hook.sh spec-interview-guard-hook.sh; do
      cp "$SCRIPT_DIR/$f" "$MUT/$f" 2>/dev/null || true
    done
    cp "$PRE" "$MUT/control.sh"
    sed 's/for guard in core-machinery-guard-hook\.sh /for guard in /' "$PRE" > "$MUT/mutant.sh"
    if cmp -s "$MUT/control.sh" "$MUT/mutant.sh"; then
      bad "the mutation changed nothing — the delegation list is not written the way this block expects"
    else
      PAYLOAD=$(jq -n --arg c "sed -i '' 's/a/b/' scripts/template-autosync.sh" --arg w "$ROOT" \
                  '{tool_input:{command:$c}, cwd:$w}')
      CTRL=$(printf '%s' "$PAYLOAD" | CLAUDE_PROJECT_DIR="$ROOT" bash "$MUT/control.sh" 2>/dev/null)
      MUTO=$(printf '%s' "$PAYLOAD" | CLAUDE_PROJECT_DIR="$ROOT" bash "$MUT/mutant.sh" 2>/dev/null)
      if [ -n "$CTRL" ]; then ok "control (delegate present, copied tree) still denies"
      else bad "control did not deny from the copied tree — the falsification proves nothing"; fi
      if [ -z "$MUTO" ]; then ok "mutant (delegate removed) goes silent — the delegation is load-bearing"
      else bad "mutant still denies without the CORE delegate: this fixture would pass without the fix"; fi
    fi
  fi
fi

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "PASS — $CHECKS/$CHECKS expectations met"
  exit 0
fi
echo "FAIL — $FAILURES of $CHECKS expectations missed"
exit 1

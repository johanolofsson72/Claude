#!/usr/bin/env bash
. "$(dirname -- "$0")/self-test-env.sh" || exit 1
# test-developer-answers.sh — a Confirmed line needs the developer's own answer (spec 088 R4, R5), and
# only a click on Confirm, to a question that showed every case, is one (spec 091 R8).
#
#   088-AC-4  --confirm with a quote no recorded answer matches, or one whose question did not show
#             the digest, exits 3 and writes nothing; after the hook records that answer for a question
#             showing the digest, the same --confirm writes the Confirmed line
#   091-AC-5  No to a question that shows the digest, or Confirm to one that leaves out a case, binds
#             nothing; Confirm to the --question text confirms
#
# The hook is run with the payload Claude Code sends at PostToolUse (shape measured 2026-10-01:
# tool_response {questions, answers}, answers keyed by question text). The store is read back to prove
# hashes only. A sabotage arm removes the binding check and requires the forged quote to be written.
#
# Exit 0 = every assertion held. Exit 1 = a real failure.

set -u

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
HOOK="$SELF_DIR/developer-answers-hook.sh"
HELPER="$SELF_DIR/acceptance-cases.sh"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok    %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$*"; }
expect() { [ "$3" = "$2" ] && ok "$1" || bad "$1 (want $2, got $3)"; }

command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required"; exit 1; }

WORK=$(mktemp -d 2>/dev/null || mktemp -d -t devwords)
WORK=$(cd -P "$WORK" && pwd)
trap 'rm -rf "$WORK"' EXIT

P="$WORK/proj"; D="$P/specs/001-x"
mkdir -p "$D"; git init -q "$P"
cat > "$D/acceptance.md" <<'EOF'
# Acceptance cases — 001-x

## AC-1 — one
**Given** a
**When** b
**Then** c

## AC-2 — two
**Given** a
**When** b
**Then** d

## AC-3 — three
**Given** a
**When** b
**Then** e
EOF
DIG=$(bash "$HELPER" --digest "$D")
STORE="$P/.git/claude-developer-words"

# answered <question> <answer> [extra json for tool_response] — run the hook as PostToolUse does
answered() {
  jq -cn --arg q "$1" --arg a "$2" --arg w "$P" \
    '{hook_event_name:"PostToolUse",tool_name:"AskUserQuestion",cwd:$w,
      tool_input:{questions:[{question:$q,header:"h",multiSelect:false,options:[{label:$a,description:"d"},{label:"No",description:"d"}]}],answers:{($q):$a}},
      tool_response:{questions:[{question:$q}],answers:{($q):$a}}}' \
    | CLAUDE_PROJECT_DIR="$P" bash "$HOOK"
}
confirm() { OUT=$(bash "$HELPER" --confirm "$D" --quote "$1" 2>&1); RC=$?; }
lines() { [ -f "$STORE" ] && grep -c '' "$STORE" || echo 0; }

Q=$(bash "$HELPER" --question "$D")
sha() { printf '%s' "$1" | python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.read().encode()).hexdigest())'; }

printf '\n[R5] no answer recorded: refused  (088-AC-4)\n'
confirm "Confirm"
expect "088-AC-4 no store: exit 3" 3 "$RC"
case "$OUT" in *"$DIG"*) ok "  the refusal names the digest to show" ;; *) bad "  the refusal does not name the digest" ;; esac
case "$OUT" in *"--question"*) ok "  the refusal says to ask with --question" ;; *) bad "  the refusal does not name --question" ;; esac
expect "088-AC-4 nothing written" 0 "$(grep -c 'Confirmed:' "$D/acceptance.md")"

printf '\n[R8] only Confirm, to a question showing every case, binds the digest  (091-AC-5)\n'
answered "Unrelated: may I delete the cache? (digest $DIG)" "No"
confirm "No"
expect "091-AC-5 No to a question that shows the digest: exit 3" 3 "$RC"
QSHORT=$(printf '%s\n' "$Q" | awk '/^AC-3 /{skip=1} /^$/{skip=0} !skip')
answered "$QSHORT" "Confirm"
confirm "Confirm"
expect "091-AC-5 Confirm to a question that leaves out a case: exit 3" 3 "$RC"
QTITLES=$(printf '%s\n' "$Q" | grep -v '^Given\|^When\|^Then')
answered "$QTITLES" "Confirm"
confirm "Confirm"
expect "R8 Confirm to a question showing only the titles: exit 3" 3 "$RC"
answered "$Q" "Confirmed as written"
confirm "Confirmed as written"
expect "R8 a typed answer to the full question confirms nothing: exit 3" 3 "$RC"
jq -cn --arg q "$Q" --arg w "$P" \
  '{tool_name:"AskUserQuestion",cwd:$w,tool_input:{questions:[{question:$q}],answers:{($q):"Confirm"}},tool_response:{questions:[{question:$q}]}}' \
  | CLAUDE_PROJECT_DIR="$P" bash "$HOOK"
confirm "Confirm"
expect "A8 an answer only in tool_input (what the agent sent) binds nothing: exit 3" 3 "$RC"
answered "Shall I proceed?" "Yes, go ahead"
confirm "Yes, go ahead"
expect "088-AC-4 an answer whose question lacked the digest: exit 3" 3 "$RC"
answered "Cases (digest ffffffffffff) ok?" "Confirm"
confirm "Confirm"
expect "an answer to a question showing another digest: exit 3" 3 "$RC"
expect "088-AC-4 still nothing written" 0 "$(grep -c 'Confirmed:' "$D/acceptance.md")"

printf '\n[R4] the hook records hashes and the digests a Confirm bound\n'
N0=$(lines)
answered "$Q" "Confirm"; HRC=$?
expect "the hook exits 0" 0 "$HRC"
expect "one more line recorded" "$((N0 + 1))" "$(lines)"
L=$(tail -1 "$STORE")
case "$L" in *" $(sha Confirm) $DIG") ok "the line is <epoch> <sha256(answer)> <digest>" ;; *) bad "line shape: $L" ;; esac
case "$(cat "$STORE")" in *"Confirm"*|*"Acceptance cases"*) bad "plaintext on disk" ;; *) ok "no plaintext answer or question on disk" ;; esac
expect "the store is private (0600)" 600 "$(python3 -c 'import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777)[2:])' "$STORE")"

printf '\n[R5] the matching answer confirms  (088-AC-4, 091-AC-5)\n'
confirm "Confirm, and also AC-6"
expect "088-AC-4 a quote no answer matches: exit 3" 3 "$RC"
confirm "  Confirm
"
expect "091-AC-5 Confirm to the --question text confirms (whitespace-collapsed): exit 0" 0 "$RC"
expect "088-AC-4 one Confirmed line written" 1 "$(grep -c "^\*\*Confirmed:\*\* .* · $DIG — \"Confirm\"\$" "$D/acceptance.md")"
bash "$HELPER" --check "$D" >/dev/null 2>&1; expect "it checks clean" 0 $?
confirm "confirm"
expect "case is kept: a different-case quote does not match" 3 "$RC"
answered "$Q" "CONFIRM"
expect "R8 the label is compared ignoring case: CONFIRM binds" "$(sha CONFIRM) $DIG" "$(tail -1 "$STORE" | cut -d' ' -f2-)"
QNODASH=$(printf '%s\n' "$Q" | sed 's/^\(AC-[0-9]*\) — /\1 - /')
answered "$QNODASH" "Confirm"
expect "R8 any edit of the --question text (a hyphen for the em dash) binds nothing" "" "$(tail -1 "$STORE" | cut -d' ' -f3)"
answered "$Q
Extra words the agent appended." "Confirm"
expect "R8 text appended to the --question text binds nothing" "" "$(tail -1 "$STORE" | cut -d' ' -f3)"
QWS=$(printf '%s\n' "$Q" | tr '\n' ' ')
answered "$QWS" "Confirm"
expect "R8 the same text with other whitespace still binds" "$DIG" "$(tail -1 "$STORE" | cut -d' ' -f3)"

printf '\n[R5] edited cases need a new answer\n'
sed -i.bak 's/\*\*Then\*\* e/**Then** e2/' "$D/acceptance.md"; rm -f "$D/acceptance.md.bak"
confirm "Confirm"
expect "after a case edit the old answer no longer binds (digest moved): exit 3" 3 "$RC"
DIG2=$(bash "$HELPER" --digest "$D")
Q2=$(bash "$HELPER" --question "$D")
answered "$Q2" "Confirm"
confirm "Confirm"; expect "a new answer for the new digest confirms" 0 "$RC"

printf '\n[R4] the hook is quiet and harmless on what it cannot use\n'
N0=$(lines)
for junk in 'not json' '[]' '{}' '{"tool_name":"AskUserQuestion","tool_response":"a string"}' \
            '{"tool_name":"AskUserQuestion","tool_response":{"answers":{"q (digest 0123456789ab)":""}}}' \
            '{"tool_name":"AskUserQuestion","tool_response":{"answers":{"q":7}}}'; do
  OUTH=$(printf '%s' "$junk" | CLAUDE_PROJECT_DIR="$P" bash "$HOOK" 2>&1); RCH=$?
  [ "$RCH" -eq 0 ] && [ -z "$OUTH" ] || bad "junk payload: rc $RCH, output '$OUTH'"
done
expect "six unusable payloads: exit 0, no output, nothing recorded" "$N0" "$(lines)"
answered "Cases (digest abcdef012345)" "Confirm"
expect "a token that is no on-disk digest is not kept" "" "$(tail -1 "$STORE" | cut -d' ' -f3)"
jq -cn --arg w "$P" --arg q "$Q2" '{tool_name:"AskUserQuestion",cwd:$w,tool_response:{answers:{($q):["a","b"]}}}' \
  | CLAUDE_PROJECT_DIR="$P" bash "$HOOK"
case "$(tail -1 "$STORE")" in *" $(sha 'a, b')") ok "a multi-select answer is recorded as its labels joined, binding nothing" ;; *) bad "multi: $(tail -1 "$STORE")" ;; esac
NOGIT="$WORK/nogit"; mkdir -p "$NOGIT"
answered_nogit=$(jq -cn '{tool_name:"AskUserQuestion",tool_response:{answers:{"q":"a"}}}' | CLAUDE_PROJECT_DIR="$NOGIT" bash "$HOOK" 2>&1; echo "rc=$?")
expect "outside a git repository: exit 0, nothing written" "rc=0" "$answered_nogit"
SUB="$P/sub"; mkdir -p "$SUB"
jq -cn --arg w "$SUB" --arg q "$Q2" '{tool_name:"AskUserQuestion",cwd:$w,tool_response:{answers:{($q):"Confirm"}}}' | env -u CLAUDE_PROJECT_DIR bash "$HOOK"
case "$(tail -1 "$STORE")" in *" $DIG2") ok "no CLAUDE_PROJECT_DIR: the payload cwd finds the repository" ;; *) bad "cwd fallback" ;; esac

printf '\n[R4] the store keeps its last 500 lines\n'
python3 - "$STORE" <<'PY'
import sys
with open(sys.argv[1], "a") as f:
    for i in range(600):
        f.write("1 %064x 0123456789ab\n" % i)
PY
answered "Last (digest $DIG2)" "Latest"
expect "capped at 500" 500 "$(lines)"
grep -q " $(sha Latest)" "$STORE" && ok "the newest line survives the cap" || bad "newest line lost"

printf '\n[R4] /tla GAP-1: a digest precomputed for text not on disk binds nothing\n'
cp "$D/acceptance.md" "$WORK/v2.md"
sed 's/\*\*Then\*\* e2/**Then** e3-the-text-nobody-saw/' "$WORK/v2.md" > "$WORK/v1.md"
cp "$WORK/v1.md" "$D/acceptance.md"; QV1=$(bash "$HELPER" --question "$D"); cp "$WORK/v2.md" "$D/acceptance.md"
answered "$QV1" "Confirm"
cp "$WORK/v1.md" "$D/acceptance.md"
confirm "Confirm"
expect "GAP-1 the precomputed digest was not recorded, so --confirm refuses (exit 3)" 3 "$RC"
cp "$WORK/v2.md" "$D/acceptance.md"

printf '\n[R5] sabotage: without the binding check a forged quote is written\n'
MUT="$WORK/mut"; mkdir -p "$MUT"; cp "$SELF_DIR"/acceptance-cases.sh "$SELF_DIR"/acceptance_cases.py "$MUT"/
python3 - "$MUT/acceptance_cases.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = 'if not answer_bound(spec_dir, quote, parsed["digest"]):'
assert old in s, "sabotage target not found"
open(p, "w").write(s.replace(old, "if False:"))
PY
bash "$MUT/acceptance-cases.sh" --confirm "$D" --quote "I never said this" >/dev/null 2>&1
expect "sabotage: the mutant writes an invented quote" 0 $?

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

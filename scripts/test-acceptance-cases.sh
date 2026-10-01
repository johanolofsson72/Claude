#!/usr/bin/env bash
# test-acceptance-cases.sh — the developer-confirmed acceptance-case gate (spec 080).
#
# A full or hardened spec owes 3-5 Given/When/Then cases in <spec-dir>/acceptance.md, confirmed by
# the developer and pinned by a digest; each case is named by a test (<spec-id>-AC-<n>) before
# production source unlocks. The gate lives in spec-interview-guard-hook.sh; the parser, digest and
# coverage scan in acceptance_cases.py; the helper in acceptance-cases.sh.
#
# The first five blocks are 080's own acceptance cases, written before the code they test.
#
# Exit 0 = every assertion held. Exit 1 = a real failure.

set -u

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SELF_DIR/hook-verdict.sh"
GUARD="$SELF_DIR/spec-interview-guard-hook.sh"
HELPER="$SELF_DIR/acceptance-cases.sh"
BASH_GUARD="$SELF_DIR/bash-write-guard-hook.sh"

FAILURES=0
PASSES=0
TMP=$(mktemp -d)
trap 'chmod -R u+rw "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT

ok()   { printf '  ✓ %s\n' "$1"; PASSES=$((PASSES + 1)); }
fail() { printf '  ✗ %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

# ---------------------------------------------------------------------------------------- fixtures

# mk_project <name> <id> <track field> -> prints the project root.
# A git repo with a language marker, a register whose only row is in progress, and a spec dir whose
# interview already has 15 answers, so the interview half of the guard is satisfied.
mk_project() {
  local name="$1" id="$2" track="$3" root="$TMP/$1"
  mkdir -p "$root/specs/$id-demo" "$root/src" "$root/tests"
  git -C "$root" init -q 2>/dev/null
  echo '{"name":"ac"}' > "$root/package.json"
  printf '# Spec register\n## Specs\n- [/] %s — demo — %s — demo goal\n' "$id" "$track" > "$root/specs/INDEX.md"
  {
    echo "# Spec interview — $id-demo"
    local i=1
    while [ "$i" -le 15 ]; do printf '## Q%s\n**Q:** q\n**A (auto):** recommended answer\n\n' "$i"; i=$((i + 1)); done
  } > "$root/specs/$id-demo/interview.md"
  echo "$root"
}

# write_cases <root> <id> <n> [skip-number] — n well-formed cases; skip-number leaves a gap there.
write_cases() {
  local root="$1" id="$2" n="$3" skip="${4:-0}" i=1 num=1
  {
    echo "# Acceptance cases — $id-demo"
    echo
    while [ "$i" -le "$n" ]; do
      [ "$num" -eq "$skip" ] && num=$((num + 1))
      printf '## AC-%s — case %s\n**Given** state %s\n**When** action %s\n**Then** outcome %s\n\n' "$num" "$num" "$num" "$num" "$num"
      i=$((i + 1)); num=$((num + 1))
    done
  } > "$root/specs/$id-demo/acceptance.md"
}

# commit_spec <root> <id> <date> — commit the spec dir as if it was begun on <date> (YYYY-MM-DD).
commit_spec() {
  ( cd "$1" && git add "specs/$2-demo" >/dev/null 2>&1 \
    && GIT_AUTHOR_DATE="$3T12:00:00" GIT_COMMITTER_DATE="$3T12:00:00" \
       git -c user.name=t -c user.email=t@t commit -qm "spec $2" >/dev/null 2>&1 )
}

# with_artifacts <root> <id> — the pipeline-state guard's artifacts, so a Bash write reaches the
# interview guard instead of stopping at a missing plan.
with_artifacts() {
  local d="$1/specs/$2-demo"
  printf '# spec
## Clarifications
- Q: q → A: a
' > "$d/spec.md"
  printf -- '-- allium: 3
' > "$d/spec.allium"
  printf '# plan
' > "$d/plan.md"
  printf '# tasks
- [ ] T1
' > "$d/tasks.md"
}

confirm() { bash "$HELPER" --confirm "$1/specs/$2-demo" --quote "${3:-Confirmed as written}" >/dev/null 2>&1; }

# guard_out <file> [env assignments...] -> raw hook output for a Write of <file>
guard_out() {
  local file="$1"; shift
  jq -n --arg p "$file" '{tool_name:"Write",tool_input:{file_path:$p,content:"x"}}' \
    | env SPEC_INTERVIEW_MODE=auto "$@" bash "$GUARD" 2>/dev/null
}

# expect <label> <file> <deny|allow> [needle] [env...]
expect() {
  local label="$1" file="$2" want="$3" needle="${4:-}" out verdict
  shift 4 2>/dev/null || shift $#
  out=$(guard_out "$file" "$@")
  verdict=$(hook_verdict "$out")
  if [ "$want" = allow ]; then
    case "$verdict" in none|allow) ok "$label — allow" ;; *) fail "$label — expected allow, got $verdict: $(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' | head -3)" ;; esac
    return
  fi
  if [ "$verdict" != deny ]; then fail "$label — expected deny, got $verdict"; return; fi
  if [ -n "$needle" ] && ! printf '%s' "$out" | jq -e --arg n "$needle" \
      '.hookSpecificOutput.permissionDecisionReason | contains($n)' >/dev/null 2>&1; then
    fail "$label — denied, but the reason does not name \"$needle\""
    return
  fi
  ok "$label — deny${needle:+ (names $needle)}"
}

# ------------------------------------------------------------------- 080's own acceptance cases

echo "080-AC-1 — unconfirmed cases block code"
P=$(mk_project ac1 080 "full track")
write_cases "$P" 080 3
expect "080-AC-1 three cases, no Confirmed line" "$P/src/app.ts" deny "not confirmed"
expect "080-AC-1 the reason says how to ask" "$P/src/app.ts" deny "AskUserQuestion"
rm "$P/specs/080-demo/acceptance.md"
expect "080-AC-1 no acceptance.md at all" "$P/src/app.ts" deny "acceptance.md"

echo "080-AC-2 — editing a confirmed case re-locks code"
P=$(mk_project ac2 080 "full track [hardened]")
write_cases "$P" 080 3
confirm "$P" 080
printf '// 080-AC-1 080-AC-2 080-AC-3\n' > "$P/tests/app.test.ts"
expect "080-AC-2 confirmed and named" "$P/src/app.ts" allow
sed -i.bak 's/^\*\*Then\*\* outcome 2$/**Then** a different outcome/' "$P/specs/080-demo/acceptance.md"
expect "080-AC-2 Then line changed after confirmation" "$P/src/app.ts" deny "digest"
expect "080-AC-2 the reason says the cases changed" "$P/src/app.ts" deny "changed after"
confirm "$P" 080 "yes, the new outcome"
expect "080-AC-2 re-confirmed" "$P/src/app.ts" allow

echo "080-AC-3 — tests come first"
P=$(mk_project ac3 080 "full track")
write_cases "$P" 080 3
confirm "$P" 080
printf '// 080-AC-1\n// 080-AC-2\n' > "$P/tests/app.test.ts"
expect "080-AC-3 a test file is editable" "$P/tests/app.test.ts" allow
P3U=$(mk_project ac3u 080 "full track")
write_cases "$P3U" 080 3
expect "080-AC-3 before confirmation a test file is not editable either" "$P3U/tests/app.test.ts" deny "not confirmed"
expect "080-AC-3 production names the untested case" "$P/src/app.ts" deny "080-AC-3"
printf '// 080-AC-3\n' > "$P/tests/more.test.ts"
expect "080-AC-3 every case named → production" "$P/src/app.ts" allow

echo "080-AC-4 — exempt specs pass"
P=$(mk_project ac4a 080 "light track")
expect "080-AC-4 light row, no acceptance.md" "$P/src/app.ts" allow
P=$(mk_project ac4b 080 "full track")
printf '# tasks\n- [x] T1 done\n- [ ] T2 open\n' > "$P/specs/080-demo/tasks.md"
commit_spec "$P" 080 2026-09-15
expect "080-AC-4 full row begun before 080 landed (ticked task, interview committed 2026-09-15)" "$P/src/app.ts" allow
printf '# tasks\n- [ ] T1 open\n' > "$P/specs/080-demo/tasks.md"
expect "080-AC-4 full row with no ticked task is not exempt" "$P/src/app.ts" deny "acceptance.md"
P=$(mk_project ac4c 080 "full track")
printf '# tasks\n- [x] T001 Initialize package.json\n' > "$P/specs/080-demo/tasks.md"
expect "080-AC-4 a new spec with a ticked setup task (uncommitted) is not exempt" "$P/src/app.ts" deny "acceptance.md"
commit_spec "$P" 080 2026-10-02
expect "080-AC-4 a new spec committed on/after the cutoff is not exempt" "$P/src/app.ts" deny "acceptance.md"
P=$(mk_project ac4d 080 "full track")
write_cases "$P" 080 3
printf '# tasks\n- [x] T1 done\n' > "$P/specs/080-demo/tasks.md"
commit_spec "$P" 080 2026-09-15
expect "080-AC-4 an old spec that has an acceptance.md is held to it" "$P/src/app.ts" deny "not confirmed"

echo "080-AC-5 — band enforced"
P=$(mk_project ac5 080 "full track")
write_cases "$P" 080 2
expect "080-AC-5 two cases" "$P/src/app.ts" deny "2 cases; the band is 3-5"
write_cases "$P" 080 6
expect "080-AC-5 six cases" "$P/src/app.ts" deny "6 cases; the band is 3-5"
write_cases "$P" 080 3 2
expect "080-AC-5 numbering gap AC-1, AC-3, AC-4" "$P/src/app.ts" deny "expected AC-2, found AC-3"

# ------------------------------------------------------------------------------- which specs owe

echo "which rows owe cases"
P=$(mk_project own1 080 "light track [hardened]")
expect "light row tagged [hardened] owes cases" "$P/src/app.ts" deny "acceptance.md"
P=$(mk_project own2 080 "light track [HARDENED]")
expect "the tag is read case-insensitively" "$P/src/app.ts" deny "acceptance.md"
P=$(mk_project own3 080 "spec-only track")
expect "spec-only row" "$P/src/app.ts" allow
P=$(mk_project own4 H3 "checkpoint")
expect "checkpoint row" "$P/src/app.ts" allow
P=$(mk_project own5 080 "full track")
expect "SPEC_ACCEPTANCE=off" "$P/src/app.ts" allow "" SPEC_ACCEPTANCE=off
expect "SPEC_ACCEPTANCE=OFF (case-insensitive)" "$P/src/app.ts" allow "" SPEC_ACCEPTANCE=OFF
expect "SPEC_ACCEPTANCE=no is not off" "$P/src/app.ts" deny "" SPEC_ACCEPTANCE=no
expect "the deny names the off switch" "$P/src/app.ts" deny "SPEC_ACCEPTANCE=off"
sed -i.bak 's/^\*\*A (auto):\*\*/**A:**/' "$P/specs/080-demo/interview.md"
expect "MANUAL interview mode still owes cases (15 human answers)" "$P/src/app.ts" deny "acceptance.md" SPEC_INTERVIEW_MODE=manual
expect "non-source edit passes" "$P/src/data.json" allow
expect "specs/ edit passes (acceptance.md is writable)" "$P/specs/080-demo/acceptance.md" allow

echo "resolver reports hardened"
for tf in "full track:False" "full track [hardened]:True" "light, [Hardened] tag:True" "light track:False"; do
  P=$(mk_project "rsv$RANDOM" 080 "${tf%%:*}")
  got=$(cd "$SELF_DIR" && python3 -c "import sys; from spec_active import resolve; print(resolve(sys.argv[1])['hardened'])" "$P" 2>&1)
  [ "$got" = "${tf##*:}" ] && ok "'${tf%%:*}' → hardened=$got" || fail "'${tf%%:*}' → hardened=$got, want ${tf##*:}"
done

echo "the interview gate still runs first"
P=$(mk_project ord 080 "full track")
head -n 20 "$P/specs/080-demo/interview.md" > "$P/x" && mv "$P/x" "$P/specs/080-demo/interview.md"
expect "short interview denies with the interview reason" "$P/src/app.ts" deny "anti-drift interview incomplete"

# ------------------------------------------------------------------------------ parser and digest

echo "parser"
P=$(mk_project prs 080 "full track")
write_cases "$P" 080 3
sed -i.bak '/^\*\*When\*\* action 2$/d' "$P/specs/080-demo/acceptance.md"
expect "a case without When" "$P/src/app.ts" deny "AC-2 has no When"
write_cases "$P" 080 3
sed -i.bak 's/^\*\*Given\*\* state 1$/**Given**   /' "$P/specs/080-demo/acceptance.md"
expect "an empty Given" "$P/src/app.ts" deny "AC-1 has no Given"
write_cases "$P" 080 3
printf '## AC-3 — again\n**Given** g\n**When** w\n**Then** t\n' >> "$P/specs/080-demo/acceptance.md"
expect "a repeated number" "$P/src/app.ts" deny "AC-3"
write_cases "$P" 080 3
sed -i.bak 's/^## AC-2 — case 2$/## AC-2 —   /' "$P/specs/080-demo/acceptance.md"
expect "a heading with no title" "$P/src/app.ts" deny "AC-2 has no title"
write_cases "$P" 080 3
printf '**Then** a second Then\n' > "$P/x"
sed -i.bak '/^\*\*Then\*\* outcome 1$/r '"$P/x" "$P/specs/080-demo/acceptance.md"
expect "a field given twice" "$P/src/app.ts" deny "AC-1 has two Then"
write_cases "$P" 080 3
printf '**Confirmed:** yesterday — "ok"\n' >> "$P/specs/080-demo/acceptance.md"
expect "a malformed Confirmed line" "$P/src/app.ts" deny "Confirmed line"
write_cases "$P" 080 3
confirm "$P" 080
grep '^\*\*Confirmed:\*\*' "$P/specs/080-demo/acceptance.md" >> "$P/specs/080-demo/acceptance.md"
expect "two Confirmed lines" "$P/src/app.ts" deny "Confirmed line"
write_cases "$P" 080 3
python3 -c "print('x' * 70000)" >> "$P/specs/080-demo/acceptance.md"
expect "over 64 KB" "$P/src/app.ts" deny "64 KB"
write_cases "$P" 080 3
chmod 000 "$P/specs/080-demo/acceptance.md"
if [ -r "$P/specs/080-demo/acceptance.md" ]; then ok "unreadable file (skipped: running as a user who can read mode 000)"
else expect "an unreadable acceptance.md denies" "$P/src/app.ts" deny "cannot be read"; fi
chmod 644 "$P/specs/080-demo/acceptance.md"

echo "parser: wrapped lines and other sections"
P=$(mk_project wrp 080 "full track")
cat > "$P/specs/080-demo/acceptance.md" <<'EOF'
# Acceptance cases — 080-demo

Intro prose the digest ignores.

## AC-1 — wrapped
**Given** a long state
that wraps onto a second line
**When** an action
**Then** an outcome

## AC-2 — second
**Given** g2
**When** w2
**Then** t2

## AC-3 — third
**Given** g3 state
**When** w3
**Then** t3

## Notes
Not a case.
EOF
out=$(bash "$HELPER" --check "$P/specs/080-demo" 2>&1); rc=$?
[ "$rc" -eq 3 ] && [ "$out" = "3 cases, unconfirmed" ] && ok "wrapped Given and a trailing non-case section parse (3 cases, unconfirmed)" || fail "check on a valid unconfirmed file: rc $rc, $out"
d1=$(bash "$HELPER" --digest "$P/specs/080-demo")
sed -i.bak 's/^Intro prose the digest ignores.$/Different intro./' "$P/specs/080-demo/acceptance.md"
d2=$(bash "$HELPER" --digest "$P/specs/080-demo")
[ "$d1" = "$d2" ] && ok "prose outside the cases does not move the digest" || fail "prose moved the digest ($d1 → $d2)"
sed -i.bak 's/^\*\*When\*\* w2$/**When**    w2   /; s/^\*\*Given\*\* g3 state$/**Given** g3   	state/' "$P/specs/080-demo/acceptance.md"
d3=$(bash "$HELPER" --digest "$P/specs/080-demo")
[ "$d1" = "$d3" ] && ok "whitespace inside and around a line does not move the digest" || fail "whitespace moved the digest"
sed -i.bak 's/^\*\*When\*\*    w2   $/**When** w2 changed/' "$P/specs/080-demo/acceptance.md"
d4=$(bash "$HELPER" --digest "$P/specs/080-demo")
[ "$d1" != "$d4" ] && ok "a changed word moves the digest" || fail "a changed word kept the digest"
sed -i.bak 's/^## AC-2 — second$/## AC-2 — renamed/' "$P/specs/080-demo/acceptance.md"
d5=$(bash "$HELPER" --digest "$P/specs/080-demo")
[ "$d4" != "$d5" ] && ok "a changed title moves the digest" || fail "a changed title kept the digest"
case "$d1" in [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ok "digest is 12 hex characters" ;; *) fail "digest shape: '$d1'" ;; esac

echo "helper: confirm"
P=$(mk_project cnf 080 "full track")
write_cases "$P" 080 3
bash "$HELPER" --confirm "$P/specs/080-demo" --quote "" >/dev/null 2>&1 && fail "an empty quote was accepted" || ok "an empty quote is refused"
write_cases "$P" 080 2
bash "$HELPER" --confirm "$P/specs/080-demo" --quote "yes" >/dev/null 2>&1 && fail "a malformed file was confirmed" || ok "a malformed file cannot be confirmed"
write_cases "$P" 080 3
confirm "$P" 080 'he said "yes"
on two lines'
line=$(grep '^\*\*Confirmed:\*\*' "$P/specs/080-demo/acceptance.md")
n=$(grep -c '^\*\*Confirmed:\*\*' "$P/specs/080-demo/acceptance.md")
[ "$n" -eq 1 ] && ok "one Confirmed line" || fail "$n Confirmed lines"
case "$line" in *'he said "yes" on two lines"') ok "the quote is kept on one line, inner quotes intact" ;; *) fail "quote line: $line" ;; esac
confirm "$P" 080 "again"
n=$(grep -c '^\*\*Confirmed:\*\*' "$P/specs/080-demo/acceptance.md")
[ "$n" -eq 1 ] && ok "confirming again replaces the line" || fail "confirming again left $n lines"
bash "$HELPER" --check "$P/specs/080-demo" >/dev/null 2>&1 && ok "the confirmed file checks clean" || fail "the confirmed file does not check"

# ------------------------------------------------------------------------------------- coverage

echo "coverage: what counts as naming a case"
P=$(mk_project cov 080 "full track")
write_cases "$P" 080 3
confirm "$P" 080
printf '// 080-AC-1 080-AC-2 080-AC-3\n' > "$P/src/app.ts"
expect "a name in production code does not count" "$P/src/app.ts" deny "080-AC-1"
rm "$P/src/app.ts"
printf '// 1080-AC-1 080-AC-10 080-AC-2x 080-AC-3\n' > "$P/tests/a.test.ts"
expect "1080-AC-1 and 080-AC-10 are not 080-AC-1" "$P/src/app.ts" deny "080-AC-1"
printf '// 080-AC-1 080-AC-2x 080-AC-3\n' > "$P/tests/a.test.ts"
expect "080-AC-2x is not 080-AC-2" "$P/src/app.ts" deny "no test names 080-AC-2 yet"
printf '// 080-AC-1, 080-AC-2.\n' > "$P/tests/b.test.ts"
expect "punctuation after the name still counts" "$P/src/app.ts" allow
P=$(mk_project dot 501.1 "full track")
write_cases "$P" 501.1 3
confirm "$P" 501.1
printf '// 501x1-AC-1 501x1-AC-2 501x1-AC-3\n' > "$P/tests/a.test.ts"
expect "a dotted id is matched literally (501x1 is not 501.1)" "$P/src/app.ts" deny "501.1-AC-1"
printf '// 501.1-AC-1 501.1-AC-2 501.1-AC-3\n' > "$P/tests/a.test.ts"
expect "a dotted id named literally" "$P/src/app.ts" allow

echo "coverage: test-path recognition"
for p in tests/x.ts test/x.ts src/__tests__/x.ts spec/x.rb e2e/x.ts integration_test/x.dart \
         App.Tests/X.cs App.Test/X.cs src/x.test.ts src/x.spec.tsx pkg/x_test.go test_x.py \
         src/XTests.cs src/XTest.cs lib/x_spec.rb scripts/test-x.sh; do
  bash "$HELPER" --is-test "$p" >/dev/null 2>&1 && ok "test path: $p" || fail "not seen as a test: $p"
done
for p in src/latest/app.ts src/contest.ts src/testing_utils.ts src/attestation/x.cs \
         src/specification.ts src/Inspector.cs scripts/testing.sh scripts/test-x.ts \
         specs/080-demo/acceptance.md; do
  bash "$HELPER" --is-test "$p" >/dev/null 2>&1 && fail "production seen as a test: $p" || ok "production path: $p"
done

echo "coverage: production under a test-looking parent"
P=$(mk_project lat 080 "full track")
write_cases "$P" 080 3
confirm "$P" 080
mkdir -p "$P/src/latest"
expect "src/latest/app.ts is production" "$P/src/latest/app.ts" deny "080-AC-1"

echo "coverage: cache and timeout"
P=$(mk_project cch 080 "full track")
write_cases "$P" 080 3
confirm "$P" 080
printf '// 080-AC-1 080-AC-2 080-AC-3\n' > "$P/tests/a.test.ts"
expect "all named" "$P/src/app.ts" allow
[ -f "$P/.claude/state/acceptance/080" ] && ok "the verdict is cached" || fail "no cache file"
expect "a cache hit allows" "$P/src/app.ts" allow
mv "$P/tests/a.test.ts" "$P/a.bak"
expect "a cache whose test file is gone does not allow" "$P/src/app.ts" deny "080-AC-1"
mv "$P/a.bak" "$P/tests/a.test.ts"
expect "rescan after the file is back" "$P/src/app.ts" allow
{ head -n 1 "$P/.claude/state/acceptance/080"; echo "src/app.ts"; } > "$P/x" && mv "$P/x" "$P/.claude/state/acceptance/080"
rm "$P/tests/a.test.ts"
printf '// 080-AC-1 080-AC-2 080-AC-3\n' > "$P/src/app.ts"
expect "a forged cache pointing at production code does not allow" "$P/src/app.ts" deny "080-AC-1"
rm "$P/src/app.ts"
printf '\377\376\000garbage' > "$P/.claude/state/acceptance/080"
expect "a cache of invalid bytes does not allow" "$P/src/app.ts" deny "080-AC-1"
sed -i.bak 's/^\*\*Then\*\* outcome 3$/**Then** changed/' "$P/specs/080-demo/acceptance.md"
confirm "$P" 080 "changed"
expect "a new digest invalidates the cache" "$P/src/app.ts" deny "080-AC-1"
printf '../../etc/x' > "$P/.claude/state/acceptance/080"
expect "a garbage cache file is ignored" "$P/src/app.ts" deny "080-AC-1"
P=$(mk_project tmo 080 "full track")
write_cases "$P" 080 3
confirm "$P" 080
expect "a scan timeout fails open" "$P/src/app.ts" allow "" ACCEPTANCE_SCAN_TIMEOUT=0.000001
expect "a nonsense timeout falls back to the default" "$P/src/app.ts" deny "080-AC-1" ACCEPTANCE_SCAN_TIMEOUT=abc

echo "routes"
P=$(mk_project rte 080 "full track")
with_artifacts "$P" 080
write_cases "$P" 080 3
bash_out() {
  jq -n --arg c "echo x > $1" '{tool_name:"Bash",tool_input:{command:$c}}' \
    | (cd "$P" && CLAUDE_PROJECT_DIR="$P" env "${@:2}" bash "$BASH_GUARD" 2>/dev/null)
}
out=$(bash_out "$P/src/app.ts")
if [ "$(hook_verdict "$out")" = deny ] && printf '%s' "$out" | grep -q "not confirmed"; then
  ok "a Bash write to production source is denied by the acceptance step"
else fail "Bash route: expected the acceptance deny, got $(hook_verdict "$out"): ${out:0:160}"; fi
out=$(bash_out "$P/src/app.ts" SPEC_ACCEPTANCE=off)
case "$(hook_verdict "$out")" in none|allow) ok "the same Bash write with the switch off is allowed (proves the deny above was ours)" ;;
  *) fail "Bash route with SPEC_ACCEPTANCE=off: got $(hook_verdict "$out"): ${out:0:160}" ;; esac
confirm "$P" 080
out=$(bash_out "$P/tests/app.test.ts")
case "$(hook_verdict "$out")" in none|allow) ok "a Bash write to a test file is allowed once confirmed" ;;
  *) fail "Bash route test file: got $(hook_verdict "$out"): ${out:0:160}" ;; esac

echo "attacks"
P=$(mk_project atk 080 "full track")
write_cases "$P" 080 3
confirm "$P" 080
ln -s ../src "$P/tests/link"
expect "a symlink in tests/ to src/ is not a test file" "$P/tests/link/app.ts" deny "080-AC-1"
python3 -c 'print("# t\n\n## AC-" + "9" * 5000 + " — x\n**Given** g\n**When** w\n**Then** t")' > "$P/specs/080-demo/acceptance.md"
expect "a 5000-digit case number is not a heading (no crash)" "$P/src/app.ts" deny "0 cases; the band is 3-5"
write_cases "$P" 080 3
confirm "$P" 080
python3 -c 'print("// 080-AC-" + "9" * 5000)' > "$P/tests/huge.test.ts"
expect "a 5000-digit name in a test denies" "$P/src/app.ts" deny "080-AC-1"
rm "$P/tests/huge.test.ts"
rm "$P/specs/080-demo/acceptance.md"
mkfifo "$P/specs/080-demo/acceptance.md"
# Bounded: a guard that opens the FIFO blocks forever, and the suite must report that, not hang.
fifo_out=$(python3 - "$GUARD" "$P/src/app.ts" <<'FIFO'
import json, subprocess, sys
payload = json.dumps({"tool_name": "Write", "tool_input": {"file_path": sys.argv[2], "content": "x"}})
try:
    r = subprocess.run(["bash", sys.argv[1]], input=payload.encode(), stdout=subprocess.PIPE,
                       stderr=subprocess.DEVNULL, timeout=10)
    print(r.stdout.decode())
except subprocess.TimeoutExpired:
    print("HUNG")
FIFO
)
case "$fifo_out" in
  HUNG*) fail "a FIFO acceptance.md made the guard hang" ;;
  *"not a regular file"*) ok "a FIFO acceptance.md denies without hanging" ;;
  *) fail "a FIFO acceptance.md: ${fifo_out:0:120}" ;;
esac
rm "$P/specs/080-demo/acceptance.md"
write_cases "$P" 080 3
confirm "$P" 080
mkdir -p "$P/tests/ö"
printf '// 080-AC-1 080-AC-2 080-AC-3\n' > "$P/tests/ö/å.test.ts"
expect "a test under a non-ASCII path counts" "$P/src/app.ts" allow
P=$(mk_project nrp 080 "full track")
write_cases "$P" 080 3
confirm "$P" 080
rm -rf "$P/.git" && mkdir "$P/.git"
expect "a broken .git denies (only a timeout fails open)" "$P/src/app.ts" deny "could not be checked"

echo "the gate cannot load its parser"
G="$TMP/guardonly"; mkdir -p "$G"
cp "$GUARD" "$SELF_DIR/spec_active.py" "$G/"
P=$(mk_project nop 080 "full track")
out=$(jq -n --arg p "$P/src/app.ts" '{tool_name:"Write",tool_input:{file_path:$p,content:"x"}}' | bash "$G/spec-interview-guard-hook.sh" 2>/dev/null)
[ "$(hook_verdict "$out")" = deny ] && ok "acceptance_cases.py missing → deny" || fail "acceptance_cases.py missing → $(hook_verdict "$out")"

echo "the gate crashes"
G="$TMP/guardcrash"; mkdir -p "$G"
cp "$GUARD" "$SELF_DIR/spec_active.py" "$G/"
printf 'def gate(root, info, file_path):\n    raise RuntimeError("boom")\n' > "$G/acceptance_cases.py"
P=$(mk_project crs 080 "full track")
out=$(jq -n --arg p "$P/src/app.ts" '{tool_name:"Write",tool_input:{file_path:$p,content:"x"}}' | bash "$G/spec-interview-guard-hook.sh" 2>/dev/null)
if [ "$(hook_verdict "$out")" = deny ] && printf '%s' "$out" | grep -q "crashed (RuntimeError: boom)"; then ok "a crash inside gate() denies and names it"
else fail "a crash inside gate() → $(hook_verdict "$out"): ${out:0:120}"; fi

echo "parser: other spellings"
P=$(mk_project spl 080 "full track")
printf '\357\273\277## AC-1 – en dash\r\n**Given:** g\r\n**When:** w\r\n**Then:** t\r\n\r\n## AC-2 - hyphen\r\n**Given** g\r\n**When** w\r\n**Then** t\r\n\r\n## AC-3 — em\r\n**Given** g\r\n**When** w\r\n**Then** t\r\n' > "$P/specs/080-demo/acceptance.md"
out=$(bash "$HELPER" --check "$P/specs/080-demo" 2>&1)
[ "$out" = "3 cases, unconfirmed" ] && ok "BOM, CRLF, en dash, hyphen and **Given:** parse" || fail "spellings: $out"
confirm "$P" 080
grep -q $'\r$' "$P/specs/080-demo/acceptance.md" && [ "$(grep -c $'[^\r]$' "$P/specs/080-demo/acceptance.md")" -eq 0 ] \
  && ok "confirm keeps CRLF line endings" || fail "confirm changed the line endings"
bash "$HELPER" --check "$P/specs/080-demo" >/dev/null 2>&1 && ok "and the CRLF file checks confirmed" || fail "CRLF confirm does not check"
P=$(mk_project noh 080 "full track")
write_cases "$P" 080 3
sed -i.bak '1d' "$P/specs/080-demo/acceptance.md"
printf '```\na\n\n\n\nb\n```\n' >> "$P/specs/080-demo/acceptance.md"
confirm "$P" 080
head -n 1 "$P/specs/080-demo/acceptance.md" | grep -q '^\*\*Confirmed:\*\*' && ok "no H1: the Confirmed line goes first" || fail "no H1: $(head -n 1 "$P/specs/080-demo/acceptance.md")"
[ "$(grep -c '^$' "$P/specs/080-demo/acceptance.md")" -ge 6 ] && ok "confirm leaves blank lines elsewhere alone" || fail "confirm collapsed blank lines"
bash "$HELPER" --check "$P/specs/080-demo" >/dev/null 2>&1 && ok "and it checks confirmed" || fail "no-H1 confirm does not check"
for p in 'C:\proj\tests\x.ts' 'App.Tests\Foo.cs'; do
  bash "$HELPER" --is-test "$p" >/dev/null 2>&1 && ok "backslash test path: $p" || fail "backslash test path: $p"
done
bash "$HELPER" --is-test 'C:\proj\src\app.ts' >/dev/null 2>&1 && fail "backslash production seen as a test" || ok "backslash production path"

echo "helper: coverage default root"
P=$(mk_project hcv 080 "full track")
write_cases "$P" 080 3
printf '// 080-AC-1 080-AC-2 080-AC-3\n' > "$P/tests/a.test.ts"
out=$(bash "$HELPER" --coverage "$P/specs/080-demo" 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$out" | grep -c ' named ')" -eq 3 ] && ok "--coverage finds the project root from the spec dir" || fail "--coverage: rc $rc, $out"

echo "timing"
P=$(mk_project tim 080 "full track")
write_cases "$P" 080 3
confirm "$P" 080
printf '// 080-AC-1 080-AC-2\n' > "$P/tests/a.test.ts"
best=999999
for _ in 1 2 3; do
  start=$(python3 -c 'import time; print(time.time())')
  guard_out "$P/src/app.ts" >/dev/null
  end=$(python3 -c 'import time; print(time.time())')
  ms=$(python3 -c "print(int(($end - $start) * 1000))")
  [ "$ms" -lt "$best" ] && best=$ms
done
[ "$best" -lt 400 ] && ok "step-2 deny in ${best} ms, best of 3 (< 400)" || fail "step-2 deny took ${best} ms, best of 3"

echo
echo "acceptance cases: $PASSES passed, $FAILURES failed"
[ "$FAILURES" -eq 0 ]

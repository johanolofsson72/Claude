#!/usr/bin/env bash
. "$(dirname -- "$0")/self-test-env.sh" || exit 1
# test-context-budget.sh — the always-loaded context budget (spec 081).
#
# context-budget.sh sums what every session loads before the first prompt: CLAUDE.md,
# .claude/CLAUDE.md, every .claude/rules/**/*.md without a `paths:` key in its frontmatter, and the
# files CLAUDE.md imports with a leading `@`. The first half tests that on fixtures. The second half
# runs only in the template repo (no language marker at the root) and is the ratchet: the template's
# own total must stay within the cap and must not grow past scripts/context-budget.baseline.
#
# Exit 0 = every assertion held. Exit 1 = a real failure.

set -u

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
BUDGET="$SELF_DIR/context-budget.sh"
REPO=$(cd "$SELF_DIR/.." && pwd)

FAILURES=0
PASSES=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ok()   { printf '  ✓ %s\n' "$1"; PASSES=$((PASSES + 1)); }
fail() { printf '  ✗ %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

# bytes <n> -> n bytes of text
bytes() { python3 -c "import sys; sys.stdout.write('x' * int(sys.argv[1]))" "$1"; }

# total_of <root> [args...] -> the total the script reports
total_of() { bash "$BUDGET" --root "$@" 2>/dev/null | sed -n 's/^total[[:space:]]\{1,\}\([0-9]\{1,\}\).*/\1/p'; }

echo "what counts"
F="$TMP/f1"; mkdir -p "$F/.claude/rules/sub" "$F/.claude/docs"
bytes 100 > "$F/CLAUDE.md"
bytes 10 > "$F/.claude/CLAUDE.md"
bytes 1000 > "$F/.claude/rules/always.md"
bytes 7 > "$F/.claude/rules/sub/nested.md"
{ printf -- '---\npaths:\n  - "**/*.cs"\n---\n'; bytes 5000; } > "$F/.claude/rules/scoped.md"
{ printf -- '---\npaths: []\n---\n'; bytes 5000; } > "$F/.claude/rules/empty-paths.md"
{ printf -- '---\ndescription: x\n---\n'; bytes 200; } > "$F/.claude/rules/front-no-paths.md"
{ printf -- '---\ndescription: x\n---\n'; bytes 50; printf '\npaths:\n  - "**/*"\n'; } > "$F/.claude/rules/body-paths.md"
bytes 3000 > "$F/.claude/docs/ondemand.md"
bytes 900 > "$F/CLAUDE.local.md"
fm_size=$(wc -c < "$F/.claude/rules/front-no-paths.md" | tr -d ' ')
bp_size=$(wc -c < "$F/.claude/rules/body-paths.md" | tr -d ' ')
want=$((100 + 10 + 1000 + 7 + fm_size + bp_size))
got=$(total_of "$F")
[ "$got" = "$want" ] && ok "CLAUDE.md + .claude/CLAUDE.md + unscoped + nested rules = $want" || fail "total $got, want $want"
out=$(bash "$BUDGET" --root "$F" 2>&1)
grep -q 'scoped.md' <<< "$out" && fail "a paths: rule was listed" || ok "a paths: rule is not counted"
grep -q 'empty-paths.md' <<< "$out" && fail "paths: [] was listed" || ok "paths: [] is scoped too"
grep -q 'body-paths.md' <<< "$out" && ok "paths: in the body (not frontmatter) still counts" || fail "body paths: treated as scoped"
grep -q 'ondemand.md' <<< "$out" && fail "a doc was counted" || ok "docs are not counted"
grep -q 'CLAUDE.local.md.*not counted' <<< "$out" && ok "CLAUDE.local.md is reported apart" || fail "CLAUDE.local.md: $(printf '%s' "$out" | grep local)"
first=$(printf '%s\n' "$out" | grep -E '^ *[0-9]+ ' | head -n 1)
case "$first" in *always.md*) ok "largest first" ;; *) fail "first row: $first" ;; esac

echo "@-imports"
F="$TMP/f2"; mkdir -p "$F/.claude/docs"
{ bytes 40; printf '\n@.claude/docs/imported.md\n'; } > "$F/CLAUDE.md"
bytes 2000 > "$F/.claude/docs/imported.md"
c=$(wc -c < "$F/CLAUDE.md" | tr -d ' ')
got=$(total_of "$F")
[ "$got" = "$((c + 2000))" ] && ok "an @-import is followed" || fail "with import: $got, want $((c + 2000))"
printf '%s\n@.claude/docs/%s\n' "$(cat "$F/CLAUDE.md")" missing.md > "$F/CLAUDE.md"
bash "$BUDGET" --root "$F" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "a missing @-import exits 2" || fail "missing import rc $rc"
F="$TMP/f2b"; mkdir -p "$F"
printf 'mail me at a@b.se\nsee `@foo` inline\n' > "$F/CLAUDE.md"
bash "$BUDGET" --root "$F" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "an @ that does not start a line is not an import" || fail "inline @ rc $rc"

echo "cap and exit codes"
F="$TMP/f3"; mkdir -p "$F/.claude/rules"
bytes 500 > "$F/CLAUDE.md"
bash "$BUDGET" --root "$F" --max-bytes 500 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "exactly at the cap is within" || fail "at cap rc $rc"
out=$(bash "$BUDGET" --root "$F" --max-bytes 499 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "one byte over exits 1" || fail "over cap rc $rc"
grep -q '1 bytes over' <<< "$out" && ok "it says by how much" || fail "over text: $out"
F="$TMP/f4"; mkdir -p "$F"
out=$(bash "$BUDGET" --root "$F" 2>&1); rc=$?
[ "$rc" -eq 0 ] && grep -qE '^total +0 ' <<< "$out" && ok "nothing to load: total 0, within" || fail "empty: rc $rc, $out"
bash "$BUDGET" --root "$TMP/nope" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "a missing root exits 2" || fail "missing root rc $rc"
bash "$BUDGET" --root "$F" --max-bytes abc >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "a non-numeric cap exits 2" || fail "bad cap rc $rc"
F="$TMP/f5 with space"; mkdir -p "$F/.claude/rules"
bytes 12 > "$F/CLAUDE.md"; bytes 8 > "$F/.claude/rules/a b.md"
got=$(total_of "$F")
[ "$got" = "20" ] && ok "paths with spaces" || fail "spaces: $got"

echo "template ratchet"
is_template=1
for m in package.json Cargo.toml go.mod pyproject.toml requirements.txt composer.json Gemfile pom.xml pubspec.yaml; do
  [ -f "$REPO/$m" ] && is_template=0
done
ls "$REPO"/*.csproj "$REPO"/*.sln >/dev/null 2>&1 && is_template=0
if [ "$is_template" -eq 0 ]; then
  ok "not the template repo: ratchet skipped"
else
  base=$(tr -d '[:space:]' < "$SELF_DIR/context-budget.baseline" 2>/dev/null)
  total=$(total_of "$REPO")
  case "$base" in ''|*[!0-9]*) fail "context-budget.baseline is missing or not a number: '$base'" ;; *)
    bash "$BUDGET" --root "$REPO" >/dev/null 2>&1 && ok "template total $total is within the 40960-byte cap" \
      || fail "template total $total is over the cap: bash scripts/context-budget.sh"
    if [ "$total" -le "$base" ]; then ok "template total $total ≤ baseline $base"
    else fail "template total $total grew past the baseline $base — move the new text to a doc, or raise the baseline in a reviewed diff"; fi
    if [ $((base - total)) -gt 1024 ]; then
      echo "    note: $((base - total)) bytes under the baseline; lower it: bash scripts/context-budget.sh --root . | sed -n 's/^total *\\([0-9]*\\).*/\\1/p' > scripts/context-budget.baseline"
    fi ;;
  esac
fi

echo
echo "context budget: $PASSES passed, $FAILURES failed"
[ "$FAILURES" -eq 0 ]

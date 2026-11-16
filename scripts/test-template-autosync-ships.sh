#!/bin/bash
. "$(dirname -- "$0")/self-test-env.sh" || exit 1
# Tests what the copy loops in scripts/template-autosync.sh deliver (spec 102).
#
# Two things were red in every synced project although the template was green:
#
#   R1  CORE_SCRIPTS names quality-gates.tsv and workload-placement.tsv, and the scripts loop
#       globbed *.sh *.py plus speckit-version by name, so neither data file reached a project.
#       test-sync-prompt-core-parity.sh caught it downstream as a name with no file behind it.
#   R3  the web stack gate withheld testing-mobile.md, spec-testing-checklist-mobile.md and
#       deployment-mobile.md, which CORE rules and docs cite by name, so validate-rule-citations
#       reported 15 dangling citations in every web project. A mobile project got the first two
#       under the canonical names only, so the same citations dangled there.
#
# End-to-end over a fixture template and project, through drive_sync (spec 011).
#
# Run: bash scripts/test-template-autosync-ships.sh

set -u
cd "$(dirname "$0")/.." || exit 1
SCRIPT="$PWD/scripts/template-autosync.sh"
[ -f "$SCRIPT" ] || { echo "FAIL: template-autosync.sh not found"; exit 1; }
. "$PWD/scripts/drive-sync.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
exists()  { if [ -f "$2" ]; then ok "$1"; else bad "$1 (no file at ${2#"$TMP"/})"; fi; }
same()    { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$3', got '$2')"; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# $1 case name · $2 the project's testing stack (web | mobile)
build() {
  R="$TMP/$1"; rm -rf "$R"; mkdir -p "$R"
  T="$R/template"; P="$R/project"

  mkdir -p "$T/scripts" "$T/.claude/docs" "$T/.claude/rules"
  printf "rule\n" > "$T/.claude/rules/demo-rule.md"   # a template clone has rules (template_candidates)
  cp "$SCRIPT" "$T/scripts/"
  echo prompt > "$T/scripts/sync-prompt.md"
  printf 'gate\tcmd\n' > "$T/scripts/quality-gates.tsv"
  printf 'web testing\n'          > "$T/.claude/docs/testing.md"
  printf 'web checklist\n'        > "$T/.claude/docs/spec-testing-checklist.md"
  printf 'mobile testing\n'       > "$T/.claude/docs/testing-mobile.md"
  printf 'mobile checklist\n'     > "$T/.claude/docs/spec-testing-checklist-mobile.md"
  printf 'mobile deployment\n'    > "$T/.claude/docs/deployment-mobile.md"
  git -C "$T" init -q -b main
  git -C "$T" config user.email t@t; git -C "$T" config user.name T
  git -C "$T" add -A; git -C "$T" commit -qm init

  mkdir -p "$P/.claude" "$P/scripts"
  printf 'testing=%s\n' "$2" > "$P/.claude/.sync-stack"
  cp "$SCRIPT" "$P/scripts/"
  git -C "$P" init -q -b main
  git -C "$P" config user.email p@p; git -C "$P" config user.name P
  git -C "$P" add -A; git -C "$P" commit -qm init
}
sync() { _p="$1"; _t="$2"; shift 2
  CLAUDE_TEMPLATE_DIR="$_t" DRIVE_SYNC_SCRIPT="$_p/scripts/template-autosync.sh" \
    drive_sync "$_p" "$TMP" "$@" 2>&1; }

echo "== [102] R1: a data file CORE_SCRIPTS names ships =="
build r1 web
sync "$P" "$T" --no-commit >/dev/null
exists "[102] quality-gates.tsv reaches the project"   "$P/scripts/quality-gates.tsv"
same   "[102] ...with the template's bytes"            "$(cat "$P/scripts/quality-gates.tsv" 2>/dev/null)" "$(printf 'gate\tcmd')"
same   "[102] ...and the manifest records it"          "$(grep -c ' scripts/quality-gates.tsv$' "$P/.claude/.template-sync" 2>/dev/null)" 1

echo "== [102] R3: a web project receives the mobile docs under their own names =="
build r3web web
sync "$P" "$T" --no-commit >/dev/null
for d in testing-mobile.md spec-testing-checklist-mobile.md deployment-mobile.md; do
  exists "[102] web gets .claude/docs/$d" "$P/.claude/docs/$d"
done
same "[102] web gets the mobile doc as itself, not as testing.md" "$(cat "$P/.claude/docs/testing-mobile.md" 2>/dev/null)" "mobile testing"

echo "== [102] R3: a mobile project gets the own-name copies too =="
# The canonical-name overlays (testing-mobile.md -> testing.md) are unchanged by spec 102 and need a
# manifest history to exercise; this case is only about the own-name copies the citations need.
build r3mob mobile
sync "$P" "$T" --no-commit >/dev/null
exists "[102] mobile gets testing-mobile.md"              "$P/.claude/docs/testing-mobile.md"
exists "[102] ...and spec-testing-checklist-mobile.md"    "$P/.claude/docs/spec-testing-checklist-mobile.md"
exists "[102] ...and deployment-mobile.md"                "$P/.claude/docs/deployment-mobile.md"

echo ""
echo "template-autosync-ships: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

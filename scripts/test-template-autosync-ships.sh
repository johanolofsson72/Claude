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

echo "== [106] R4: a RULE_ADDS rule is added when missing; a stack rule is not =="
build r4 web
printf 'design refs\n' > "$T/.claude/rules/design-references.md"
printf 'wp\n'          > "$T/.claude/rules/wordpress.md"
printf 'decided\n'     > "$T/.claude/docs/deployment.md"
git -C "$T" add -A; git -C "$T" commit -qm rules
sync "$P" "$T" --no-commit >/dev/null
exists "[106] design-references.md reaches a project that lacks it" "$P/.claude/rules/design-references.md"
if [ -f "$P/.claude/rules/wordpress.md" ]; then bad "[106] a stack rule the project lacks was added"; else ok "[106] a stack rule the project lacks stays absent"; fi
if [ -f "$P/.claude/docs/deployment.md" ]; then bad "[106] a decision doc outside RULE_DOCS was added"; else ok "[106] a doc outside RULE_DOCS the project lacks stays absent"; fi
printf 'project edit\n' > "$P/.claude/rules/design-references.md"
printf 'design refs v2\n' > "$T/.claude/rules/design-references.md"
git -C "$T" commit -qam v2
sync "$P" "$T" --no-commit >/dev/null
same "[106] ...and after that a local edit is kept, not overwritten" "$(cat "$P/.claude/rules/design-references.md")" "project edit"

echo "== [106] R1: a template clone git cannot read is refused, nothing stamped =="
build r1git web
GOOD="$R/home/repos/Claude"; mkdir -p "$R/home/repos"; git clone -q "$T" "$GOOD"
echo 'not a ref' > "$T/.git/HEAD"
mkdir -p "$R/empty-home"
out=$(HOME="$R/empty-home" sync "$P" "$T" --no-commit); rc=$?
same "[106] the refusal exits 0 (SessionStart never fails)" "$rc" 0
case "$out" in *"git could not read the template clone"*) ok "[106] ...and says why" ;; *) bad "[106] no reason printed: $out" ;; esac
if [ -f "$P/.claude/.template-sync" ]; then bad "[106] a stamp was written: $(sed -n 1p "$P/.claude/.template-sync")"; else ok "[106] ...and writes no stamp"; fi
out=$(HOME="$R/empty-home" sync "$P" "$T" --accept-local x 2>&1); rc=$?
same "[106] under --accept-local the refusal exits 1" "$rc" 1
# 106 review #3: one unreadable candidate (a stale CLAUDE_TEMPLATE_DIR) must not hide a good one.
out=$(HOME="$R/home" sync "$P" "$T" --no-commit); rc=$?
same "[106] an unreadable first candidate is passed over: the good clone syncs" \
  "$(sed -n 's/^sha=//p' "$P/.claude/.template-sync" 2>/dev/null)" "$(git -C "$GOOD" rev-parse --short=12 HEAD)"

echo "== [106] R1: HEAD readable, status failing (a corrupt index) is unreadable too =="
build r1idx web
printf 'garbage' > "$T/.git/index"
mkdir -p "$R/empty-home"
out=$(HOME="$R/empty-home" sync "$P" "$T" --no-commit); rc=$?
case "$out" in *"git could not read the template clone"*) ok "[106] a failing status is refused, not read as clean" ;; *) bad "[106] corrupt index: $out" ;; esac
if [ -f "$P/.claude/.template-sync" ]; then bad "[106] corrupt index: a stamp was written"; else ok "[106] ...and nothing is stamped"; fi
# The same clone under ALLOW_DIRTY skips the first status and meets the second one.
out=$(HOME="$R/empty-home" CLAUDE_TEMPLATE_ALLOW_DIRTY=1 sync "$P" "$T" --no-commit); rc=$?
case "$out" in *"git could not read the template clone"*) ok "[106] ...also under CLAUDE_TEMPLATE_ALLOW_DIRTY" ;; *) bad "[106] corrupt index + allow-dirty: $out" ;; esac
if [ -f "$P/.claude/.template-sync" ]; then bad "[106] corrupt index + allow-dirty: a stamp was written"; else ok "[106] ...with nothing stamped"; fi

echo "== [106] R1: a template directory with no .git keeps the use-it-as-is fallback =="
build r1plain web
rm -fr "$T/.git"
out=$(HOME="$R/empty-home" sync "$P" "$T" --no-commit); rc=$?
same "[106] a plain directory still syncs (stamp local-unknown, as documented)" \
  "$(sed -n 's/^sha=//p' "$P/.claude/.template-sync" 2>/dev/null)" "local-unknown"

echo "== [106] R1: --tracked that cannot list is reported, and the sync still exits 0 =="
build r1trk web
cp "$PWD/scripts/harness-gitignore.sh" "$R/hg-real.sh"
cat > "$T/scripts/harness-gitignore.sh" <<EOF
#!/bin/bash
[ "\$1" = --tracked ] && { echo "harness-gitignore: git will not read the stub/.git"; exit 4; }
exec bash "$R/hg-real.sh" "\$@"
EOF
git -C "$T" add -A; git -C "$T" commit -qm stub
out=$(HOME="$R/empty-home" sync "$P" "$T" --no-commit); rc=$?
same "[106] the sync exits 0" "$rc" 0
case "$out" in *"[tracked] the committed machine-local paths could not be listed: git will not read the stub/.git"*) ok "[106] ...and quotes why --tracked could not list" ;; *) bad "[106] no [tracked] reason: $out" ;; esac

# [106] R4 parity (F233). Docs and rules reach an existing project only by name: RULE_DOCS and
# RULE_ADDS add them when missing, CORE_RULES always. A file every project receives that cites a
# template doc or rule outside those lists holds a citation that dangles in every project born
# before the cited file (6 of 47 in ~/repos on 2026-11-17). Upstream only: downstream the template's
# tree is not here to compare against.
if [ "$(. "$PWD/scripts/template-identity.sh" && self_test_subject "$PWD")" = upstream ]; then
  echo "== [106] R4 parity: every citation in an always-shipped file reaches every project =="
  list() { awk -v v="^$1=\"" '$0 ~ v {on=1} on {print} on && /"$/ {exit}' scripts/template-autosync.sh \
    | sed "s/^$1=\"//; s/\"\$//" | tr ' ' '\n' | grep -v '^$'; }
  RULE_DOCS_L=$(list RULE_DOCS); RULE_ADDS_L=$(list RULE_ADDS)
  CORE_RULES_L=$(bash scripts/template-autosync.sh --list-core-rules)
  [ -n "$RULE_DOCS_L" ] && [ -n "$RULE_ADDS_L" ] && [ -n "$CORE_RULES_L" ] \
    && ok "[106] RULE_DOCS, RULE_ADDS and CORE_RULES read" || bad "[106] a list could not be read"
  SHIPPED=$( {
    printf '.claude/rules/%s\n' $CORE_RULES_L $RULE_ADDS_L
    printf '.claude/docs/%s\n' $RULE_DOCS_L
    bash scripts/template-autosync.sh --list-core-scripts | sed 's#^#scripts/#'
    git ls-files .claude/skills
  } | sort -u)
  # Docs a project removes by stack decision (scripts/sync-prompt.md: no UI drops the checklist, no
  # live4 drops spot-architecture.md, a pure mobile app drops deployment.md). They are cited by path,
  # some from code paths that cannot be reworded, and adding them back on every sync would undo the
  # decision (106 adversarial review #1). So they are never added, and a citation of one is expected.
  # Stack RULES get no such list: files every project receives name them without the path.
  DECISION_DOCS="deployment.md spot-architecture.md spec-testing-checklist.md"
  for d in $DECISION_DOCS; do
    if grep -qxF "$d" <<< "$(printf '%s\n' $RULE_DOCS_L)"; then bad "[106] $d is a stack decision and must not be in RULE_DOCS"; else ok "[106] $d (a stack decision) is not added"; fi
  done
  # gaps <file>... : each citation of an existing template doc or rule that no list adds.
  gaps() { printf '%s\n' "$@" | RD="$RULE_DOCS_L $DECISION_DOCS" RA="$RULE_ADDS_L $CORE_RULES_L" python3 -c '
import os, re, sys
cite = re.compile(r"(?<![\w$/.-])\.claude/(rules|docs)/([A-Za-z0-9._-]+\.md)")
docs, rules = set(os.environ["RD"].split()), set(os.environ["RA"].split())
for rel in sys.stdin.read().split():
    if not os.path.isfile(rel): continue
    for i, line in enumerate(open(rel, encoding="utf-8", errors="replace"), 1):
        for kind, name in cite.findall(line):
            if not os.path.isfile(f".claude/{kind}/{name}"): continue   # a fixture name, not a file
            if name not in (docs if kind == "docs" else rules):
                print(f"{rel}:{i}: .claude/{kind}/{name}")
'; }
  GAPS=$(gaps $SHIPPED)
  if [ -z "$GAPS" ]; then ok "[106] every cited doc is in RULE_DOCS and every cited rule is CORE or in RULE_ADDS"
  else bad "[106] cited but never added to an existing project:"; printf '%s\n' "$GAPS" | sed 's/^/         /'; fi
  # Sabotage: a planted citation of a doc outside RULE_DOCS and a stack rule must both be seen.
  OUTSIDE=$(ls .claude/docs | grep -vxF -f <(printf '%s\n' $RULE_DOCS_L $DECISION_DOCS) | head -1)
  printf 'see .claude/docs/%s and .claude/rules/%s\n' "$OUTSIDE" dotnet.md > "$TMP/sab.md"
  same "[106] sabotage: a planted doc gap and stack-rule citation are both seen" "$(gaps "$TMP/sab.md" | wc -l | tr -d ' ')" 2
else
  echo "== [106] R4 parity: skipped downstream (no template tree to compare against) =="
fi

echo ""
echo "template-autosync-ships: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

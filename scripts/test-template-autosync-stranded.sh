#!/bin/bash
# Tests the stranded-writes detector in scripts/template-autosync.sh (spec 007bf).
#
# The bug it guards: four arms of the sync write to the working tree and do not commit
# (--no-commit, --ignore-in-progress mid-operation, a failed `git add`, a failed commit), and on
# every one of them the stamp is still advanced. The early exit at the top of the script reads the
# stamp, so from that moment every run prints `[ok] already at template` and nothing else — the run
# that stranded the files is the last run that ever looks at them. `--force` does not recover them
# either: the bytes on disk already match the template, so the copy loop writes nothing.
#
# End-to-end, not function extraction, because half of what is under test is WHERE the block
# renders — the [ok] early exit, --check/--dry-run, and the end of a full sync.
#
# Run: bash scripts/test-template-autosync-stranded.sh

set -u
cd "$(dirname "$0")/.." || exit 1
SCRIPT="$PWD/scripts/template-autosync.sh"
[ -f "$SCRIPT" ] || { echo "FAIL: template-autosync.sh not found"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
has()   { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 (missing '$3' in: $(printf '%s' "$2" | tr '\n' '|'))" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1 (unexpected '$3')" ;; *) ok "$1" ;; esac; }
same()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$3', got '$2')"; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# A template and a project already in sync, then the template moves — so the next sync has exactly
# two files to write. Named per case so the cases cannot contaminate each other.
build() {
  R="$TMP/$1"; rm -rf "$R"; mkdir -p "$R"
  T="$R/template"; P="$R/project"

  mkdir -p "$T/scripts" "$T/.claude/rules" "$T/.claude/agents"
  cp "$SCRIPT" "$T/scripts/"
  echo prompt > "$T/scripts/sync-prompt.md"
  printf 'rule v1\n'  > "$T/.claude/rules/demo-rule.md"
  printf 'agent v1\n' > "$T/.claude/agents/demo-agent.md"
  git -C "$T" init -q -b main
  git -C "$T" config user.email t@t; git -C "$T" config user.name T
  git -C "$T" add -A; git -C "$T" commit -qm init

  mkdir -p "$P/.claude/rules" "$P/.claude/agents" "$P/scripts"
  echo '{"name":"fake"}' > "$P/package.json"
  cp "$SCRIPT" "$P/scripts/"
  cp "$T/.claude/rules/demo-rule.md"   "$P/.claude/rules/"
  cp "$T/.claude/agents/demo-agent.md" "$P/.claude/agents/"
  git -C "$P" init -q -b main
  git -C "$P" config user.email p@p; git -C "$P" config user.name P
  git -C "$P" add -A; git -C "$P" commit -qm init

  sync "$P" "$T" --quiet >/dev/null 2>&1   # establishes the manifest
  git -C "$P" add -A >/dev/null 2>&1; git -C "$P" commit -qm baseline >/dev/null 2>&1

  printf 'rule v2\n'  > "$T/.claude/rules/demo-rule.md"
  printf 'agent v2\n' > "$T/.claude/agents/demo-agent.md"
  git -C "$T" add -A; git -C "$T" commit -qm bump
}

sync() { _p="$1"; _t="$2"; shift 2; ( cd "$_p" && CLAUDE_TEMPLATE_DIR="$_t" bash scripts/template-autosync.sh "$@" 2>&1 ); }

echo "== AC-01: --no-commit strands, and every later run says so =="
build ac01
OUT=$(sync "$P" "$T" --no-commit)
has  "the stranding run reports it"        "$OUT" "[stranded]"
OUT=$(sync "$P" "$T")
has  "the next run still says [ok]"        "$OUT" "[ok] already at template"
has  "…and now names the rule"             "$OUT" "modified   .claude/rules/demo-rule.md"
has  "…and the agent"                      "$OUT" "modified   .claude/agents/demo-agent.md"
has  "…and its own stamp"                  "$OUT" "modified   .claude/.template-sync"
OUT=$(sync "$P" "$T")
has  "and the run after that, unchanged"   "$OUT" "[stranded]"

echo "== AC-02: a failed \`git add\` strands, and the report outlives the [stage] block =="
build ac02
touch "$P/.git/index.lock"
OUT=$(sync "$P" "$T"); rm -f "$P/.git/index.lock"
has  "007av's transient block still fires" "$OUT" "[stage] git staged NOTHING"
has  "and the persistent one beside it"    "$OUT" "[stranded]"
OUT=$(sync "$P" "$T")
hasnt "the transient one is gone"          "$OUT" "[stage] git staged NOTHING"
has  "the persistent one is not"           "$OUT" "[stranded]"
has  "naming the rule"                     "$OUT" "modified   .claude/rules/demo-rule.md"

echo "== AC-03: mid-rebase, continued rather than aborted =="
build ac03
( cd "$P"
  git checkout -q -b side; printf 'x\n' > f.txt; git add f.txt; git commit -qm side
  git checkout -q main;    printf 'y\n' > f.txt; git add f.txt; git commit -qm main
  git rebase side >/dev/null 2>&1 ) || true
sync "$P" "$T" --ignore-in-progress --quiet >/dev/null 2>&1
( cd "$P" && printf 'z\n' > f.txt && git add f.txt && GIT_EDITOR=true git rebase --continue ) >/dev/null 2>&1
OUT=$(sync "$P" "$T")
has  "the finished rebase leaves them named" "$OUT" "[stranded]"
has  "naming the rule"                       "$OUT" "modified   .claude/rules/demo-rule.md"

echo "== AC-04: a created CORE rule is named, and named untracked =="
build ac04
printf 'core rule\n' > "$T/.claude/rules/continuous-execution.md"
git -C "$T" add -A; git -C "$T" commit -qm core
sync "$P" "$T" --no-commit --quiet >/dev/null 2>&1
OUT=$(sync "$P" "$T")
has  "the created CORE rule is named"      "$OUT" "untracked  .claude/rules/continuous-execution.md"
has  "untracked is listed before modified" "$(printf '%s' "$OUT" | grep -n 'untracked \|modified ' | head -1)" "untracked"

echo "== AC-05: a file the DEVELOPER edited afterwards is not named =="
build ac05
sync "$P" "$T" --quiet >/dev/null 2>&1          # a clean, committed sync
printf 'my own edit\n' > "$P/.claude/rules/demo-rule.md"
OUT=$(sync "$P" "$T")
hasnt "silent about the developer's own edit" "$OUT" "[stranded]"
# and the same file, still on its manifest hash, IS named
git -C "$P" checkout -- .claude/rules/demo-rule.md
printf 'rule v3\n' > "$T/.claude/rules/demo-rule.md"; git -C "$T" add -A; git -C "$T" commit -qm v3
sync "$P" "$T" --no-commit --quiet >/dev/null 2>&1
OUT=$(sync "$P" "$T")
has  "but the sync's own write is"            "$OUT" "modified   .claude/rules/demo-rule.md"

echo "== AC-06: an ignored untracked manifest path is not named =="
build ac06
printf 'core rule\n' > "$T/.claude/rules/continuous-execution.md"
git -C "$T" add -A; git -C "$T" commit -qm core
printf '.claude/rules/continuous-execution.md\n' > "$P/.gitignore"
git -C "$P" add .gitignore; git -C "$P" commit -qm ignore
sync "$P" "$T" --no-commit --quiet >/dev/null 2>&1
OUT=$(sync "$P" "$T")
hasnt "the ignored path is not named"      "$OUT" "continuous-execution.md"
has  "the rest still is"                   "$OUT" "modified   .claude/rules/demo-rule.md"

echo "== AC-07: a clean synced project is silent in every mode =="
build ac07
sync "$P" "$T" --quiet >/dev/null 2>&1
for M in "" --check --dry-run --force; do
  OUT=$(sync "$P" "$T" $M)
  hasnt "silent on '${M:-<none>}'"         "$OUT" "[stranded]"
done

echo "== AC-08: --check and --dry-run render it when the template has ALSO moved =="
build ac08
sync "$P" "$T" --no-commit --quiet >/dev/null 2>&1     # strand at this template
printf 'rule v3\n' > "$T/.claude/rules/demo-rule.md"   # then move the template on
git -C "$T" add -A; git -C "$T" commit -qm v3
OUT=$(sync "$P" "$T" --check)
has  "--check takes the [check] path"      "$OUT" "[check] template"
has  "…and renders the block"              "$OUT" "[stranded]"
OUT=$(sync "$P" "$T" --dry-run)
has  "--dry-run renders it too"            "$OUT" "[stranded]"

echo "== AC-09: a full sync with work to do reports pre-existing stranded paths =="
build ac09
sync "$P" "$T" --no-commit --quiet >/dev/null 2>&1
printf 'agent v3\n' > "$T/.claude/agents/demo-agent.md"
git -C "$T" add -A; git -C "$T" commit -qm v3
OUT=$(sync "$P" "$T")
has  "the sync did work"                   "$OUT" "[synced]"
has  "…and still reported them"            "$OUT" "[stranded]"

echo "== AC-10: nothing but the output changed =="
build ac10
OUT=$(sync "$P" "$T"); RC=$?
same "exit 0 on a healthy sync"            "$RC" "0"
BEFORE=$(git -C "$P" rev-parse HEAD)
build ac10b
OUT=$(sync "$P" "$T" --no-commit); RC=$?
same "exit 0 on a stranding run"           "$RC" "0"
same "no commit was made"                  "$(git -C "$P" log --oneline | wc -l | tr -d ' ')" "2"
same "nothing was staged"                  "$(git -C "$P" diff --cached --name-only | wc -l | tr -d ' ')" "0"
has  "the files are on disk as before"     "$(cat "$P/.claude/rules/demo-rule.md")" "rule v2"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]

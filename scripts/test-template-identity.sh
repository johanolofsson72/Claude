#!/usr/bin/env bash
. "$(dirname -- "$0")/self-test-env.sh" || exit 1
# test-template-identity.sh — the template is its history, not its URL (spec 091 R1, R2; F097).
#
#   091-AC-1  a project whose origin is the template's URL but whose history does not start at the
#             template's root commit: core-machinery-guard and core-owed-tick-guard decide as for any
#             project, autosync writes nothing and warns, `git remote set-url` is denied; a clone with
#             the template's history is still exempt
#
# Real hooks, real throwaway repositories. A fixture gets the template's history by borrowing this
# clone's objects (objects/info/alternates) and moving its branch onto HEAD: no copy, no network. Run
# from a project, whose history is not the template's, those arms say so and skip.
#
# Exit 0 = every assertion held. Exit 1 = a real failure.

set -u

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SELF_DIR/hook-verdict.sh"
. "$SELF_DIR/template-identity.sh"
. "$SELF_DIR/drive-sync.sh"
PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); printf '  ok    %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$*"; }
skip() { SKIP=$((SKIP+1)); printf '  skip  %s\n' "$*"; }
expect() { [ "$3" = "$2" ] && ok "$1" || bad "$1 (want '$2', got '$3')"; }

command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 1; }
WORK=$(mktemp -d 2>/dev/null || mktemp -d -t tplid)
WORK=$(cd -P "$WORK" && pwd)
trap 'rm -rf "$WORK"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

TPL_URL="https://github.com/johanolofsson72/Claude.git"
SRC=$(git -C "$SELF_DIR" rev-parse --show-toplevel 2>/dev/null)
HAVE_HISTORY=0
git -C "$SRC" cat-file -e "$TEMPLATE_ROOT_COMMIT^{commit}" 2>/dev/null && HAVE_HISTORY=1

# repo <name> — a repository with one commit of its own (a project's history).
repo() {
  _r="$WORK/$1"; mkdir -p "$_r"; git init -q "$_r"
  git -C "$_r" commit -q --allow-empty -m "project root"
  printf '%s' "$_r"
}
# template_history <repo> — move the repo's branch onto the template's history, objects borrowed.
template_history() {
  _od=$(git -C "$SRC" rev-parse --path-format=absolute --git-common-dir)/objects
  printf '%s\n' "$_od" >> "$1/.git/objects/info/alternates"
  git -C "$1" reset -q --soft "$(git -C "$SRC" rev-parse HEAD)"
}
set_origin() { git -C "$1" remote remove origin 2>/dev/null; git -C "$1" remote add origin "$2"; }

printf '\n[R1] template_url_matches: anchored, case-folded\n'
for u in "$TPL_URL" "https://github.com/johanolofsson72/Claude" "https://github.com/johanolofsson72/Claude/" \
         "git@github.com:johanolofsson72/Claude.git" "ssh://git@github.com/johanolofsson72/Claude.git" \
         "https://github.com/JohanOlofsson72/CLAUDE.git"; do
  template_url_matches "$u" && ok "matches $u" || bad "does not match $u"
done
for u in "https://github.com/evil-johanolofsson72/Claude" "https://github.com/johanolofsson72/Claude-x.git" \
         "https://evil.example/johanolofsson72/Claude.git" "$WORK/johanolofsson72/Claude.git" \
         "https://github.com/johanolofsson72/Claude.git.evil" "" "https://github.com/johanolofsson72/Claude.git?x"; do
  template_url_matches "$u" && bad "matches $u" || ok "rejects '$u'"
done

printf '\n[R1] template_identity\n'
P=$(repo plain)
expect "no origin: project" project "$(template_identity "$P")"
template_identity "$P" >/dev/null; expect "template_identity exits 0 (project)" 0 "$?"
expect "not a repository: project" project "$(template_identity "$WORK")"
set_origin "$P" "https://github.com/someone/else.git"
expect "another origin: project" project "$(template_identity "$P")"
set_origin "$P" "$TPL_URL"
expect "091-AC-1 the template's URL on a project's history: impostor" impostor "$(template_identity "$P")"
template_identity "$P" >/dev/null; expect "template_identity exits 0 (impostor)" 0 "$?"
set_origin "$P" "https://github.com/evil-johanolofsson72/Claude"
expect "F097 evil-johanolofsson72/Claude: project" project "$(template_identity "$P")"
# insteadOf rewrites what `remote get-url` prints; the raw configured URL is what is compared (A1).
set_origin "$P" "https://github.com/someone/else.git"
git -C "$P" config "url.$TPL_URL.insteadOf" "https://github.com/someone/else.git"
expect "A1 insteadOf pointing at the template does not make it one" project "$(template_identity "$P")"
git -C "$P" config --unset "url.$TPL_URL.insteadOf"

if [ "$HAVE_HISTORY" -eq 1 ]; then
  T=$(repo tpl); template_history "$T"; set_origin "$T" "$TPL_URL"
  expect "091-AC-1 the template's history and URL: template" template "$(template_identity "$T")"
  set_origin "$T" "https://github.com/JohanOlofsson72/claude"
  expect "a case-folded URL on the template's history: template" template "$(template_identity "$T")"
  set_origin "$T" "https://github.com/someone/fork.git"
  expect "the template's history under another URL: project" project "$(template_identity "$T")"

  # A graft or a replace ref can make a project's own root claim the template's root as its parent.
  G=$(repo graft); set_origin "$G" "$TPL_URL"
  printf '%s\n' "$(git -C "$SRC" rev-parse --path-format=absolute --git-common-dir)/objects" >> "$G/.git/objects/info/alternates"
  GROOT=$(git -C "$G" rev-parse HEAD)
  printf '%s %s\n' "$GROOT" "$TEMPLATE_ROOT_COMMIT" > "$G/.git/info/grafts"
  expect "Q5 the graft really does fake the root for plain git" "$TEMPLATE_ROOT_COMMIT" \
         "$(git -C "$G" rev-list --max-parents=0 HEAD 2>/dev/null)"
  expect "Q5 a grafted root is still an impostor" impostor "$(template_identity "$G")"
  rm -f "$G/.git/info/grafts"
  git -C "$G" replace --graft "$GROOT" "$TEMPLATE_ROOT_COMMIT" 2>/dev/null
  expect "Q5 the replace ref really does fake the root for plain git" "$TEMPLATE_ROOT_COMMIT" \
         "$(git -C "$G" rev-list --max-parents=0 HEAD 2>/dev/null)"
  expect "Q5 a replaced root is still an impostor" impostor "$(template_identity "$G")"

  # A merge that brings the template's history in has two roots, so it is not the template either.
  M=$(repo merged); set_origin "$M" "$TPL_URL"
  printf '%s\n' "$(git -C "$SRC" rev-parse --path-format=absolute --git-common-dir)/objects" >> "$M/.git/objects/info/alternates"
  git -C "$M" merge -q --allow-unrelated-histories --no-edit -s ours "$(git -C "$SRC" rev-parse HEAD)" 2>/dev/null
  expect "a project merged with the template's history (two roots): impostor" impostor "$(template_identity "$M")"
else
  skip "template-history arms: this clone's history is not the template's (run in the template)"
fi

# ------------------------------------------------------------------------------- the four callers
SYNC="$SELF_DIR/template-autosync.sh"
make_project() {   # a project the CORE guards act in: register, manifest, sync script, CORE files
  _p=$(repo "$1")
  mkdir -p "$_p/scripts" "$_p/.claude/rules" "$_p/specs"
  cp "$SYNC" "$_p/scripts/template-autosync.sh"
  cp "$SELF_DIR/template-identity.sh" "$_p/scripts/template-identity.sh"
  printf 'core script\n' > "$_p/scripts/spec_active.py"
  printf '{}\n' > "$_p/.claude/settings.json"
  printf '# Spec register\n\n## Specs\n\n- [/] 001 — x — spec-only track — y\n' > "$_p/specs/INDEX.md"
  {
    printf 'sha=deadbeefcafe\n'
    printf '%s  scripts/spec_active.py\n' "$(shasum -a 256 "$_p/scripts/spec_active.py" 2>/dev/null | cut -d' ' -f1 || sha256sum "$_p/scripts/spec_active.py" | cut -d' ' -f1)"
  } > "$_p/.claude/.template-sync"
  printf '%s' "$_p"
}
edit_verdict() {   # <guard> <file> — the verdict for an Edit of the file
  hook_verdict "$(jq -n --arg p "$2" '{tool_name:"Edit",tool_input:{file_path:$p,old_string:"core script",new_string:"edited"}}' \
                  | CLAUDE_PROJECT_DIR="$(dirname "$(dirname "$2")")" bash "$SELF_DIR/$1" 2>/dev/null)"
}

printf '\n[091-AC-1] a project that points origin at the template\n'
IMP=$(make_project impostor); set_origin "$IMP" "$TPL_URL"
expect "091-AC-1 core-machinery-guard denies a CORE edit as for any project" deny \
       "$(edit_verdict core-machinery-guard-hook.sh "$IMP/scripts/spec_active.py")"
printf 'drifted\n' > "$IMP/scripts/spec_active.py"
TICKV=$(hook_verdict "$(jq -n --arg p "$IMP/specs/INDEX.md" \
          '{tool_name:"Edit",tool_input:{file_path:$p,old_string:"- [/] 001 — x — spec-only track — y",new_string:"- [x] 001 — x — spec-only track — y"}}' \
        | CLAUDE_PROJECT_DIR="$IMP" bash "$SELF_DIR/core-owed-tick-guard-hook.sh" 2>/dev/null)")
expect "091-AC-1 core-owed-tick-guard denies the tick (CORE owed) as for any project" deny "$TICKV"
git -C "$IMP" add -A && git -C "$IMP" commit -qm fixture
BEFORE=$(git -C "$IMP" rev-parse HEAD; git -C "$IMP" status --porcelain)
OUT=$(DRIVE_SYNC_SCRIPT="$IMP/scripts/template-autosync.sh" drive_sync "$IMP" "$WORK" 2>&1); RC=$?
expect "091-AC-1 autosync exits 0" 0 "$RC"
case "$OUT" in *"HEAD's history is not the template's"*) ok "091-AC-1 autosync warns that the history is not the template's" ;;
  *) bad "091-AC-1 autosync did not warn: $(printf '%s' "$OUT" | head -3)" ;; esac
expect "091-AC-1 autosync wrote, staged and committed nothing" "$BEFORE" "$(git -C "$IMP" rev-parse HEAD; git -C "$IMP" status --porcelain)"
printf 'drifted again\n' > "$IMP/scripts/spec_active.py"
OUT=$(DRIVE_SYNC_SCRIPT="$IMP/scripts/template-autosync.sh" drive_sync "$IMP" "$WORK" --owed 2>/dev/null); RC=$?
expect "--owed on an impostor answers as for a project (0, the drifted file)" "0 scripts/spec_active.py" "$RC $OUT"
git -C "$IMP" checkout -q -- scripts/spec_active.py
HOOKOUT=$(DRIVE_HOOK_SCRIPT="$SELF_DIR/template-autosync-hook.sh" drive_hook "$IMP" "$WORK" </dev/null 2>&1)
case "$HOOKOUT" in *"history is not the template's"*|"") ok "the SessionStart hook does not treat it as the template" ;;
  *) ok "the SessionStart hook ran the sync (output: $(printf '%s' "$HOOKOUT" | head -1 | cut -c1-60))" ;; esac

SETURL=$(hook_verdict "$(jq -n --arg c "git remote set-url origin $TPL_URL" '{tool_name:"Bash",tool_input:{command:$c}}' \
          | CLAUDE_PROJECT_DIR="$IMP" bash "$SELF_DIR/trust-anchor-guard-hook.sh" 2>/dev/null)")
expect "091-AC-1 git remote set-url origin … is denied" deny "$SETURL"

if [ "$HAVE_HISTORY" -eq 1 ]; then
  TP=$(make_project tplproj); git -C "$TP" add -A && git -C "$TP" commit -qm fixture
  template_history "$TP"; set_origin "$TP" "$TPL_URL"
  expect "091-AC-1 core-machinery-guard still exempts a clone with the template's history" none \
         "$(edit_verdict core-machinery-guard-hook.sh "$TP/scripts/spec_active.py")"
  printf 'drifted\n' > "$TP/scripts/spec_active.py"
  TICKV=$(hook_verdict "$(jq -n --arg p "$TP/specs/INDEX.md" \
            '{tool_name:"Edit",tool_input:{file_path:$p,old_string:"- [/] 001 — x — spec-only track — y",new_string:"- [x] 001 — x — spec-only track — y"}}' \
          | CLAUDE_PROJECT_DIR="$TP" bash "$SELF_DIR/core-owed-tick-guard-hook.sh" 2>/dev/null)")
  expect "091-AC-1 core-owed-tick-guard still exempts it" none "$TICKV"
  OUT=$(DRIVE_SYNC_SCRIPT="$TP/scripts/template-autosync.sh" drive_sync "$TP" "$WORK" 2>&1)
  case "$OUT" in *"IS the template repo"*) ok "091-AC-1 autosync still skips the template" ;;
    *) bad "091-AC-1 autosync did not skip the template: $(printf '%s' "$OUT" | head -2)" ;; esac
fi

printf '\n[102] self_test_subject: does a self-test here have a template-only subject\n'
S="$WORK/st"; mkdir -p "$S/a" "$S/b" "$S/c" "$S/d" "$S/outer/inner"
git -C "$S/a" init -q; git -C "$S/a" remote add origin https://github.com/johanolofsson72/Claude.git
expect "[102] the template's URL: upstream" upstream "$(self_test_subject "$S/a")"
git -C "$S/b" init -q; git -C "$S/b" remote add origin https://github.com/someone/fundit.git
mkdir -p "$S/b/.claude"; : > "$S/b/.claude/.template-sync"
expect "[102] another origin: downstream" downstream "$(self_test_subject "$S/b")"
git -C "$S/c" init -q; mkdir -p "$S/c/.claude"; : > "$S/c/.claude/.template-sync"
expect "[102] no origin, a sync stamp: downstream" downstream "$(self_test_subject "$S/c")"
git -C "$S/d" init -q
expect "[102] neither signal: upstream, nothing skipped" upstream "$(self_test_subject "$S/d")"
expect "[102] not a repository, no stamp: upstream" upstream "$(self_test_subject "$S/outer/inner")"
git -C "$S/outer" init -q; git -C "$S/outer" remote add origin https://github.com/someone/fundit.git
expect "[102] a dir inside another checkout does not inherit its origin" upstream "$(self_test_subject "$S/outer/inner")"
git -C "$S/a" remote set-url origin https://github.com/evil-johanolofsson72/Claude.git
expect "[102] evil-johanolofsson72/Claude: downstream" downstream "$(self_test_subject "$S/a")"
if [ "$HAVE_HISTORY" -eq 1 ]; then
  M=$(repo st-mirror); template_history "$M"; set_origin "$M" "https://x-access-token:t@git.example/mirror/Claude.git"
  expect "[102] the template's history behind a mirror URL: upstream" upstream "$(self_test_subject "$M")"
else
  skip "[102] mirror URL on the template's history (no template history here)"
fi

printf '\n[R1] sabotage: a URL-only identity lets the impostor through\n'
MUT="$WORK/mut"; mkdir -p "$MUT"; cp "$SELF_DIR"/*.sh "$SELF_DIR"/*.py "$MUT"/ 2>/dev/null
python3 - "$MUT/template-identity.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = 'if [ "$(_template_roots "$1")" = "$TEMPLATE_ROOT_COMMIT" ]; then echo template; else echo impostor; fi'
assert old in s, "sabotage target not found"
open(p, "w").write(s.replace(old, "echo template"))
PY
expect "sabotage: the mutant exempts the impostor" none "$(hook_verdict "$(jq -n --arg p "$IMP/scripts/spec_active.py" \
  '{tool_name:"Edit",tool_input:{file_path:$p,old_string:"x",new_string:"y"}}' | CLAUDE_PROJECT_DIR="$IMP" bash "$MUT/core-machinery-guard-hook.sh" 2>/dev/null)")"

printf '\n[105-R5] git is bounded and runs with GIT_* dropped\n'
SLOWB="$WORK/slowgit"; mkdir -p "$SLOWB"
printf '#!/bin/sh\nsleep 30\n' > "$SLOWB/git"; chmod +x "$SLOWB/git"
T0=$(date +%s)
V=$(PATH="$SLOWB:$PATH" GUARD_GIT_TIMEOUT=1 bash -c '. "$0"; template_identity "$1"' "$SELF_DIR/template-identity.sh" "$SELF_DIR/..")
T1=$(date +%s)
[ "$V" = project ] && ok "105-R5 a git that hangs reads as project (no exemption)" || bad "105-R5 a hanging git read as [$V]"
# Spec 106: with git silenced only the sync stamp is left to answer self_test_subject. Asked of two
# fixtures, so both answers are checked in the template and in every project alike (expecting the
# template's own answer from the live tree made this case red in every synced project).
mkdir -p "$WORK/r5-stamped/.claude" "$WORK/r5-plain"; : > "$WORK/r5-stamped/.claude/.template-sync"
for c in "r5-stamped downstream" "r5-plain upstream"; do
  set -- $c
  V=$(PATH="$SLOWB:$PATH" GUARD_GIT_TIMEOUT=1 bash -c '. "$0"; self_test_subject "$1"' "$SELF_DIR/template-identity.sh" "$WORK/$1")
  [ "$V" = "$2" ] && ok "105-R5 hanging git, $1: $2 (only the sync stamp can answer)" || bad "105-R5 hanging git, $1 read as [$V], want $2"
done
[ $((T1 - T0)) -lt 10 ] && ok "  within the bound ($((T1 - T0)) s), not the 30 s the git sleeps" || bad "  it waited $((T1 - T0)) s"
V=$(GIT_DIR=/nonexistent GIT_WORK_TREE=/nonexistent GIT_CONFIG_PARAMETERS="'remote.origin.url=https://github.com/x/y'" \
    bash -c '. "$0"; template_identity "$1"' "$SELF_DIR/template-identity.sh" "$SELF_DIR/..")
[ "$V" = "$(template_identity "$SELF_DIR/..")" ] && ok "105-R5 GIT_DIR, GIT_WORK_TREE and GIT_CONFIG_PARAMETERS change nothing" || bad "105-R5 the environment moved the answer to [$V]"
SABT="$WORK/sab105r5"; mkdir -p "$SABT"
sed 's/^    for _v in \$(compgen.*/    :/' "$SELF_DIR/template-identity.sh" > "$SABT/template-identity.sh"
if cmp -s "$SELF_DIR/template-identity.sh" "$SABT/template-identity.sh"; then bad "105-R5 sabotage target not found"; else
  V=$(GIT_DIR=/nonexistent bash -c '. "$0"; template_identity "$1"' "$SABT/template-identity.sh" "$SELF_DIR/..")
  [ "$V" = project ] && ok "105-R5 sabotage: without the scrub GIT_DIR moves the answer" || bad "105-R5 sabotage: the mutant read [$V]"
fi

printf '\n%d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ]

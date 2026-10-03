#!/usr/bin/env bash
. "$(dirname -- "$0")/self-test-env.sh" || exit 1
# test-guard-canonical-paths.sh — the Edit-path guards judge the file a write lands on (spec 090).
#
#   090-AC-1  SCRIPTS/guarded.sh, scripts/GUARDED.SH, a tick through specs/index.md, and an NFD-spelled
#             CLAUDE_PROJECT_DIR over an NFC path with a planted src/.git are judged as the stored file
#   090-AC-2  a symlinked file or directory, App.cs., a new source extension and a NotebookEdit reach
#             the parser and are denied; the template wiring sends NotebookEdit to the five guards
#   090-AC-3  a --no-checkout worktree and a .git planted at a subdirectory anchor keep the project's
#             register; a nested repository with a commit at the anchor is still its own root
#
# R1 stored names · R2 prechecks · R3 extension · R4 NotebookEdit · R6 anchor .git · R7 worktree.
# Every requirement has a sabotage arm: a copy of the scripts with that one piece removed must let
# its arm through, so the arms cannot pass for a reason other than the code under test. The case and
# Unicode arms need a folding file system (macOS); elsewhere they print a skip line.
#
# Exit 0 = every assertion held. Exit 1 = a real failure.

set -u

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SELF_DIR/hook-verdict.sh"
BASH_BIN=$(command -v bash)
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok    %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$*"; }
skip() { printf '  skip  %s\n' "$*"; }
expect() { [ "$3" = "$2" ] && ok "$1" || bad "$1 (want $2, got $3)"; }

command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required"; exit 1; }

WORK=$(mktemp -d 2>/dev/null || mktemp -d -t guardcanon)
WORK=$(cd -P "$WORK" && /bin/pwd -P)
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home"; mkdir -p "$HOME"
unset ALLOW_CORE_MACHINERY_EDIT ALLOW_TICK_WITH_CORE_OWED
GIT="git -c user.name=t -c user.email=t@t -c init.defaultBranch=main"

# verdict <scripts-dir> <guard> <payload> [anchor] -> deny | none | ...
# A guard must exit 0: the CLI reads its JSON only then, and exit 1 is a non-blocking error that lets
# the call through. So a non-zero exit is its own verdict here, never "none".
verdict() {
  local dir="$1" guard="$2" payload="$3" anchor="${4:-}" out rc
  if [ -n "$anchor" ]; then
    out=$(printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$anchor" "$BASH_BIN" "$dir/$guard" 2>/dev/null); rc=$?
  else
    out=$(printf '%s' "$payload" | "$BASH_BIN" "$dir/$guard" 2>/dev/null); rc=$?
  fi
  [ "$rc" -eq 0 ] || { echo "exit-$rc"; return; }
  hook_verdict "$out"
}
edit_payload() { jq -cn --arg p "$1" --arg c "${2:-}" '{tool_name:"Edit",tool_input:{file_path:$p,old_string:"a",new_string:"b"}} + (if $c == "" then {} else {cwd:$c} end)'; }
nb_payload()   { jq -cn --arg p "$1" '{tool_name:"NotebookEdit",tool_input:{notebook_path:$p,new_source:"x = 1"}}'; }
tick_payload() { jq -cn --arg p "$1" '{tool_name:"Edit",tool_input:{file_path:$p,old_string:"- [/] 001",new_string:"- [x] 001"}}'; }

# A code project: package.json, a register whose active full-track spec has spec.md only (so the
# interview and pipeline guards deny every source edit), .claude/, a stub sync that calls
# scripts/guarded.sh CORE and owes it, and one commit.
make_project() {
  local p="$1"
  mkdir -p "$p/src" "$p/scripts" "$p/specs/001-x" "$p/.claude/rules" "$p/docs"
  $GIT init -q "$p"
  echo '{}' > "$p/package.json"
  printf '# Spec register\n\n## Specs\n\n- [/] 001 — x — full track — goal\n' > "$p/specs/INDEX.md"
  echo "# x" > "$p/specs/001-x/spec.md"
  cat > "$p/scripts/template-autosync.sh" <<'STUB'
#!/bin/bash
case "$1" in
  --is-core) [ "$2" = scripts/guarded.sh ] && { echo "scripts/guarded.sh is CORE"; exit 0; }; exit 1 ;;
  --owed) echo "scripts/guarded.sh"; exit 0 ;;
  --unlisted) exit 1 ;;
esac
exit 1
STUB
  echo '#!/bin/bash' > "$p/scripts/guarded.sh"
  echo 'class App {}' > "$p/src/App.cs"
  ( cd "$p" && $GIT add -A && $GIT commit -qm init ) >/dev/null 2>&1
}

# A copy of the scripts with one change applied by python: sabotage <name> <file> <old> <new>
sabotage() {
  local d="$WORK/mut-$1"
  rm -rf "$d"; mkdir -p "$d"
  cp "$SELF_DIR"/*.sh "$SELF_DIR"/*.py "$d"/ 2>/dev/null
  python3 - "$d/$2" "$3" "$4" <<'PY' || { echo "sabotage target not found in $2" >&2; return 1; }
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
if old not in s:
    sys.exit(1)
open(p, "w").write(s.replace(old, new))
PY
  printf '%s' "$d"
}

P="$WORK/proj"; make_project "$P"
FOLDS=0
[ -d "$(printf '%s' "$P" | tr '[:lower:]' '[:upper:]')" ] && FOLDS=1

printf '\n[baseline] the stored spelling is denied\n'
expect "core-machinery denies scripts/guarded.sh" deny "$(verdict "$SELF_DIR" core-machinery-guard-hook.sh "$(edit_payload "$P/scripts/guarded.sh")" "$P")"
expect "core-owed-tick denies a tick of specs/INDEX.md" deny "$(verdict "$SELF_DIR" core-owed-tick-guard-hook.sh "$(tick_payload "$P/specs/INDEX.md")" "$P")"
expect "spec-interview denies src/App.cs" deny "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$P/src/App.cs")" "$P")"

printf '\n[R1] a path spelled in another case is the stored file  (090-AC-1)\n'
if [ "$FOLDS" -eq 1 ]; then
  expect "090-AC-1 core-machinery denies SCRIPTS/guarded.sh" deny "$(verdict "$SELF_DIR" core-machinery-guard-hook.sh "$(edit_payload "$P/SCRIPTS/guarded.sh")" "$P")"
  expect "090-AC-1 core-machinery denies scripts/GUARDED.SH" deny "$(verdict "$SELF_DIR" core-machinery-guard-hook.sh "$(edit_payload "$P/scripts/GUARDED.SH")" "$P")"
  expect "090-AC-1 core-owed-tick denies a tick through specs/index.md" deny "$(verdict "$SELF_DIR" core-owed-tick-guard-hook.sh "$(tick_payload "$P/specs/index.md")" "$P")"
  expect "090-AC-1 core-owed-tick denies a tick through SPECS/INDEX.md" deny "$(verdict "$SELF_DIR" core-owed-tick-guard-hook.sh "$(tick_payload "$P/SPECS/INDEX.md")" "$P")"
  UPP=$(printf '%s' "$P" | tr '[:lower:]' '[:upper:]')
  expect "a file and an anchor both spelled in upper case: core-machinery denies" deny "$(verdict "$SELF_DIR" core-machinery-guard-hook.sh "$(edit_payload "$UPP/SCRIPTS/GUARDED.SH")" "$UPP")"
  OUT=$(printf '%s' "$(edit_payload "$P/SCRIPTS/guarded.sh")" | CLAUDE_PROJECT_DIR="$P" "$BASH_BIN" "$SELF_DIR/core-machinery-guard-hook.sh" 2>/dev/null)
  case "$OUT" in *SCRIPTS*) bad "the deny names the typed spelling SCRIPTS" ;; *) ok "the deny names the stored file, not the typed spelling" ;; esac

  NFC=$(printf 'caf\xc3\xa9'); NFD=$(printf 'cafe\xcc\x81')
  mkdir -p "$WORK/$NFC"; Q="$WORK/$NFC/proj"; make_project "$Q"; : > "$Q/src/.git"
  expect "090-AC-1 NFD anchor, NFC file, planted src/.git: spec-interview denies" deny "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$Q/src/main.py")" "$WORK/$NFD/proj")"
  expect "NFC anchor, NFD file, planted src/.git: spec-interview denies" deny "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$WORK/$NFD/proj/src/main.py")" "$Q")"

  M=$(sabotage pwd guard-lib.sh 'then /bin/pwd -P 2>/dev/null && return 0; fi' 'then :; fi')
  expect "sabotage: builtin pwd only — SCRIPTS/guarded.sh is let through" none "$(verdict "$M" core-machinery-guard-hook.sh "$(edit_payload "$P/SCRIPTS/guarded.sh")" "$P")"
  expect "sabotage: builtin pwd only — the NFD anchor misses the NFC file" none "$(verdict "$M" spec-interview-guard-hook.sh "$(edit_payload "$Q/src/main.py")" "$WORK/$NFD/proj")"
  M=$(sabotage stored guard-lib.sh '  [ $# -eq 1 ] && GUARD_STORED="$1"' '  :')
  expect "sabotage: no stored final name — scripts/GUARDED.SH is let through" none "$(verdict "$M" core-machinery-guard-hook.sh "$(edit_payload "$P/scripts/GUARDED.SH")" "$P")"
else
  skip "case and Unicode folding: this file system is case-sensitive"
fi
# A case-sensitive file system: two spellings are two files, and the stored-name lookup must not merge them.
if [ "$FOLDS" -eq 0 ]; then
  mkdir -p "$P/SCRIPTS"; echo x > "$P/SCRIPTS/guarded.sh"
  expect "case-sensitive: SCRIPTS/guarded.sh is a different, non-CORE file" none "$(verdict "$SELF_DIR" core-machinery-guard-hook.sh "$(edit_payload "$P/SCRIPTS/guarded.sh")" "$P")"
  rm -rf "$P/SCRIPTS"
fi

printf '\n[R2] a symlink anywhere in the path reaches the parser  (090-AC-2)\n'
ln -s ../src/App.cs "$P/docs/notes.txt"
ln -s ../scripts "$P/docs/tools"
ln -s ../specs/INDEX.md "$P/docs/reg.md"
ln -s plain.txt "$P/docs/alias.txt"; echo x > "$P/docs/plain.txt"
expect "090-AC-2 spec-interview denies docs/notes.txt -> src/App.cs" deny "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$P/docs/notes.txt")" "$P")"
expect "090-AC-2 pipeline-state denies docs/notes.txt -> src/App.cs" deny "$(verdict "$SELF_DIR" pipeline-state-guard-hook.sh "$(edit_payload "$P/docs/notes.txt")" "$P")"
expect "relative docs/notes.txt against the payload cwd: denied" deny "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "docs/notes.txt" "$P")" "$P")"
expect "090-AC-2 core-machinery denies docs/tools/guarded.sh (docs/tools -> scripts)" deny "$(verdict "$SELF_DIR" core-machinery-guard-hook.sh "$(edit_payload "$P/docs/tools/guarded.sh")" "$P")"
expect "core-owed-tick denies a tick through docs/reg.md -> specs/INDEX.md" deny "$(verdict "$SELF_DIR" core-owed-tick-guard-hook.sh "$(tick_payload "$P/docs/reg.md")" "$P")"
expect "control: a link to a text file is still allowed" none "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$P/docs/alias.txt")" "$P")"
expect "control: a plain text file is allowed" none "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$P/docs/plain.txt")" "$P")"
. "$SELF_DIR/guard-precheck.sh"
RAW=$(edit_payload "$WORK/home/x.txt")
mkdir -p "$WORK/real"; ln -s "$WORK/real" "$WORK/linked"
RAW_ABOVE=$(edit_payload "$WORK/linked/proj2/docs/x.txt")
if CLAUDE_PROJECT_DIR="$WORK/linked/proj2" guard_precheck_link "$RAW_ABOVE"; then bad "a link ABOVE the anchor sends every edit to the parser"; else ok "a link above the anchor is not tested (the spec 073 fast exit holds)"; fi
if guard_precheck_link "$RAW"; then bad "a plain path is reported as a link"; else ok "a plain path is no link"; fi
if guard_precheck_link "$(jq -cn '{tool_name:"Edit",tool_input:{file_path:"/x/App.cs"}}' | sed 's/A/\\u0041/')"; then ok "an escaped path goes to the parser"; else bad "an escaped path skipped the parser"; fi
M=$(sabotage link guard-precheck.sh 'guard_precheck_link() {' 'guard_precheck_link() { return 1;')
expect "sabotage: no link test — docs/notes.txt is let through" none "$(verdict "$M" spec-interview-guard-hook.sh "$(edit_payload "$P/docs/notes.txt")" "$P")"
expect "sabotage: no link test — docs/tools/guarded.sh is let through" none "$(verdict "$M" core-machinery-guard-hook.sh "$(edit_payload "$P/docs/tools/guarded.sh")" "$P")"

printf '\n[R3] the extension NTFS reads, and the new source extensions  (090-AC-2)\n'
for f in 'App.cs.' 'App.cs ' 'App.cs::$DATA' 'App.CS. .' 'q.sql' 'run.bat' 'run.cmd' 'mod.psm1' 'page.aspx' 'v.jsp' 't.ejs' 'a.coffee' 'b.mm' 'c.sol' 'main.tf' 'n.ipynb'; do
  expect "090-AC-2 spec-interview denies src/$f" deny "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$P/src/$f")" "$P")"
done
expect "pipeline-state denies src/App.cs." deny "$(verdict "$SELF_DIR" pipeline-state-guard-hook.sh "$(edit_payload "$P/src/App.cs.")" "$P")"
for f in 'README.md' 'notes.txt.' 'data.json ' 'App.cs.bak'; do
  expect "control: src/$f is allowed" none "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$P/src/$f")" "$P")"
done
lists=$(for g in spec-interview pipeline-state spec-register; do grep -m1 '^SOURCE_EXTS=' "$SELF_DIR/$g-guard-hook.sh"; done | sort -u | wc -l | tr -d ' ')
expect "SOURCE_EXTS is one list in the three guards" 1 "$lists"
M=$(sabotage ext guard-lib.sh '  _guard_ntfs_trim "${1##*/}"' '  GUARD_TRIMMED="${1##*/}"')
expect "sabotage: no NTFS trim — src/App.cs. is let through" none "$(verdict "$M" spec-interview-guard-hook.sh "$(edit_payload "$P/src/App.cs.")" "$P")"
r=$( . "$SELF_DIR/guard-lib.sh"; GUARD_NTFS=1; _guard_canon_walk "$P/scripts./guarded.sh" )
expect "NTFS: scripts./guarded.sh canonicalises to scripts/guarded.sh" "$P/scripts/guarded.sh" "$r"
r=$( . "$SELF_DIR/guard-lib.sh"; GUARD_NTFS=1; _guard_canon_walk "$P/src/.. /scripts/guarded.sh" )
expect "NTFS: '.. ' is .. before the walk reads it" "$P/scripts/guarded.sh" "$r"

printf '\n[R4] NotebookEdit is judged  (090-AC-2)\n'
expect "090-AC-2 spec-interview denies a NotebookEdit of src/n.ipynb" deny "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(nb_payload "$P/src/n.ipynb")" "$P")"
expect "pipeline-state denies a NotebookEdit of src/n.ipynb" deny "$(verdict "$SELF_DIR" pipeline-state-guard-hook.sh "$(nb_payload "$P/src/n.ipynb")" "$P")"
NR="$WORK/noreg"; make_project "$NR"; rm -f "$NR/specs/INDEX.md"
expect "spec-register denies a NotebookEdit with no register" deny "$(verdict "$SELF_DIR" spec-register-guard-hook.sh "$(nb_payload "$NR/src/n.ipynb")" "$NR")"
SETTINGS="$SELF_DIR/../.claude/settings.json"
MATCHER=$(jq -r '.hooks.PreToolUse[] | select([.hooks[]?.command] | map(test("spec-interview-guard-hook")) | any) | .matcher' "$SETTINGS" 2>/dev/null)
case "|$MATCHER|" in *"|NotebookEdit|"*) ok "090-AC-2 the template wires NotebookEdit to the five-guard block ($MATCHER)" ;;
  *) bad "090-AC-2 the five-guard block's matcher lacks NotebookEdit ($MATCHER)" ;; esac
N=$(jq -r '.hooks.PreToolUse[] | select([.hooks[]?.command] | map(test("spec-interview-guard-hook")) | any) | [.hooks[].command | capture("scripts/(?<s>[a-z-]+-guard-hook)").s] | join(" ")' "$SETTINGS" 2>/dev/null)
for g in spec-register pipeline-state spec-interview core-machinery core-owed-tick; do
  case " $N " in *" $g-guard-hook "*) ok "the block holds $g" ;; *) bad "the block lacks $g ($N)" ;; esac
done
M=$(sabotage nb guard-lib.sh '  if [ "$rc" -eq 0 ] && [ -z "$FILE" ]; then FILE=$(guard_field .tool_input.notebook_path); rc=$?; fi' '  :')
expect "sabotage: no notebook_path — the NotebookEdit is let through" none "$(verdict "$M" spec-interview-guard-hook.sh "$(nb_payload "$P/src/n.ipynb")" "$P")"

printf '\n[R6] a .git at a subdirectory anchor counts only as a repository with a commit  (090-AC-3, O1)\n'
S="$WORK/sub"; make_project "$S"; mkdir -p "$S/src/app"
: > "$S/src/app/.git"
expect "090-AC-3 an empty .git file at the anchor: denied on the project's register" deny "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$S/src/app/main.py")" "$S/src/app")"
rm -f "$S/src/app/.git"; mkdir "$S/src/app/.git"
expect "an empty .git directory at the anchor: denied" deny "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$S/src/app/main.py")" "$S/src/app")"
rm -rf "$S/src/app/.git"; $GIT init -q "$S/src/app"
expect "a fresh git init (no commit) at the anchor: denied" deny "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$S/src/app/main.py")" "$S/src/app")"
rm -rf "$S/src/app/.git"; printf 'gitdir: %s/.git\n' "$S" > "$S/src/app/.git"
expect "a .git file naming the outer git dir (rev-parse accepts it): denied" deny "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$S/src/app/main.py")" "$S/src/app")"
rm -f "$S/src/app/.git"; ( cd "$S/src/app" && $GIT init -q . && echo x > f && $GIT add f && $GIT commit -qm n ) >/dev/null 2>&1
expect "090-AC-3 a nested repository with a commit at the anchor is its own root (no register: allowed)" none "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$S/src/app/main.py")" "$S/src/app")"
T="$WORK/top"; make_project "$T"
expect "a project with nothing above it: its own .git is the root, as before" deny "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$T/src/main.py")" "$T")"
rm -rf "$S/src/app/.git"; : > "$S/src/app/.git"
M=$(sabotage anchor guard-lib.sh '    _guard_anchor_git_counts "$1"
    return' '    return 0')
expect "sabotage: no R6 check — the planted anchor .git is let through" none "$(verdict "$M" spec-interview-guard-hook.sh "$(edit_payload "$S/src/app/main.py")" "$S/src/app")"

printf '\n[R7] a worktree without its own register keeps the project'"'"'s  (090-AC-3)\n'
W="$WORK/wt"; make_project "$W"
( cd "$W" && $GIT worktree add -q --no-checkout .claude/worktrees/nc ) >/dev/null 2>&1
expect "090-AC-3 a --no-checkout worktree: spec-interview denies its src/main.py" deny "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$W/.claude/worktrees/nc/src/main.py")" "$W")"
expect "a --no-checkout worktree: pipeline-state denies" deny "$(verdict "$SELF_DIR" pipeline-state-guard-hook.sh "$(edit_payload "$W/.claude/worktrees/nc/src/main.py")" "$W")"
expect "a --no-checkout worktree: its scripts/ is its own tooling (exempt)" none "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$W/.claude/worktrees/nc/scripts/x.sh")" "$W")"
expect "a --no-checkout worktree: core-machinery denies its scripts/guarded.sh (judged by the project's sync)" deny "$(verdict "$SELF_DIR" core-machinery-guard-hook.sh "$(edit_payload "$W/.claude/worktrees/nc/scripts/guarded.sh")" "$W")"
mkdir -p "$W/.claude/worktrees/nc/specs"
printf '# Spec register\n\n## Specs\n\n- [/] 001 — x — full track — goal\n' > "$W/.claude/worktrees/nc/specs/INDEX.md"
expect "a --no-checkout worktree: core-owed-tick denies a tick of its register" deny "$(verdict "$SELF_DIR" core-owed-tick-guard-hook.sh "$(tick_payload "$W/.claude/worktrees/nc/specs/INDEX.md")" "$W")"
rm -rf "$W/.claude/worktrees/nc/specs"
O="$WORK/old"; mkdir -p "$O/src"; $GIT init -q "$O"; echo '{}' > "$O/package.json"; echo x > "$O/src/a.py"
( cd "$O" && $GIT add -A && $GIT commit -qm pre-register ) >/dev/null 2>&1
mkdir -p "$O/specs/001-x" "$O/.claude"; printf '# Spec register\n\n## Specs\n\n- [/] 001 — x — full track — goal\n' > "$O/specs/INDEX.md"; echo x > "$O/specs/001-x/spec.md"
( cd "$O" && $GIT add -A && $GIT commit -qm register && $GIT worktree add -q .claude/worktrees/old HEAD~1 ) >/dev/null 2>&1
[ -f "$O/.claude/worktrees/old/.git" ] && ok "F122 fixture: the pre-register worktree exists" || bad "F122 fixture: git worktree add failed"
expect "F122: a worktree at a commit before the register: denied on the project's register" deny "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$O/.claude/worktrees/old/src/a.py")" "$O")"
( cd "$W" && $GIT worktree add -q .claude/worktrees/full ) >/dev/null 2>&1
printf '# Spec register\n\n## Specs\n\n- [x] 001 — x — full track — goal\n' > "$W/.claude/worktrees/full/specs/INDEX.md"
expect "a worktree with its own register (every row ticked) still uses its own, as in 088" none "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$W/.claude/worktrees/full/src/main.py")" "$W")"
expect "a session started inside the --no-checkout worktree: still denied" deny "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$W/.claude/worktrees/nc/src/main.py")" "$W/.claude/worktrees/nc")"
( cd "$W" && $GIT worktree add -q --no-checkout .claude/worktrees/w -b w && $GIT worktree add -q --no-checkout .claude/worktrees/w/inner -b w2 ) >/dev/null 2>&1
expect "review #1: a --no-checkout worktree inside one: spec-interview denies" deny "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$W/.claude/worktrees/w/inner/src/x.cs")" "$W")"
expect "review #1: the nested worktree's CORE script: core-machinery denies" deny "$(verdict "$SELF_DIR" core-machinery-guard-hook.sh "$(edit_payload "$W/.claude/worktrees/w/inner/scripts/guarded.sh")" "$W")"

printf '\n[R6] review #7 and #9: a submodule session is its own root, a symlinked .git is not\n'
SP="$WORK/super"; make_project "$SP"
MODSRC="$WORK/modsrc"; mkdir -p "$MODSRC"; ( cd "$MODSRC" && $GIT init -q . && echo x > f && $GIT add f && $GIT commit -qm m ) >/dev/null 2>&1
( cd "$SP" && $GIT -c protocol.file.allow=always submodule add -q "$MODSRC" mod && $GIT commit -qm sub ) >/dev/null 2>&1
if [ -f "$SP/mod/.git" ]; then
  expect "review #7: a session in a submodule (its .git is a file) is its own root" none "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$SP/mod/src/m.cs")" "$SP/mod")"
else
  skip "review #7: git did not make a submodule here"
fi
$GIT init -q --separate-git-dir="$WORK/sepgit" "$SP/sep" >/dev/null 2>&1
( cd "$SP/sep" && echo x > f && $GIT add f && $GIT commit -qm s ) >/dev/null 2>&1
expect "review #7: a --separate-git-dir repository with a commit at the anchor is its own root" none "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$SP/sep/src/m.cs")" "$SP/sep")"
mkdir -p "$SP/sl"; ln -s ../.git "$SP/sl/.git"
expect "review #9: a .git symlinked to the outer one at the anchor: denied" deny "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$SP/sl/src/y.cs")" "$SP/sl")"

M=$(sabotage inherit guard-lib.sh '        own_reg="$GUARD_REGISTER"; GUARD_INHERITED=1' '        break')
expect "sabotage: no inheritance — the --no-checkout worktree is let through" none "$(verdict "$M" spec-interview-guard-hook.sh "$(edit_payload "$W/.claude/worktrees/nc/src/main.py")" "$W")"
M=$(sabotage exempt guard-lib.sh '    "$GUARD_GIT_ROOT"/*) guard_root_exempt' '    *) guard_root_exempt')
expect "sabotage: exempt at the inherited root — the worktree's src/ reads as .claude/** and passes" none "$(verdict "$M" spec-interview-guard-hook.sh "$(edit_payload "$W/.claude/worktrees/nc/src/main.py")" "$W")"
M=$(sabotage coresync guard-lib.sh '        dir="${dir%/*}"; continue' '        :')
expect "sabotage: core root without the sync fallback — the worktree's CORE script passes" none "$(verdict "$M" core-machinery-guard-hook.sh "$(edit_payload "$W/.claude/worktrees/nc/scripts/guarded.sh")" "$W")"

printf '\n[exit] every allow path exits 0 (mutation gate: exit 1 lets the call through as an error)\n'
echo 'FROM x' > "$P/Dockerfile"; ln -s ../Dockerfile "$P/src/build.cs"
expect "a .cs link that lands on Dockerfile is name-exempt: allowed, exit 0" none "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$P/src/build.cs")" "$P")"
mkdir -p "$WORK/nogit/src"
expect "a source file in no git repository: allowed, exit 0" none "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$WORK/nogit/src/x.cs")")"
expect "pipeline-state, the same: allowed, exit 0" none "$(verdict "$SELF_DIR" pipeline-state-guard-hook.sh "$(edit_payload "$WORK/nogit/src/x.cs")")"
expect "spec-register, the same: allowed, exit 0" none "$(verdict "$SELF_DIR" spec-register-guard-hook.sh "$(edit_payload "$WORK/nogit/src/x.cs")")"

printf '\n[markers and fail-closed] a .csproj-only project; no library; an unreadable payload\n'
C="$WORK/dotnet"; make_project "$C"; rm -f "$C/package.json"; echo '<Project/>' > "$C/src/App.csproj"
expect "a project whose only marker is a .csproj: spec-interview denies" deny "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$C/src/App.cs")" "$C")"
rm -f "$C/src/App.csproj"; echo 'x' > "$C/App.sln"
expect "a project whose only marker is a .sln: spec-interview denies" deny "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$C/src/App.cs")" "$C")"
# 092-AC-1 (R1, F101): no marker at all is no project. Each '&&'->'||' on the .csproj/.sln lines, and a
# _guard_has_match that matches an unexpanded glob, made every directory a .NET project.
N="$WORK/nomarker"; make_project "$N"; rm -f "$N/package.json"; echo 'class Root {}' > "$N/Root.cs"
for g in spec-interview-guard-hook.sh pipeline-state-guard-hook.sh; do
  # Spec 095 R6 (095-AC-4) supersedes this half of 092-AC-1: with a register, no marker is still a project.
  expect "095-AC-4 no marker, but a register: $g denies" deny "$(verdict "$SELF_DIR" "$g" "$(edit_payload "$N/src/App.cs")" "$N")"
done
mv "$N/specs/INDEX.md" "$N/INDEX.md.away"
expect "092-AC-1 no marker, no register: spec-register-guard answers none, exit 0" none "$(verdict "$SELF_DIR" spec-register-guard-hook.sh "$(edit_payload "$N/src/App.cs")" "$N")"
mv "$N/INDEX.md.away" "$N/specs/INDEX.md"
echo '<Project/>' > "$N/src/App.csproj"
for g in spec-interview-guard-hook.sh pipeline-state-guard-hook.sh; do
  expect "095-AC-4 a marker only in src/, a register at the root, an edit of Root.cs: $g denies" deny "$(verdict "$SELF_DIR" "$g" "$(edit_payload "$N/Root.cs")" "$N")"
  expect "092-AC-1 control: App.csproj beside src/App.cs: $g denies" deny "$(verdict "$SELF_DIR" "$g" "$(edit_payload "$N/src/App.cs")" "$N")"
done
mv "$N/specs/INDEX.md" "$N/INDEX.md.away"
expect "092-AC-1 a marker only in src/, no register, an edit of Root.cs: spec-register-guard answers none" none "$(verdict "$SELF_DIR" spec-register-guard-hook.sh "$(edit_payload "$N/Root.cs")" "$N")"
expect "092-AC-1 control: App.csproj beside src/App.cs, no register: spec-register-guard denies" deny "$(verdict "$SELF_DIR" spec-register-guard-hook.sh "$(edit_payload "$N/src/App.cs")" "$N")"
mv "$N/INDEX.md.away" "$N/specs/INDEX.md"
LONE="$WORK/lone"; mkdir -p "$LONE"; cp "$SELF_DIR/spec-interview-guard-hook.sh" "$SELF_DIR/guard-precheck.sh" "$LONE/"
expect "spec-interview without guard-lib.sh: a source payload is denied" deny "$(verdict "$LONE" spec-interview-guard-hook.sh "$(edit_payload "$P/src/App.cs")" "$P")"
expect "spec-interview without guard-lib.sh: a text payload passes" none "$(verdict "$LONE" spec-interview-guard-hook.sh "$(edit_payload "$P/docs/plain.txt")" "$P")"
TRUNC='{"tool_name":"Edit","tool_input":{"file_path":"'"$P"'/src/App.cs"'
expect "an unreadable payload naming a source file: denied" deny "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$TRUNC" "$P")"
TRUNC='{"tool_name":"Edit","tool_input":{"file_path":"'"$P"'/docs/plain.txt"'
expect "an unreadable payload naming a text file: allowed" none "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$TRUNC" "$P")"
ln -s loopb "$P/docs/loopa.cs"; ln -s loopa.cs "$P/docs/loopb"
T0=$(date +%s)
v=$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$P/docs/loopa.cs")" "$P")
[ $(( $(date +%s) - T0 )) -le 10 ] && ok "a symlink loop is judged within 10 s (8 hops at most)" || bad "a symlink loop was not bounded"

W3="$WORK/wt3"; make_project "$W3"
( cd "$W3" && $GIT worktree add -q --no-checkout .claude/worktrees/r -b r ) >/dev/null 2>&1
mkdir -p "$W3/.claude/worktrees/r/specs/001-x"
printf '# Spec register\n\n## Specs\n\n- [/] 001 — x — full track — goal\n' > "$W3/.claude/worktrees/r/specs/INDEX.md"
echo x > "$W3/.claude/worktrees/r/specs/001-x/spec.md"
expect "a worktree with its own register but no marker takes the project's marker: denied" deny "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$W3/.claude/worktrees/r/src/x.cs")" "$W3")"
MONO="$WORK/mono"; mkdir -p "$MONO/pkg/specs/001-x" "$MONO/pkg/scripts" "$MONO/pkg/src"; $GIT init -q "$MONO"
echo '{}' > "$MONO/pkg/package.json"
printf '# Spec register\n\n## Specs\n\n- [/] 001 — x — full track — goal\n' > "$MONO/pkg/specs/INDEX.md"; echo x > "$MONO/pkg/specs/001-x/spec.md"
expect "a monorepo package's own scripts/ is exempt (the register's root)" none "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$MONO/pkg/scripts/x.sh")" "$MONO")"
expect "a monorepo package's src/ is gated" deny "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$(edit_payload "$MONO/pkg/src/x.sh")" "$MONO")"
BIG=$(python3 -c 'print("x" * 5000)')
TRUNC='{"tool_name":"Edit","tool_input":{"old_string":"'"$BIG"'","file_path":"'"$P"'/docs/plain.txt"'
expect "a large unreadable payload naming a text file: allowed, exit 0" none "$(verdict "$SELF_DIR" spec-interview-guard-hook.sh "$TRUNC" "$P")"

printf '\n[unit] the library pieces a fixture cannot reach on this platform\n'
# unit <label> <want> <bash snippet run after sourcing guard-lib.sh (and guard-precheck.sh)>
unit() {
  local got
  got=$(cd "$WORK" && "$BASH_BIN" -c '. "$1/guard-lib.sh"; . "$1/guard-precheck.sh"; shift; eval "$1"' _ "$SELF_DIR" "$3" 2>/dev/null)
  expect "$1" "$2" "$got"
}
L=$(printf '%s' "$P" | tr '[:lower:]' '[:upper:]')
if [ "$FOLDS" -eq 1 ]; then
  got=$(cd "$WORK" && OSTYPE=linux-gnu CLAUDE_PROJECT_DIR="$P" "$BASH_BIN" -c 'OSTYPE=linux-gnu; . "$1/guard-lib.sh"; echo "$GUARD_ANCHOR_FOLD"' _ "$SELF_DIR")
  expect "a linux OSTYPE on a folding mount: the .GIT probe turns folding on" 1 "$got"
fi
mkdir -p "$WORK/nogit"
got=$(cd "$WORK" && CLAUDE_PROJECT_DIR="$WORK/nogit" "$BASH_BIN" -c 'OSTYPE=linux-gnu; . "$1/guard-lib.sh"; echo "$GUARD_ANCHOR_FOLD"' _ "$SELF_DIR")
expect "a linux OSTYPE and a project with no .git: no folding" 0 "$got"
unit "_guard_under folds case when the system folds" 0 'GUARD_ANCHOR_FOLD=1; _guard_under /A/B/c /a/b; echo $?'
unit "_guard_under is exact when it does not" 1 'GUARD_ANCHOR_FOLD=0; _guard_under /A/B/c /a/b; echo $?'
unit "_guard_under restores nocasematch off" off 'GUARD_ANCHOR_FOLD=1; _guard_under /a/b /a; shopt -q nocasematch && echo on || echo off'
unit "_guard_under keeps a caller's nocasematch on" on 'shopt -s nocasematch; GUARD_ANCHOR_FOLD=1; _guard_under /a/b /a; shopt -q nocasematch && echo on || echo off'
unit "_guard_is folds case when the system folds" 0 'GUARD_ANCHOR_FOLD=1; _guard_is /A/B /a/b; echo $?'
unit "_guard_is is exact when it does not" 1 'GUARD_ANCHOR_FOLD=0; _guard_is /A/B /a/b; echo $?'
unit "_guard_is restores nocasematch off" off 'GUARD_ANCHOR_FOLD=1; _guard_is /a /a; shopt -q nocasematch && echo on || echo off'
unit "_guard_is keeps a caller's nocasematch on" on 'shopt -s nocasematch; GUARD_ANCHOR_FOLD=1; _guard_is /a /b; shopt -q nocasematch && echo on || echo off'
unit "guard_ext_of App.cs::\$DATA. is cs" cs 'guard_ext_of "/x/App.cs::\$DATA."; echo "$GUARD_EXT"'
unit "guard_ext_of a name with no dot is empty" "" 'guard_ext_of "/x/Makefile"; echo "$GUARD_EXT"'
unit "_guard_ntfs_trim keeps .. as .." ".." '_guard_ntfs_trim ".. "; echo "$GUARD_TRIMMED"'
unit "_guard_stored_name outside a folding system returns the name as given" APP.CS 'GUARD_ANCHOR_FOLD=0; cd "'"$P"'/src"; _guard_stored_name APP.CS; echo "$GUARD_STORED"'
unit "_guard_stored_name of a missing name returns it as given" Nope.cs 'GUARD_ANCHOR_FOLD=1; cd "'"$P"'/src"; _guard_stored_name Nope.cs; echo "$GUARD_STORED"'
if [ "$FOLDS" -eq 1 ]; then
  unit "_guard_stored_name finds the stored case" App.cs 'GUARD_ANCHOR_FOLD=1; cd "'"$P"'/src"; _guard_stored_name APP.CS; echo "$GUARD_STORED"'
fi
# Windows spellings, with a stand-in cygpath (the real one ships with Git Bash and Cygwin).
mkdir -p "$WORK/fakebin"
printf '#!/bin/sh\n[ "$1" = -u ] && [ "$2" = -- ] && printf "%%s" "$3" | sed "s|^Z:|%s|"\n' "$P" > "$WORK/fakebin/cygpath"; chmod +x "$WORK/fakebin/cygpath"
got=$(cd "$WORK" && PATH="$WORK/fakebin:$PATH" "$BASH_BIN" -c '. "$1/guard-lib.sh"; GUARD_NTFS=1; _guard_canon_walk "$2"' _ "$SELF_DIR" 'Z:\scripts\guarded.sh' 2>/dev/null)
expect "NTFS: a drive path with backslashes canonicalises through cygpath" "$P/scripts/guarded.sh" "$got"
unit "guard_precheck_src restores nocasematch off" off 'SOURCE_EXTS=cs; guard_precheck_src "{\"file_path\":\"/x/A.CS\"}"; shopt -q nocasematch && echo on || echo off'
unit "guard_precheck_src keeps a caller's nocasematch on" on 'shopt -s nocasematch; SOURCE_EXTS=cs; guard_precheck_src "{}"; shopt -q nocasematch && echo on || echo off'
unit "guard_precheck_src folds the extension's case" 0 'SOURCE_EXTS=cs; guard_precheck_src "{\"file_path\":\"/x/A.CS\"}"; echo $?'
unit "guard_is_source restores nocasematch off" off 'SOURCE_EXTS=cs; guard_is_source /x/A.CS; shopt -q nocasematch && echo on || echo off'
unit "guard_is_source keeps a caller's nocasematch on" on 'shopt -s nocasematch; SOURCE_EXTS=cs; guard_is_source /x/a.txt; shopt -q nocasematch && echo on || echo off'
unit "precheck: a payload with no path is no link" 1 'guard_precheck_link "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}"; echo $?'
unit "precheck: a relative path whose cwd holds a backslash goes to the parser" 0 'guard_precheck_link "{\"tool_input\":{\"file_path\":\"a.txt\"},\"cwd\":\"C:\\\\x\"}"; echo $?'
unit "precheck: the walk stops at CLAUDE_PROJECT_DIR" 1 'mkdir -p real lnk2; ln -s real up 2>/dev/null; CLAUDE_PROJECT_DIR="$PWD/up/p" guard_precheck_link "{\"tool_input\":{\"file_path\":\"$PWD/up/p/a.txt\"}}"; echo $?'
unit "precheck: without an anchor a linked ancestor is found" 0 'mkdir -p real; ln -s real up2 2>/dev/null; guard_precheck_link "{\"tool_input\":{\"file_path\":\"$PWD/up2/p/a.txt\"}}"; echo $?'

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

#!/usr/bin/env bash
. "$(dirname -- "$0")/self-test-env.sh" || exit 1
# test-guard-lib.sh — scripts/guard-lib.sh, the library every PreToolUse guard reads its payload,
# writes its verdict and canonicalises its path through (spec 083, R1).
#
# Three promises, each with a sabotage arm that must turn the suite red:
#
#   guard_field   reads a field with jq, with python3 alone, and reports "no parser" / "not JSON"
#                 as distinct exit codes instead of an empty string that reads as "nothing to judge".
#   guard_deny    prints valid PreToolUse JSON on every parser tier, whatever bytes the reason has.
#   guard_canon   lands where the kernel would land: `..`, `//`, `.`, relative, symlinked directory.
#
# Exit 0 = every assertion held. Exit 1 = a real failure.

set -u

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
LIB="$SELF_DIR/guard-lib.sh"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok    %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$*"; }
info() { printf '        %s\n' "$*"; }

[ -f "$LIB" ] || { echo "missing: $LIB"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required"; exit 1; }

WORK=$(mktemp -d 2>/dev/null || mktemp -d -t guardlib)
WORK=$(cd -P "$WORK" && pwd)
trap 'rm -rf "$WORK"' EXIT

# Run a snippet in a fresh bash with the library sourced and the parser tier forced.
lib() {               # $1 = tier (jq|python3|none), $2 = snippet
  GUARD_TIER="$1" bash -c '. "$0"; GUARD_PARSER=$GUARD_TIER; '"$2" "$LIB"
}

printf '\n[R1] guard_field — three tiers, three distinct answers\n'
for tier in jq python3; do
  command -v "$tier" >/dev/null 2>&1 || { info "$tier not installed — tier skipped"; continue; }
  V=$(lib "$tier" 'INPUT='"'"'{"tool_input":{"file_path":"/a b/\"q\".cs","n":3}}'"'"'; guard_field .tool_input.file_path')
  [ "$V" = '/a b/"q".cs' ] && ok "$tier: reads a nested string with a space and quotes" || bad "$tier: read [$V]"
  V=$(lib "$tier" 'INPUT='"'"'{"tool_input":{"n":3}}'"'"'; guard_field .tool_input.n')
  [ "$V" = "3" ] && ok "$tier: a number comes back as its JSON text" || bad "$tier: number read as [$V]"
  lib "$tier" 'INPUT='"'"'{"tool_input":{}}'"'"'; v=$(guard_field .tool_input.file_path); rc=$?; [ -z "$v" ] && exit $rc; exit 9'
  [ $? -eq 0 ] && ok "$tier: an absent field is empty with exit 0 (an answer, not a failure)" || bad "$tier: absent field"
  lib "$tier" 'INPUT="{\"tool_input\":"; guard_field .tool_input.file_path >/dev/null'
  RC=$?; [ "$RC" -eq 4 ] && ok "$tier: a truncated payload is exit 4" || bad "$tier: truncated payload rc=$RC"
  lib "$tier" 'INPUT="[1,2]"; guard_field .a >/dev/null'
  RC=$?; [ "$RC" -eq 4 ] && ok "$tier: a payload that is not an object is exit 4" || bad "$tier: array rc=$RC"
done
lib none 'INPUT="{\"a\":\"b\"}"; guard_field .a >/dev/null'
RC=$?; [ "$RC" -eq 3 ] && ok "none: no parser is exit 3, never an empty success" || bad "none: rc=$RC"

printf '\n[R1] guard_deny / guard_context — valid JSON on every tier\n'
NASTY=$(printf 'q"\\ \n\t\r\001\037 é ✓ end')
for tier in jq python3 none; do
  OUT=$(NASTY="$NASTY" lib "$tier" 'guard_deny "$NASTY"')
  if printf '%s' "$OUT" | NASTY="$NASTY" python3 -c '
import json, os, sys
d = json.load(sys.stdin)["hookSpecificOutput"]
assert d["hookEventName"] == "PreToolUse"
assert d["permissionDecision"] == "deny"
assert d["permissionDecisionReason"] == os.environ["NASTY"], repr(d["permissionDecisionReason"])
' 2>/dev/null; then ok "$tier: the deny round-trips quotes, backslash, controls and UTF-8"
  else bad "$tier: the deny did not round-trip"; info "$OUT"; fi
  OUT=$(lib "$tier" 'guard_context "note"')
  printf '%s' "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin)["hookSpecificOutput"]; assert d["hookEventName"]=="PreToolUse" and d["additionalContext"]=="note"' 2>/dev/null \
    && ok "$tier: additionalContext carries hookEventName" || { bad "$tier: guard_context"; info "$OUT"; }
done

printf '\n[R1] guard_announce — once per session, every time without one\n'
# Spec 098 R6: the stamp needs a project git dir; without one the notice is said every time.
mkdir -p "$WORK/annp" && git init -q "$WORK/annp"
OUT1=$(CLAUDE_PROJECT_DIR="$WORK/annp" TMPDIR="$WORK/tmp" lib jq 'mkdir -p "$TMPDIR"; INPUT="{\"session_id\":\"s1\"}"; guard_announce g cause')
OUT2=$(CLAUDE_PROJECT_DIR="$WORK/annp" TMPDIR="$WORK/tmp" lib jq 'INPUT="{\"session_id\":\"s1\"}"; guard_announce g cause')
OUT3=$(CLAUDE_PROJECT_DIR="$WORK/annp" TMPDIR="$WORK/tmp" lib jq 'INPUT="{}"; guard_announce g cause')
case "$OUT1" in *additionalContext*"ALLOWED"*) ok "the first announcement in a session is printed" ;; *) bad "first announcement: [$OUT1]" ;; esac
[ -z "$OUT2" ] && ok "the second, same session and cause, is not" || bad "repeated announcement: [$OUT2]"
[ -n "$OUT3" ] && ok "without a session id it is always printed" || bad "no-session announcement missing"

printf '\n[R1, R4] guard_canon — where the kernel would land\n'
mkdir -p "$WORK/p/scripts" "$WORK/p/x" "$WORK/p/src"
ln -s "$WORK/p/scripts" "$WORK/s"
ln -s "$WORK/p" "$WORK/plink"
WANT="$WORK/p/scripts/a.sh"
canon() { bash -c '. "$0"; guard_canon "$1" "$2"' "$LIB" "$1" "${2:-}"; }
for c in "$WORK/p/x/../scripts/a.sh" "$WORK/p//scripts/a.sh" "$WORK/p/./scripts/a.sh" \
         "$WORK/s/a.sh" "$WORK/plink/scripts/a.sh" "$WORK/p/scripts/a.sh"; do
  V=$(canon "$c"); [ "$V" = "$WANT" ] && ok "${c#$WORK} -> /p/scripts/a.sh" || bad "${c#$WORK} -> ${V#$WORK}"
done
V=$(canon "scripts/a.sh" "$WORK/p");   [ "$V" = "$WANT" ] && ok "relative + base" || bad "relative + base -> $V"
V=$(cd "$WORK/p" && canon "./scripts/a.sh"); [ "$V" = "$WANT" ] && ok "relative + \$PWD" || bad "relative + PWD -> $V"
V=$(INPUT="{\"cwd\":\"$WORK/p\"}" bash -c '. "$0"; guard_canon "scripts/a.sh"' "$LIB")
[ "$V" = "$WANT" ] && ok "relative + payload .cwd" || bad "relative + cwd -> $V"
V=$(canon "$WORK/p/new/dir/../f.cs"); [ "$V" = "$WORK/p/new/f.cs" ] && ok "a non-existent tail is normalised lexically" || bad "tail -> $V"
V=$(canon "$WORK/s/../src/f.cs");    [ "$V" = "$WORK/src/f.cs" ] && ok "'..' is textual, as the CLI's Write applies it (not through the link)" || bad "symlink .. -> $V"
V=$(canon "$WORK/p/scripts/");      [ "$V" = "$WORK/p/scripts" ] && ok "a trailing slash names the directory" || bad "trailing slash -> $V"
V=$(canon "/");                     [ "$V" = "/" ] && ok "/ stays /" || bad "/ -> $V"
V=$(canon "$WORK/p/a b/../c d.cs"); [ "$V" = "$WORK/p/c d.cs" ] && ok "spaces survive" || bad "spaces -> $V"

printf '\n[R5] root-anchored exemptions\n'
ex() { bash -c '. "$0"; guard_root_exempt "$1"' "$LIB" "$1"; }
for r in scripts/x.sh specs/001/spec.md .specify/f .claude/x/y; do
  ex "$r" && ok "exempt: $r" || bad "not exempt: $r"
done
for r in src/scripts/app.js app/specs/x.ts lib/.claude/x.js scriptsx/a.js; do
  ex "$r" && bad "exempt but nested: $r" || ok "not exempt: $r"
done

printf '\n[sabotage] each promise, broken, turns the suite red\n'
SAB="$WORK/sab-lib.sh"
sed 's/|| return 4/|| return 0/' "$LIB" > "$SAB"
bash -c '. "$0"; GUARD_PARSER=jq; INPUT="{"; guard_field .a >/dev/null' "$SAB"
[ $? -eq 0 ] && ok "a guard_field that hides a parse error is detectable (rc 0 where 4 is required)" || bad "sabotage 1 not observable"
sed 's/^  s=\${s\/\/\\"\/\\\\\\"}$/  :/' "$LIB" > "$SAB"
OUT=$(bash -c '. "$0"; GUARD_PARSER=none; guard_deny "a\"b"' "$SAB")
printf '%s' "$OUT" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null \
  && bad "an escaper that skips quotes still produced valid JSON — the round-trip arm would not see it" \
  || ok "an escaper that skips quotes produces invalid JSON, which the round-trip arm rejects"
sed -e 's/cd -P -- "\$seg"/cd -L -- "$seg"/' -e 's/out=\$(_guard_pwd)/out=$(pwd -L)/' "$LIB" > "$SAB"
V=$(bash -c '. "$0"; guard_canon "$1"' "$SAB" "$WORK/s/a.sh")
[ "$V" != "$WANT" ] && ok "a canon that does not resolve symlinks lands elsewhere (${V#$WORK})" || bad "sabotage 3 not observable"

printf '\n[095-R6] a register stands in for a missing language marker  (095-AC-4)\n'
IG="$(cd "$(dirname "$0")" && pwd)/spec-interview-guard-hook.sh"
mkproj() { # mkproj <dir> [origin-url]: a git repo with a register naming an active full spec, no interview
  mkdir -p "$1/specs/001-demo" "$1/src"; git init -q "$1"
  printf '# Spec register\n\n## Specs\n\n- [/] 001 — demo — full track — demo\n' > "$1/specs/INDEX.md"
  printf '# 001\n' > "$1/specs/001-demo/spec.md"
  [ -n "${2:-}" ] && git -C "$1" remote add origin "$2"
  git -C "$1" add -A && git -C "$1" -c user.email=t@example.invalid -c user.name=t -c commit.gpgsign=false commit -qm init
}
ask_ig() { # ask_ig <project> <file> -> deny|allow
  local out
  out=$(jq -cn --arg p "$2" '{tool_name:"Edit",tool_input:{file_path:$p,old_string:"a",new_string:"b"}}' \
        | (cd "$1" && CLAUDE_PROJECT_DIR="$1" bash "$IG") 2>/dev/null)
  case "$out" in *'"deny"'*) echo deny ;; *) echo allow ;; esac
}
R6="$WORK/r6"; mkproj "$R6"
[ "$(ask_ig "$R6" "$R6/src/app.ts")" = deny ] && ok "095-AC-4 no marker, a register: the spec-interview guard denies" || bad "095-AC-4 no marker turned the guard off"
: > "$R6/package.json"
[ "$(ask_ig "$R6" "$R6/src/app.ts")" = deny ] && ok "control: with package.json it denies too" || bad "control with package.json"
R6I="$WORK/r6i"; mkproj "$R6I" "https://github.com/johanolofsson72/Claude.git"
[ "$(ask_ig "$R6I" "$R6I/src/app.ts")" = deny ] && ok "an impostor (the template's URL, another history) is guarded" || bad "an impostor turned the guard off"
R6S="$WORK/r6s"; mkdir -p "$R6S/src" "$R6S/.claude"; git init -q "$R6S"; : > "$R6S/.claude/.template-sync"
OUT6=$(jq -cn --arg p "$R6S/src/app.ts" '{tool_name:"Edit",tool_input:{file_path:$p,old_string:"a",new_string:"b"}}' \
       | (cd "$R6S" && CLAUDE_PROJECT_DIR="$R6S" bash "$(dirname "$IG")/spec-register-guard-hook.sh") 2>/dev/null)
case "$OUT6" in *'"deny"'*) ok "threat model: a synced project with neither marker nor register owes a register" ;; *) bad "the sync stamp did not stand in" ;; esac
case "$OUT6" in *".claude/.template-sync"*) ok "  and the reason names the sync stamp as the marker" ;; *) bad "  the reason names the wrong stand-in" ;; esac
TROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$(dirname "$IG")/template-identity.sh"
if [ "$(template_identity "$TROOT")" = template ]; then
  [ "$(ask_ig "$TROOT" "$TROOT/src/app.ts")" = allow ] && ok "095-AC-4 the template repository itself stays unguarded" || bad "095-AC-4 the template is now guarded"
else
  ok "095-AC-4 (template half skipped: this checkout is not the template by history)"
fi
SAB6="$WORK/sab6"; mkdir -p "$SAB6"; cp "$(dirname "$IG")"/*.sh "$(dirname "$IG")"/*.py "$SAB6"/ 2>/dev/null
sed 's/^  if \[ -z "\$GUARD_LANG_MARKER" \] && \[ -n "\$GUARD_GIT_ROOT" \] \\$/  if false \\/' "$(dirname "$IG")/guard-lib.sh" > "$SAB6/guard-lib.sh"
if cmp -s "$(dirname "$IG")/guard-lib.sh" "$SAB6/guard-lib.sh"; then bad "095-R6 sabotage target not found"; else
  OUTS=$(jq -cn --arg p "$R6/src/app.ts" '{tool_name:"Edit",tool_input:{file_path:$p,old_string:"a",new_string:"b"}}' \
         | (rm -f "$R6/package.json"; cd "$R6" && CLAUDE_PROJECT_DIR="$R6" bash "$SAB6/spec-interview-guard-hook.sh") 2>/dev/null)
  case "$OUTS" in *'"deny"'*) bad "095-R6 sabotage: the mutant still denies" ;; *) ok "095-R6 sabotage: without the stand-in, no marker turns the guard off again" ;; esac
fi

printf '\n[098-R4] _guard_git: an answer, no git, a git that does not answer\n'
NOGIT="$WORK/nogit"; mkdir -p "$NOGIT"
for d in /usr/bin /bin /usr/local/bin /opt/homebrew/bin; do
  [ -d "$d" ] || continue
  for x in "$d"/*; do b=${x##*/}; [ "$b" = git ] || [ -e "$NOGIT/$b" ] || ln -s "$x" "$NOGIT/$b" 2>/dev/null; done
done
SLOW="$WORK/slowgit"; mkdir -p "$SLOW"; printf '#!/bin/sh\nsleep 20\n' > "$SLOW/git"; chmod +x "$SLOW/git"
V=$(bash -c '. "$0"; _guard_git -C "$1" rev-parse --git-dir; echo "rc=$? u=[$GUARD_GIT_UNSURE]"' "$LIB" "$WORK")
case "$V" in "rc=128 u=[]") ok "git saying 'not a repository' is an answer (rc 128, not unsure)" ;; *) bad "an answer read as [$V]" ;; esac
V=$(PATH="$NOGIT" bash -c '. "$0"; _guard_git rev-parse --git-dir; echo "rc=$? u=[$GUARD_GIT_UNSURE]"' "$LIB")
case "$V" in "rc=125 u=[git is not on PATH]") ok "no git on PATH is unsure, with the cause" ;; *) bad "missing git read as [$V]" ;; esac
T0=$SECONDS
V=$(PATH="$SLOW:$PATH" GUARD_GIT_TIMEOUT=1 bash -c '. "$0"; _guard_git rev-parse --git-dir; echo "rc=$? u=[$GUARD_GIT_UNSURE]"' "$LIB")
case "$V" in "rc=125 u=[git did not answer within 1s]") ok "a git that hangs is cut off and unsure" ;; *) bad "a hanging git read as [$V]" ;; esac
[ $((SECONDS - T0)) -lt 8 ] && ok "  within the bound ($((SECONDS - T0)) s)" || bad "  took $((SECONDS - T0)) s"
V=$(GIT_DIR=/nonexistent bash -c '. "$0"; _guard_git -C "$1" rev-parse --is-inside-work-tree; echo "rc=$?"' "$LIB" "$(cd "$(dirname "$0")/.." && pwd)")
case "$V" in *"rc=0"*) ok "GIT_DIR in the environment does not reach git" ;; *) bad "GIT_DIR leaked: [$V]" ;; esac
P4="$WORK/p4"; mkdir -p "$P4/src"; git init -q "$P4"
V=$(PATH="$NOGIT" CLAUDE_PROJECT_DIR="$P4" bash -c '. "$0"; guard_walk "$1"; echo "u=[$GUARD_GIT_UNSURE] root=[${GUARD_GIT_ROOT##*/}]"' "$LIB" "$P4/src/a.ts")
[ "$V" = "u=[] root=[p4]" ] && ok "SC-2 an ordinary checkout never asks git: no git on PATH, still sure" || bad "an ordinary walk needed git: [$V]"

printf '\n[098-R4] the pipeline guards deny when the walk is unsure  (098-AC-4)\n'
W4="$WORK/w4"; mkdir -p "$W4/src"; git init -q "$W4"
git -C "$W4" -c user.email=t@example.invalid -c user.name=t -c commit.gpgsign=false commit -qm init --allow-empty
git -C "$W4" worktree add -q "$W4/.claude/worktrees/wt" 2>/dev/null; mkdir -p "$W4/.claude/worktrees/wt/src"
PS="$(dirname "$IG")/pipeline-state-guard-hook.sh"
ask_ps() { # ask_ps <hook> -> the hook's stdout for an Edit to the worktree's src/app.ts, git off PATH
  jq -cn --arg p "$W4/.claude/worktrees/wt/src/app.ts" '{tool_name:"Edit",tool_input:{file_path:$p,old_string:"a",new_string:"b"}}' \
    | (cd "$W4/.claude/worktrees/wt" && env PATH="$NOGIT" CLAUDE_PROJECT_DIR="$W4/.claude/worktrees/wt" bash "$1") 2>/dev/null
}
OUT=$(ask_ps "$PS")
case "$OUT" in *'"deny"'*"git is not on PATH"*) ok "098-AC-4 pipeline-state denies, naming git" ;; *) bad "098-AC-4 pipeline-state did not deny: $OUT" ;; esac
for g in spec-interview spec-register; do
  case "$(ask_ps "$(dirname "$IG")/$g-guard-hook.sh")" in *'"deny"'*"could not find this project's root"*) ok "$g denies too" ;; *) bad "$g did not deny" ;; esac
done
SAB4="$WORK/sab4"; mkdir -p "$SAB4"; cp "$(dirname "$IG")"/*.sh "$(dirname "$IG")"/*.py "$SAB4"/ 2>/dev/null
sed 's/^guard_unsure_deny pipeline-state-guard && exit 0.*/:/' "$PS" > "$SAB4/pipeline-state-guard-hook.sh"
if cmp -s "$PS" "$SAB4/pipeline-state-guard-hook.sh"; then bad "098-R4 sabotage target not found"; else
  case "$(ask_ps "$SAB4/pipeline-state-guard-hook.sh")" in *'"deny"'*) bad "098-R4 sabotage: the mutant still denies" ;; *) ok "098-R4 sabotage: without the check an unsure walk allows silently" ;; esac
fi

printf '\n[098-R6] the announce stamp lives in the git dir  (098-AC-4)\n'
P6="$WORK/p6"; mkdir -p "$P6/pkg/a"; git init -q "$P6"
ann() { # ann <project-dir> <sid> <cause> [lib] -> 1 when the notice was said, 0 when deduplicated
  local out
  out=$(CLAUDE_PROJECT_DIR="$1" INPUT="{\"session_id\":\"$2\"}" bash -c '. "$0"; guard_announce g "$1"' "${4:-$LIB}" "$3")
  [ -n "$out" ] && echo 1 || echo 0
}
SID6="t098-$$"
[ "$(ann "$P6" "$SID6" c1)$(ann "$P6" "$SID6" c1)" = 10 ] && ok "said once, then deduplicated" || bad "dedupe broken"
[ -n "$(ls -A "$P6/.git/claude-hook-notices/$SID6" 2>/dev/null)" ] && ok "  the stamp is under .git/claude-hook-notices" || bad "  no stamp in the git dir"
K=$(printf '%s' "guard-announce:g:c2" | cksum | tr -d ' ' | cut -c1-24)
mkdir -p "${TMPDIR:-/tmp}/claude-hook-notices/$SID6" && : > "${TMPDIR:-/tmp}/claude-hook-notices/$SID6/$K"
[ "$(ann "$P6" "$SID6" c2)" = 1 ] && ok "098-AC-4 a stamp planted under TMPDIR silences nothing" || bad "098-AC-4 a TMPDIR stamp silenced the notice"
[ "$(ann "$P6/pkg/a" "$SID6" c3)$(ann "$P6/pkg/a" "$SID6" c3)" = 10 ] && ok "threat #8: a package directory finds the git dir above it" || bad "a monorepo package directory repeats the notice"
NG="$WORK/nogitdir"; mkdir -p "$NG"
[ "$(ann "$NG" "$SID6" c4)$(ann "$NG" "$SID6" c4)" = 11 ] && ok "no git dir: said every time" || bad "no git dir was deduplicated"
[ -e "${TMPDIR:-/tmp}/claude-hook-notices/$SID6/$(printf '%s' "guard-announce:g:c4" | cksum | tr -d ' ' | cut -c1-24)" ] \
  && bad "  …and it fell back to a TMPDIR stamp" || ok "  and never through a TMPDIR stamp"
SAB6B="$WORK/sab6b"; mkdir -p "$SAB6B"; cp "$(dirname "$IG")"/*.sh "$SAB6B"/
sed 's/hn_first_time "\$sid" "guard-announce:\$guard:\$cause" "\$base"/hn_first_time "$sid" "guard-announce:$guard:$cause"/' "$LIB" > "$SAB6B/guard-lib.sh"
if cmp -s "$LIB" "$SAB6B/guard-lib.sh"; then bad "098-R6 sabotage target not found"; else
  K5=$(printf '%s' "guard-announce:g:c5" | cksum | tr -d ' ' | cut -c1-24); : > "${TMPDIR:-/tmp}/claude-hook-notices/$SID6/$K5"
  [ "$(ann "$P6" "$SID6" c5 "$SAB6B/guard-lib.sh")" = 0 ] && ok "098-R6 sabotage: a TMPDIR stamp silences the old code" || bad "098-R6 sabotage: the mutant still speaks"
fi
rm -rf "${TMPDIR:-/tmp}/claude-hook-notices/$SID6"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

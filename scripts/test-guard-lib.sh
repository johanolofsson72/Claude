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
KILLED="$WORK/killedgit"; mkdir -p "$KILLED"; printf '#!/bin/sh\nkill -TERM $$\n' > "$KILLED/git"; chmod +x "$KILLED/git"
V=$(PATH="$KILLED:$PATH" bash -c '. "$0"; _guard_git rev-parse --git-dir; echo "rc=$? u=[$GUARD_GIT_UNSURE]"' "$LIB")
case "$V" in "rc=125 u=[git exited 143, which is no answer]") ok "098 review R4-1: a git killed by SIGTERM is unsure, not an answer" ;; *) bad "a killed git read as [$V]" ;; esac
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
sk() { printf '%s' "$1" | { sha256sum 2>/dev/null || shasum -a 256; } | cut -c1-40; }   # hn_first_time's stamp name
[ "$(ann "$P6" "$SID6" c1)$(ann "$P6" "$SID6" c1)" = 10 ] && ok "said once, then deduplicated" || bad "dedupe broken"
[ -n "$(ls -A "$P6/.git/claude-hook-notices/$SID6" 2>/dev/null)" ] && ok "  the stamp is under .git/claude-hook-notices" || bad "  no stamp in the git dir"
K=$(sk "guard-announce:g:c2")
mkdir -p "${TMPDIR:-/tmp}/claude-hook-notices/$SID6" && : > "${TMPDIR:-/tmp}/claude-hook-notices/$SID6/$K"
[ "$(ann "$P6" "$SID6" c2)" = 1 ] && ok "098-AC-4 a stamp planted under TMPDIR silences nothing" || bad "098-AC-4 a TMPDIR stamp silenced the notice"
[ "$(ann "$P6/pkg/a" "$SID6" c3)$(ann "$P6/pkg/a" "$SID6" c3)" = 10 ] && ok "threat #8: a package directory finds the git dir above it" || bad "a monorepo package directory repeats the notice"
NG="$WORK/nogitdir"; mkdir -p "$NG"
[ "$(ann "$NG" "$SID6" c4)$(ann "$NG" "$SID6" c4)" = 11 ] && ok "no git dir: said every time" || bad "no git dir was deduplicated"
[ -e "${TMPDIR:-/tmp}/claude-hook-notices/$SID6/$(sk "guard-announce:g:c4")" ] \
  && bad "  …and it fell back to a TMPDIR stamp" || ok "  and never through a TMPDIR stamp"
# 098 review R6-1/R6-2: the leftmost session_id is the session; a nested one (MCP input) is not.
V=$(bash -c '. "$0"; hn_session_id "$1"' "$(dirname "$IG")/hook-notice.sh" '{"session_id":"real","tool_input":{"session_id":"old"}}')
[ "$V" = real ] && ok "098 review R6-2: the top-level session_id wins over a nested one" || bad "session id read as [$V]"
[ "${#K}" -eq 40 ] && [ "$(sk "guard-announce:g:c2")" = "$K" ] && ok "098 review R6-1: the stamp name is a SHA-256 prefix, not a CRC" || bad "stamp name [$K]"
V=$(bash -c 'set -e; . "$0"; hn_session_id "{}"; echo "rc=$?"' "$(dirname "$IG")/hook-notice.sh")
[ "$V" = "rc=0" ] && ok "a payload with no session_id returns 0 (a hook under set -e lives)" || bad "no session id read as [$V]"
NOHASH="$WORK/nohash"; mkdir -p "$NOHASH"
for d in /usr/bin /bin /usr/local/bin /opt/homebrew/bin; do
  [ -d "$d" ] || continue
  for x in "$d"/*; do b=${x##*/}; case "$b" in sha256sum|shasum) continue ;; esac; [ -e "$NOHASH/$b" ] || ln -s "$x" "$NOHASH/$b" 2>/dev/null; done
done
annp() { local out; out=$(PATH="$NOHASH" CLAUDE_PROJECT_DIR="$1" INPUT="{\"session_id\":\"$2\"}" bash -c '. "$0"; guard_announce g "$1"' "$LIB" "$3"); [ -n "$out" ] && echo 1 || echo 0; }
[ "$(annp "$P6" "$SID6" c6)$(annp "$P6" "$SID6" c6)" = 11 ] && ok "nothing to hash with: said every time, never silenced" || bad "no hasher silenced the notice"
# The base must be a git dir, or nothing: never an empty base that falls back to TMPDIR.
[ "$(ann "" "$SID6" c7)$(ann "" "$SID6" c7)" = 11 ] && ok "no project dir: said every time (clarification R6)" || bad "no project dir was deduplicated"
J1="$WORK/junkgit"; mkdir -p "$J1"; echo "not a gitdir line" > "$J1/.git"
[ "$(ann "$J1" "$SID6" c8)$(ann "$J1" "$SID6" c8)" = 11 ] && ok "a .git file without gitdir: is no git dir: said every time" || bad "a junk .git file was deduplicated"
J2="$WORK/danglegit"; mkdir -p "$J2"; echo "gitdir: $WORK/nowhere" > "$J2/.git"
[ "$(ann "$J2" "$SID6" c9)$(ann "$J2" "$SID6" c9)" = 11 ] && ok "a gitdir: naming no directory: said every time" || bad "a dangling gitdir was deduplicated"
J3="$WORK/linkedgit"; mkdir -p "$J3" "$WORK/realgd"; echo "gitdir: $WORK/realgd" > "$J3/.git"
[ "$(ann "$J3" "$SID6" c10)$(ann "$J3" "$SID6" c10)" = 10 ] && ok "threat #8: a gitdir: naming a directory dedupes there" || bad "the gitdir: route did not dedupe"
[ -n "$(ls -A "$WORK/realgd/claude-hook-notices/$SID6" 2>/dev/null)" ] && ok "  its stamp is in that git dir" || bad "  no stamp in the named git dir"
V=$(CLAUDE_PROJECT_DIR="$P6" INPUT="{\"session_id\":\"$SID6\"}" bash -c 'set -e; . "$0"; guard_announce g c1 >/dev/null; echo "rc=$?"' "$LIB")
[ "$V" = "rc=0" ] && ok "a deduplicated announcement returns 0 (a caller under set -e lives)" || bad "deduplicated announce read as [$V]"
NOTO="$WORK/noto"; mkdir -p "$NOTO"
for d in /usr/bin /bin /usr/local/bin /opt/homebrew/bin; do
  [ -d "$d" ] || continue
  for x in "$d"/*; do b=${x##*/}; case "$b" in timeout|gtimeout|perl|perl5*) continue ;; esac; [ -e "$NOTO/$b" ] || ln -s "$x" "$NOTO/$b" 2>/dev/null; done
done
V=$(PATH="$NOTO" bash -c '. "$0"; _guard_git rev-parse --git-dir; echo "rc=$? u=[$GUARD_GIT_UNSURE]"' "$LIB")
case "$V" in *"rc=125 u=[neither timeout, gtimeout nor perl"*) ok "nothing to bound git with: unsure, rc 125" ;; *) bad "an unbounded git read as [$V]" ;; esac
V=$(GUARD_GIT_UNSURE="git is not on PATH" bash -c '. "$0"; guard_unsure_deny g >/dev/null; echo "rc=$?"' "$LIB")
[ "$V" = "rc=0" ] && ok "guard_unsure_deny returns 0 once it has denied" || bad "guard_unsure_deny read as [$V]"
V=$(bash -c '. "$0"; unset GUARD_GIT_UNSURE; out=$(guard_unsure_deny g); echo "rc=$? out=[$out]"' "$LIB")
[ "$V" = "rc=1 out=[]" ] && ok "  and 1, silently, when the walk was sure" || bad "  a sure walk read as [$V]"
# 091 R6 through _guard_git (098 mutation survivors): a project inside an outer repository whose own
# .git is a FILE counts as the root only when git accepts it as a repository of its own.
O="$WORK/outer"; mkdir -p "$O"; git init -q "$O"
anchor_root() { # anchor_root <project> -> the root guard_walk settles on for <project>/src/a.ts
  mkdir -p "$1/src"
  CLAUDE_PROJECT_DIR="$1" bash -c '. "$0"; guard_walk "$1/src/a.ts"; printf "%s" "$GUARD_GIT_ROOT"' "$LIB" "$1"
}
OR=$(cd -P "$O" && pwd)
mkdir -p "$O/p1"; echo "junk" > "$O/p1/.git"
[ "$(anchor_root "$O/p1")" = "$OR" ] && ok "a junk .git file does not make the project a root" || bad "a junk .git file counted"
mkdir -p "$O/p2"; echo "gitdir: $WORK/nowhere2" > "$O/p2/.git"
[ "$(anchor_root "$O/p2")" = "$OR" ] && ok "a dangling gitdir: does not make the project a root" || bad "a dangling gitdir counted"
mkdir -p "$O/p3" "$WORK/emptygd"; echo "gitdir: $WORK/emptygd" > "$O/p3/.git"
[ "$(anchor_root "$O/p3")" = "$OR" ] && ok "a gitdir: git rejects does not make the project a root" || bad "a git-rejected gitdir counted"
git init -q --separate-git-dir="$WORK/p4gd" "$O/p4"
git -C "$O/p4" -c user.email=t@example.invalid -c user.name=t -c commit.gpgsign=false commit -qm i --allow-empty
P4R=$(cd -P "$O/p4" && pwd)
[ "$(anchor_root "$O/p4")" = "$P4R" ] && ok "a --separate-git-dir repository of its own is the root (review #7)" || bad "a real separate-git-dir repository did not count"
SAB6B="$WORK/sab6b"; mkdir -p "$SAB6B"; cp "$(dirname "$IG")"/*.sh "$SAB6B"/
sed 's/hn_first_time "\$sid" "guard-announce:\$guard:\$cause" "\$base"/hn_first_time "$sid" "guard-announce:$guard:$cause"/' "$LIB" > "$SAB6B/guard-lib.sh"
if cmp -s "$LIB" "$SAB6B/guard-lib.sh"; then bad "098-R6 sabotage target not found"; else
  K5=$(sk "guard-announce:g:c5"); : > "${TMPDIR:-/tmp}/claude-hook-notices/$SID6/$K5"
  [ "$(ann "$P6" "$SID6" c5 "$SAB6B/guard-lib.sh")" = 0 ] && ok "098-R6 sabotage: a TMPDIR stamp silences the old code" || bad "098-R6 sabotage: the mutant still speaks"
fi
rm -rf "${TMPDIR:-/tmp}/claude-hook-notices/$SID6"

printf '\n[105-R3] a stamp only in a git dir trust-anchor guards\n'
SID5="t105-$$"
A1="$WORK/anc1"; mkdir -p "$A1/pkg" "$WORK/sepgd1"; echo "gitdir: $WORK/sepgd1" > "$A1/.git"
[ "$(ann "$A1/pkg" "$SID5" r1)$(ann "$A1/pkg" "$SID5" r1)" = 11 ] && ok "105-R3 an ancestor's gitdir with no .git component: said every time" || bad "105-R3 an unguarded ancestor git dir deduplicated"
[ -e "$WORK/sepgd1/claude-hook-notices" ] && bad "  …and left a stamp there" || ok "  and no stamp was left there"
A2="$WORK/anc2"; mkdir -p "$A2/pkg" "$WORK/main/.git/worktrees/w"; echo "gitdir: $WORK/main/.git/worktrees/w" > "$A2/.git"
[ "$(ann "$A2/pkg" "$SID5" r2)$(ann "$A2/pkg" "$SID5" r2)" = 10 ] && ok "105-R3 an ancestor worktree's gitdir under .git/ dedupes" || bad "105-R3 a guarded ancestor git dir did not dedupe"
mkdir -p "$WORK/tricky/.git" "$WORK/elsewhere"; A3="$WORK/anc3"; mkdir -p "$A3/pkg"; echo "gitdir: $WORK/tricky/.git/../../elsewhere" > "$A3/.git"
[ "$(ann "$A3/pkg" "$SID5" r3)$(ann "$A3/pkg" "$SID5" r3)" = 11 ] && ok "105-R3 a .git component only as spelled (threat #9) is judged resolved" || bad "105-R3 a spelled-only .git component deduplicated"
[ "$(ann "$J3" "$SID5" r4)$(ann "$J3" "$SID5" r4)" = 10 ] && ok "105-R3 control: the project dir's own .git file still dedupes (098 TB1)" || bad "105-R3 the project's own gitdir: stopped deduping"
A4="$WORK/anc4"; mkdir -p "$A4/pkg" "$WORK/locked/.git/worktrees/w"; echo "gitdir: $WORK/locked/.git/worktrees/w" > "$A4/.git"
chmod 000 "$WORK/locked/.git/worktrees/w"
[ "$(ann "$A4/pkg" "$SID5" r6)$(ann "$A4/pkg" "$SID5" r6)" = 11 ] && ok "105-R3 an ancestor gitdir that cannot be resolved: said every time" || bad "105-R3 an unresolvable gitdir deduplicated"
chmod 755 "$WORK/locked/.git/worktrees/w"
SAB5="$WORK/sab105r3"; mkdir -p "$SAB5"; cp "$(dirname "$IG")"/*.sh "$SAB5"/
sed 's|case "\$g/" in \*/.git/\*) ;; \*) return 1 ;; esac|:|' "$LIB" > "$SAB5/guard-lib.sh"
if cmp -s "$LIB" "$SAB5/guard-lib.sh"; then bad "105-R3 sabotage target not found"; else
  [ "$(ann "$A1/pkg" "$SID5" r5 "$SAB5/guard-lib.sh")$(ann "$A1/pkg" "$SID5" r5 "$SAB5/guard-lib.sh")" = 10 ] \
    && ok "105-R3 sabotage: without the check the unguarded git dir keeps a stamp" || bad "105-R3 sabotage: the mutant still says it every time"
fi

printf '\n[105-R1] no .git at a registered or synced root  (105-AC-2)\n'
NGP="$WORK/nogitproj"; mkdir -p "$NGP/src" "$NGP/specs" "$NGP/.claude"; : > "$NGP/specs/INDEX.md"; : > "$NGP/.claude/.template-sync"; : > "$NGP/package.json"
SRG="$(dirname "$IG")/spec-register-guard-hook.sh"
ask_ng() { jq -cn --arg p "$2/src/app.py" '{tool_name:"Edit",tool_input:{file_path:$p,old_string:"a",new_string:"b"}}' | CLAUDE_PROJECT_DIR="$2" bash "$1" 2>/dev/null; }
OUT=$(ask_ng "$SRG" "$NGP")
case "$OUT" in *'"deny"'*"has no .git"*) ok "105-AC-2 spec-register-guard denies naming the missing .git" ;; *) bad "105-AC-2 spec-register-guard: [$(printf '%s' "$OUT" | head -c 140)]" ;; esac
case "$OUT" in *'with the ! prefix'*) ok "  and names the developer's route" ;; *) bad "  no route in the reason" ;; esac
for g in pipeline-state spec-interview; do
  case "$(ask_ng "$(dirname "$IG")/$g-guard-hook.sh" "$NGP")" in *'"deny"'*"has no .git"*) ok "105-R1 $g denies too" ;; *) bad "105-R1 $g did not deny" ;; esac
done
for one in specs/INDEX.md .claude/.template-sync; do
  N1="$WORK/ngone-${one##*/}"; mkdir -p "$N1/src" "$N1/specs" "$N1/.claude"; : > "$N1/$one"; : > "$N1/package.json"
  case "$(ask_ng "$SRG" "$N1")" in *'"deny"'*"has no .git"*) ok "105-R1 $one alone makes it a project" ;; *) bad "105-R1 $one alone was not judged" ;; esac
done
ND="$WORK/ngdangle"; mkdir -p "$ND/src" "$ND/specs"; : > "$ND/specs/INDEX.md"; : > "$ND/package.json"; ln -s "$WORK/nowhere-git" "$ND/.git"
case "$(ask_ng "$SRG" "$ND")" in *'"deny"'*"has no .git"*) ok "105-R1 a dangling .git link is as gone as a removed .git" ;; *) bad "105-R1 a dangling .git link went silent" ;; esac
V=$(bash -c 'set -e; . "$0"; guard_walk "/nonexistent-105/a.py"; echo "rc=$?"' "$LIB")
[ "$V" = "rc=0" ] && ok "105-R1 guard_walk returns 0 when it found no root and no fallback (a caller under set -e lives)" || bad "guard_walk read as [$V]"
V=$(GUARD_NO_GIT="the project root /x has no .git" GUARD_GIT_UNSURE="the project root /x has no .git" bash -c '. "$0"; guard_unsure_deny g >/dev/null; echo "rc=$?"' "$LIB")
[ "$V" = "rc=0" ] && ok "105-R1 guard_unsure_deny returns 0 after the no-.git deny (the caller exits on it)" || bad "no-.git deny read as [$V]"
V=$(bash -c '. "$0"; unset GUARD_NO_GIT; guard_no_git_announce g; echo "rc=$?"' "$LIB")
[ "$V" = "rc=0" ] && ok "105-R1 guard_no_git_announce returns 0 when there is nothing to announce" || bad "guard_no_git_announce read as [$V]"
NGL="$WORK/nogitloose"; mkdir -p "$NGL/src"; : > "$NGL/package.json"
[ -z "$(ask_ng "$SRG" "$NGL")" ] && ok "105-R1 control: no register and no stamp stays silent" || bad "105-R1 a loose directory was denied"
SAB1="$WORK/sab105r1"; mkdir -p "$SAB1"; cp "$(dirname "$IG")"/*.sh "$(dirname "$IG")"/*.py "$SAB1"/ 2>/dev/null
sed 's/^  \[ -z "\$GUARD_GIT_ROOT" \] && _guard_no_git_root && GUARD_GIT_UNSURE="\$GUARD_NO_GIT"$/  :/' "$LIB" > "$SAB1/guard-lib.sh"
if cmp -s "$LIB" "$SAB1/guard-lib.sh"; then bad "105-R1 sabotage target not found"; else
  [ -z "$(ask_ng "$SAB1/spec-register-guard-hook.sh" "$NGP")" ] && ok "105-R1 sabotage: without the fallback the guard is silent with .git gone" || bad "105-R1 sabotage: the mutant still speaks"
fi

printf '\n[100] return codes the callers rely on\n'
# guard_json_str succeeds on every tier: one literal on stdout and exit 0, so a caller that checks the
# status (`s=$(guard_json_str "$x") || …`) never mistakes a written literal for a failure.
for tier in jq python3 none; do
  [ "$tier" = none ] || command -v "$tier" >/dev/null 2>&1 || { info "$tier not installed — tier skipped"; continue; }
  V=$(lib "$tier" 's=$(guard_json_str "a\"b"); echo "rc=$? s=$s"')
  [ "$V" = 'rc=0 s="a\"b"' ] && ok "[100] guard-lib.sh:89-90 guard_json_str on $tier: one literal, exit 0" || bad "[100] guard_json_str on $tier read as [$V]"
done
# _guard_gitdir_of: a .git FILE without a `gitdir:` line is no git dir (exit 1). Taking it as one with
# an empty target made the worktree check ask git about a junk file, and a git that does not answer
# then turned the walk unsure (098 R4) where it was sure: no git is needed to reject a junk .git.
JG="$WORK/junkgd"; mkdir -p "$JG/sub"; echo "not a gitdir line" > "$JG/sub/.git"
V=$(bash -c '. "$0"; _guard_gitdir_of "$1"; echo "rc=$? g=[$GUARD_GITDIR]"' "$LIB" "$JG/sub")
[ "$V" = "rc=1 g=[]" ] && ok "[100] guard-lib.sh:447 a .git file without gitdir: is exit 1" || bad "[100] _guard_gitdir_of on a junk .git read as [$V]"
FAKEGIT="$WORK/fakegit"; mkdir -p "$FAKEGIT"; printf '#!/bin/sh\nexit 3\n' > "$FAKEGIT/git"; chmod +x "$FAKEGIT/git"
V=$(PATH="$FAKEGIT:$PATH" bash -c '. "$0"; GUARD_ANCHOR=$1; GUARD_ANCHOR_FOLD=0; GUARD_GIT_UNSURE=""
  guard_git_boundary "$1/sub"; echo "rc=$? u=[$GUARD_GIT_UNSURE]"' "$LIB" "$JG")
[ "$V" = "rc=1 u=[]" ] && ok "[100] guard-lib.sh:447 a junk .git below the anchor is no boundary, and git is never asked" || bad "[100] junk .git boundary read as [$V]"

# Spec 109 (F195 class): guard_name_exempt is what lets the pipeline guards pass CLAUDE.md, README and
# friends. Every name group answers 0, and a source file answers 1.
V=""
for n in /p/CLAUDE.md /p/CLAUDE.local.md /p/README /p/LICENSE /p/CHANGELOG /p/.gitignore /p/.env /p/Dockerfile /p/src/App.cs /p/README.sh; do
  V="$V $(bash -c '. "$0"; guard_name_exempt "$1"; echo $?' "$LIB" "$n")"
done
[ "$V" = " 0 0 0 0 0 0 0 0 1 1" ] && ok "[109] guard_name_exempt: the named files are exempt, App.cs and README.sh are not" \
  || bad "[109] guard_name_exempt answered [$V]"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

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
OUT1=$(TMPDIR="$WORK/tmp" lib jq 'mkdir -p "$TMPDIR"; INPUT="{\"session_id\":\"s1\"}"; guard_announce g cause')
OUT2=$(TMPDIR="$WORK/tmp" lib jq 'INPUT="{\"session_id\":\"s1\"}"; guard_announce g cause')
OUT3=$(TMPDIR="$WORK/tmp" lib jq 'INPUT="{}"; guard_announce g cause')
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

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

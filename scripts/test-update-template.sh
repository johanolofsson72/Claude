#!/bin/bash
# Self-test for spec 082 R12 in scripts/update-template.sh: the template updater feeds web pages to a
# model, so the model it starts gets no shell, the log is not at a path another user can pre-plant,
# a dirty tree is refused, and the run ends on a diff for a human to read.
#
#   bash scripts/test-update-template.sh
#
# A fake `claude` on PATH records its argv, so nothing reaches a real model. The script runs from a
# throwaway copy inside a temp git repo, because REPO_ROOT is the copy's parent directory.
#
# bash 3.2-safe. Template-only, like the script it tests.

set -u

DIR=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/update-template-test.$$")
mkdir -p "$TMP"
PASS=0
FAIL=0
trap 'rm -rf "$TMP"' EXIT

ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"; }
expect_eq()       { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }
expect_contains() { if grep -Fq -e "$2" <<< "$3"; then ok "$1"; else bad "$1" "contains: $2" "$3"; fi; }
expect_absent()   { if grep -Fq -e "$2" <<< "$3"; then bad "$1" "absent: $2" "$3"; else ok "$1"; fi; }

BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/claude" <<'SH'
#!/bin/bash
for a in "$@"; do printf '%s\n' "$a"; done > "$CLAUDE_ARGV"
echo "fake claude ran"
SH
chmod +x "$BIN/claude"

mkrepo() {
  local r="$TMP/$1"; mkdir -p "$r/scripts"
  cp "$DIR/update-template.sh" "$r/scripts/"
  ( cd "$r" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm init )
  printf '%s' "$r"
}

# argv_after FILE FLAG -> the value following FLAG
argv_after() { awk -v f="$2" 'p{print; exit} $0==f{p=1}' "$1"; }

echo "update-template.sh (R12)"

R=$(mkrepo live)
A="$TMP/argv.live"
OUT=$(PATH="$BIN:$PATH" CLAUDE_ARGV="$A" TMPDIR="$TMP" bash "$R/scripts/update-template.sh" 2>&1); RC=$?
expect_eq       "U1 a clean live run exits 0" "0" "$RC"
DIS=$(argv_after "$A" --disallowedTools)
ALW=$(argv_after "$A" --allowedTools)
expect_contains "U2 Bash is disallowed (deny beats a bypassPermissions default)" "Bash" "$DIS"
expect_contains "U2 Agent is disallowed" "Agent" "$DIS"
expect_absent   "U3 Bash is not in the allow list" "Bash" "$ALW"
expect_absent   "U3 Agent is not in the allow list" "Agent" "$ALW"
expect_contains "U4 live mode keeps Edit" "Edit" "$ALW"
# Token-wise: the live list denies Edit(.git/**) and friends, but never bare Edit.
expect_eq       "U4 live mode does not disallow Edit as a whole" "" "$(printf '%s\n' $DIS | grep -x Edit)"
expect_absent   "U5 the log is not at the predictable /tmp path" "/tmp/claude-template-update-" "$OUT"
LOG=$(printf '%s\n' "$OUT" | sed -n 's/^Log: //p' | head -1)
expect_eq       "U5 the log path is printed and exists" "yes" "$([ -n "$LOG" ] && [ -f "$LOG" ] && echo yes || echo no)"
expect_contains "U5 the log holds the model's output" "fake claude ran" "$(cat "$LOG" 2>/dev/null)"
expect_contains "U6 the run ends on a diff summary for review" "git diff --stat" "$OUT"

# U9 (review finding 4): an injected model with Edit/Write must not reach what runs code later --
# .git/ (hooks, core.fsmonitor), settings.json (hook commands) or scripts/ (the hooks themselves) --
# nor read credentials to exfiltrate through WebFetch.
for r in "Edit(.git/**)" "Write(.git/**)" "Edit(.claude/settings*.json)" "Write(.claude/settings*.json)" \
         "Edit(scripts/**)" "Write(scripts/**)" "Read(~/.ssh/**)" "Read(~/.aws/**)" "Read(~/.gnupg/**)" \
         "Read(~/.config/gh/**)" "Read(~/.netrc)" "Read(~/.git-credentials)"; do
  expect_contains "U9 live run disallows $r" "$r" "$DIS"
done
expect_contains "U10 the prompt sends scripts/ changes to the report" "Do not edit scripts/" "$(cat "$A")"

# U11: the closing diff and the opening status run with repository config that cannot execute:
# a planted core.fsmonitor in the template's .git/config must never fire.
R=$(mkrepo fsmon)
git -C "$R" config core.fsmonitor "touch $TMP/fsmonitor-fired; false"
A="$TMP/argv.fsmon"
PATH="$BIN:$PATH" CLAUDE_ARGV="$A" TMPDIR="$TMP" bash "$R/scripts/update-template.sh" >/dev/null 2>&1
expect_eq       "U11 a planted core.fsmonitor never runs" "no" "$([ -e "$TMP/fsmonitor-fired" ] && echo yes || echo no)"

A="$TMP/argv.dry"
OUT=$(PATH="$BIN:$PATH" CLAUDE_ARGV="$A" TMPDIR="$TMP" bash "$R/scripts/update-template.sh" --dry-run 2>&1)
DIS=$(argv_after "$A" --disallowedTools)
for t in Bash Agent Edit Write; do
  expect_eq "U7 --dry-run disallows $t as a whole" "$t" "$(printf '%s\n' $DIS | grep -x "$t")"
done

R=$(mkrepo dirty)
echo "wip" > "$R/scratch.txt"
A="$TMP/argv.dirty"; rm -f "$A"
OUT=$(PATH="$BIN:$PATH" CLAUDE_ARGV="$A" TMPDIR="$TMP" bash "$R/scripts/update-template.sh" 2>&1); RC=$?
expect_eq       "U8 a dirty template tree is refused" "1" "$RC"
expect_contains "U8 the refusal says why" "uncommitted" "$OUT"
expect_eq       "U8 the model never started" "no" "$([ -f "$A" ] && echo yes || echo no)"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

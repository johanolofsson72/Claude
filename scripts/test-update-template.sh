#!/bin/bash
. "$(dirname -- "$0")/self-test-env.sh" || exit 1
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
# --help lists --restricted unless the test says this claude predates it (spec 091 R5).
if [ "${1:-}" = "--help" ]; then
  [ -n "${FAKE_NO_RESTRICTED:-}" ] || echo "  --restricted                          Restricted mode: ..."
  echo "  --tools <tools...>"
  exit 0
fi
for a in "$@"; do printf '%s\n' "$a"; done > "$CLAUDE_ARGV"
# FAKE_WRITE="<path>|<content>" plays a model that edits a file in the repository.
if [ -n "${FAKE_WRITE:-}" ]; then
  mkdir -p "$(dirname "${FAKE_WRITE%%|*}")"; printf '%b' "${FAKE_WRITE#*|}" > "${FAKE_WRITE%%|*}"
fi
echo "fake claude ran"
exit "${FAKE_EXIT:-0}"
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

# ---- spec 091 R5 (F080): the model is confined to the repository -------------------------------
R=$(mkrepo r5)
A="$TMP/argv.r5"
OUT=$(PATH="$BIN:$PATH" CLAUDE_ARGV="$A" TMPDIR="$TMP" bash "$R/scripts/update-template.sh" 2>&1); RC=$?
expect_eq       "091-AC-3 a clean live run still exits 0" "0" "$RC"
expect_eq       "091-AC-3 claude is started --restricted" "--restricted" "$(grep -x -- --restricted "$A")"
expect_eq       "091-AC-3 claude runs in dontAsk mode" "dontAsk" "$(argv_after "$A" --permission-mode)"
TOOLS=$(argv_after "$A" --tools)
expect_eq       "091-AC-3 --tools names exactly the allowed list" "$(argv_after "$A" --allowedTools)" "$TOOLS"
expect_contains "091-AC-3 --tools keeps WebFetch (restricted mode drops it otherwise)" "WebFetch" "$TOOLS"
expect_absent   "091-AC-3 --tools has no Bash" "Bash" "$TOOLS"
DIS=$(argv_after "$A" --disallowedTools)
expect_contains "091-AC-3 .mcp.json edits are denied" "Edit(.mcp.json)" "$DIS"
expect_contains "091-AC-3 .mcp.json writes are denied" "Write(.mcp.json)" "$DIS"

R=$(mkrepo old)
A="$TMP/argv.old"; rm -f "$A"
OUT=$(PATH="$BIN:$PATH" FAKE_NO_RESTRICTED=1 CLAUDE_ARGV="$A" TMPDIR="$TMP" bash "$R/scripts/update-template.sh" 2>&1); RC=$?
expect_eq       "091-AC-3 a claude without --restricted is refused (exit 2)" "2" "$RC"
expect_contains "091-AC-3 the refusal names the fix" "Update Claude Code" "$OUT"
expect_eq       "091-AC-3 the model never started" "no" "$([ -f "$A" ] && echo yes || echo no)"

R=$(mkrepo hooks)
A="$TMP/argv.hooks"
OUT=$(PATH="$BIN:$PATH" FAKE_WRITE="$R/.claude/skills/x/SKILL.md|---\nname: x\nhooks:\n  PreToolUse: []\n---\nbody\n" \
      CLAUDE_ARGV="$A" TMPDIR="$TMP" bash "$R/scripts/update-template.sh" 2>&1); RC=$?
expect_eq       "091-AC-3 a skill gaining hooks: exits 4" "4" "$RC"
expect_contains "091-AC-3 it is named [REVIEW]" "[REVIEW] .claude/skills/x/SKILL.md" "$OUT"

R=$(mkrepo quoted)
OUT=$(PATH="$BIN:$PATH" FAKE_WRITE="$R/.claude/agents/a.md|---\r\nname: a\r\n\"permissionMode\" : bypassPermissions\r\n---\r\n" \
      CLAUDE_ARGV="$TMP/argv.q" TMPDIR="$TMP" bash "$R/scripts/update-template.sh" 2>&1); RC=$?
expect_eq       "R5 a quoted permissionMode in CRLF frontmatter is caught" "4" "$RC"

R=$(mkrepo body)
OUT=$(PATH="$BIN:$PATH" FAKE_WRITE="$R/.claude/skills/y/SKILL.md|---\nname: y\n---\nhooks: are explained here\n" \
      CLAUDE_ARGV="$TMP/argv.b" TMPDIR="$TMP" bash "$R/scripts/update-template.sh" 2>&1); RC=$?
expect_eq       "R5 'hooks:' in the body, not the frontmatter, is not a review" "0" "$RC"

R=$(mkrepo script)
OUT=$(PATH="$BIN:$PATH" FAKE_WRITE="$R/.claude/skills/z/run.sh|echo hi\n" \
      CLAUDE_ARGV="$TMP/argv.s" TMPDIR="$TMP" bash "$R/scripts/update-template.sh" 2>&1); RC=$?
expect_eq       "R5 a new script under a skill is a review" "4" "$RC"
expect_contains "R5 it says why" "not markdown" "$OUT"

R=$(mkrepo rules095); mkdir -p "$R/.claude/rules"
OUT=$(PATH="$BIN:$PATH" FAKE_WRITE="$R/.claude/rules/new-rule.md|# A rule\nAlways do x.\n" \
      CLAUDE_ARGV="$TMP/argv.r95" TMPDIR="$TMP" bash "$R/scripts/update-template.sh" 2>&1); RC=$?
expect_eq       "095-R11 a changed rule is a review (exit 4)" "4" "$RC"
expect_contains "095-R11 it is named as prompt text" "[REVIEW] .claude/rules/new-rule.md: prompt text" "$OUT"
R=$(mkrepo docs095); mkdir -p "$R/.claude/docs"
OUT=$(PATH="$BIN:$PATH" FAKE_WRITE="$R/.claude/docs/d.md|text\n" \
      CLAUDE_ARGV="$TMP/argv.d95" TMPDIR="$TMP" bash "$R/scripts/update-template.sh" 2>&1); RC=$?
expect_contains "095-R11 a changed doc is named" "[REVIEW] .claude/docs/d.md" "$OUT"
R=$(mkrepo claudemd095)
OUT=$(PATH="$BIN:$PATH" FAKE_WRITE="$R/CLAUDE.md|# CLAUDE.md\nnew line\n" \
      CLAUDE_ARGV="$TMP/argv.c95" TMPDIR="$TMP" bash "$R/scripts/update-template.sh" 2>&1); RC=$?
expect_contains "095-R11 a changed CLAUDE.md is named" "[REVIEW] CLAUDE.md" "$OUT"

R=$(mkrepo failed)
OUT=$(PATH="$BIN:$PATH" FAKE_EXIT=3 FAKE_WRITE="$R/.claude/skills/x/SKILL.md|---\nhooks: {}\n---\n" \
      CLAUDE_ARGV="$TMP/argv.f" TMPDIR="$TMP" bash "$R/scripts/update-template.sh" 2>&1); RC=$?
expect_eq       "R5 claude's own failure code wins over 4" "3" "$RC"
expect_contains "R5 the review is still printed" "[REVIEW]" "$OUT"

R=$(mkrepo usage)
OUT=$(PATH="$BIN:$PATH" CLAUDE_ARGV="$TMP/argv.u" TMPDIR="$TMP" bash "$R/scripts/update-template.sh" --bogus 2>&1); RC=$?
expect_eq       "an unknown argument exits 1" "1" "$RC"
expect_contains "and says which" "Unknown argument: --bogus" "$OUT"
OUT=$(PATH="$BIN:$PATH" CLAUDE_ARGV="$TMP/argv.f" TMPDIR="$TMP" bash "$R/scripts/update-template.sh" --dry-run --focus skills 2>&1)
expect_contains "--dry-run says so in the banner" "DRY RUN" "$OUT"
expect_contains "--focus is named in the banner" "Focus: skills" "$OUT"
expect_contains "--focus reaches the prompt" "skills" "$(cat "$TMP/argv.f")"
OUT=$(PATH="$BIN:$PATH" CLAUDE_ARGV="$TMP/argv.l" TMPDIR="$TMP" bash "$R/scripts/update-template.sh" 2>&1)
expect_absent   "a live run without --focus names no focus" "Focus:" "$OUT"
expect_contains "a live run says LIVE" "LIVE" "$OUT"
OUT=$(PATH="$BIN:$PATH" FAKE_EXIT=5 CLAUDE_ARGV="$TMP/argv.e" TMPDIR="$TMP" bash "$R/scripts/update-template.sh" 2>&1); RC=$?
expect_eq       "claude's failure is the exit code" "5" "$RC"
expect_contains "and is reported as an error" "Error occurred (exit code: 5)" "$OUT"
expect_absent   "not as done" "Done! Log saved" "$OUT"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

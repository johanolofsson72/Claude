#!/bin/bash
# PostToolUse hook on AskUserQuestion: records the developer's answers, hashed (spec 088 R4, F094).
#
# acceptance-cases.sh --confirm writes a Confirmed line only for a quote that equals an answer recorded
# here, given to a question that showed the cases' digest. Before 088 the quote was whatever the agent
# typed, so "never confirm on the developer's behalf" was a sentence and nothing more.
#
# One line per answered question goes to <git-common-dir>/claude-developer-words: the time, the
# SHA-256 of the whitespace-collapsed answer, and every 12-hex token in the question text. No answer is
# stored as text. The format and the reader live in acceptance_cases.py, beside the one that checks it.
# scripts/trust-anchor-guard-hook.sh keeps the agent's tools out of the file.
#
# The repository is CLAUDE_PROJECT_DIR (the harness sets it; the agent cannot change a hook's
# environment), else the payload's cwd. A payload it cannot read records nothing: PostToolUse cannot
# block, and the cost of a missing line is a refused --confirm that says how to ask again.
# Silent on stdout. Exit: always 0.

set -u
INPUT=$(cat 2>/dev/null || true)
[ -n "$INPUT" ] || exit 0
HOOK_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
printf '%s' "$INPUT" | python3 "$HOOK_DIR/acceptance_cases.py" record-answers "${CLAUDE_PROJECT_DIR:-}" >/dev/null 2>&1
exit 0

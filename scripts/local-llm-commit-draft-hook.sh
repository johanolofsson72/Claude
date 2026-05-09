#!/usr/bin/env bash
# PostToolUse hook for Bash. After `git add`, draft a Conventional Commit
# message locally and stash it at .claude/.local-llm-commit-draft.md.
# The path is surfaced to the assistant via additionalContext so the next
# `git commit` step can read and refine it instead of starting from scratch.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$CMD" ] || exit 0

# Fire only on `git add` invocations (not `git status`, `git log`, etc.)
echo "$CMD" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+add([[:space:]]|$)' || exit 0

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

DIFF_STAT=$(git -C "$REPO_ROOT" diff --cached --stat 2>/dev/null)
[ -n "$DIFF_STAT" ] || exit 0

DIFF_FULL=$(git -C "$REPO_ROOT" diff --cached 2>/dev/null | head -c 6000)

SYSTEM='Draft a Conventional Commit message for the staged diff.
Format:
<type>(<optional-scope>): <subject>

<optional body, wrapped at 72 chars>

Rules:
- type ∈ {feat, fix, refactor, test, docs, style, chore, perf, build, ci}
- subject: imperative mood, lowercase first word, no trailing period, ≤60 chars
- no emoji, no marketing language, no Co-authored-by, no AI attribution
- include a body only if the diff genuinely needs context
Output ONLY the message. No preamble, no code fences.'

DRAFT=$(printf 'Files changed:\n%s\n\nDiff (truncated):\n%s\n' "$DIFF_STAT" "$DIFF_FULL" \
  | bash "$SCRIPT_DIR/local-llm-call.sh" "$SYSTEM" 384 2>/dev/null)

[ -n "$DRAFT" ] || exit 0

DRAFT_DIR="$REPO_ROOT/.claude"
DRAFT_PATH="$DRAFT_DIR/.local-llm-commit-draft.md"
mkdir -p "$DRAFT_DIR"
printf '%s\n' "$DRAFT" > "$DRAFT_PATH"

jq -nc --arg p "$DRAFT_PATH" \
  '{additionalContext: ("Local-LLM commit-message draft saved at " + $p + ". Read and refine before running `git commit` — do not commit it verbatim without sanity-checking against the actual diff.")}'

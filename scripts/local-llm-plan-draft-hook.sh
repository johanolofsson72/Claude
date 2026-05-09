#!/usr/bin/env bash
# PostToolUse Edit/Write hook. When a speckit spec.md is written, draft an
# initial plan.md to <spec-dir>/.local-llm-plan-draft.md so the subsequent
# /plan step refines the draft instead of generating from scratch.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$FILE" ] || exit 0

case "$FILE" in
  */specs/*/spec.md|*/.specify/specs/*/spec.md) ;;
  *) exit 0 ;;
esac
[ -r "$FILE" ] || exit 0

SPEC=$(head -c 24000 "$FILE")
[ -n "$SPEC" ] || exit 0

SYSTEM='You draft a plan.md for a speckit-style feature spec.

Output sections (use these headings exactly):

# Plan

## Approach
<2-5 sentences on the technical approach: which layers/files, which patterns from the existing codebase>

## Phases
1. <Phase name> — <one-line description>
2. ...

## Files affected
- <path> — <create | modify | delete> — <one-line reason>

## Risks
- <risk> — <mitigation>

## Out of scope
- <bullet of what is NOT in this spec>

Rules:
- Be specific. Cite likely file paths from the spec.
- Phases must include: setup, core implementation, tests, wiring, docs, deploy/rollback if applicable.
- Risks must include any data migrations, breaking changes, or perf concerns implied by the spec.
- 30-80 lines total.
- No preamble, no extra prose.'

DRAFT=$(printf 'Spec:\n%s\n' "$SPEC" \
  | bash "$SCRIPT_DIR/local-llm-call.sh" "$SYSTEM" 1536 2>/dev/null)

[ -n "$DRAFT" ] || exit 0

DRAFT_DIR=$(dirname "$FILE")
DRAFT_PATH="$DRAFT_DIR/.local-llm-plan-draft.md"
printf '%s\n' "$DRAFT" > "$DRAFT_PATH"

jq -nc --arg p "$DRAFT_PATH" \
  '{additionalContext: ("Local-LLM plan-draft saved at " + $p + ". When you run /plan for this spec, read and refine this draft instead of generating from scratch — verify approach, phase ordering, and file impacts against the actual codebase before writing the real plan.md.")}'

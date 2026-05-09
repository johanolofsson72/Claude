#!/usr/bin/env bash
# UserPromptSubmit hook: classify the incoming prompt via local LLM
# and inject a routing hint as additionalContext. Silent no-op when
# Ollama is offline or the prompt is too short to bother with.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)
[ -n "$PROMPT" ] || exit 0
[ ${#PROMPT} -gt 20 ] || exit 0

# Tight timeout so we never block the user for long on the prompt path.
LOCAL_LLM_TIMEOUT="${LOCAL_LLM_CLASSIFY_TIMEOUT:-4}"
export LOCAL_LLM_TIMEOUT

SYSTEM='You classify a developer prompt to a coding assistant.
Reply with EXACTLY one line in this format and nothing else:
TOKEN | <reason in <=12 words>

Tokens:
- TRIVIAL  : greeting, status check, single-line question, simple file read
- MEDIUM   : focused implementation, single-component bug fix or refactor
- COMPLEX  : architecture work, multi-file feature, anything mentioning specs, Allium, TLA+, migrations, or production deploy

Output ONLY that one line. No preamble, no markdown.'

RESULT=$(printf '%s' "$PROMPT" \
  | bash "$SCRIPT_DIR/local-llm-call.sh" "$SYSTEM" 48 2>/dev/null \
  | head -n1)

[ -n "$RESULT" ] || exit 0

jq -nc --arg c "$RESULT" \
  '{additionalContext: ("Local-LLM complexity hint (advisory): " + $c + "\nUse as routing signal only — your judgement overrides.")}'

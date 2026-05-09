#!/usr/bin/env bash
# Generic non-streaming Ollama caller.
#
# Usage:  echo "user prompt" | local-llm-call.sh "system prompt" [num_predict]
#
# Prints model output on stdout. Exits 0 on success, non-zero on any failure
# (offline, timeout, missing model, malformed response). Callers should treat
# non-zero / empty stdout as "no offload available, carry on".

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/local-llm-detect.sh"

[ "${LOCAL_LLM_AVAILABLE:-0}" = "1" ] || exit 1
command -v jq >/dev/null 2>&1 || exit 1

SYSTEM_PROMPT="${1:-}"
NUM_PREDICT="${2:-256}"

USER_PROMPT="$(cat)"
[ -n "$USER_PROMPT" ] || exit 1

PAYLOAD=$(jq -nc \
  --arg model "$LOCAL_LLM_MODEL" \
  --arg system "$SYSTEM_PROMPT" \
  --arg prompt "$USER_PROMPT" \
  --argjson num_predict "$NUM_PREDICT" \
  '{
    model: $model,
    system: $system,
    prompt: $prompt,
    stream: false,
    options: { temperature: 0.2, num_predict: $num_predict }
  }')

RESPONSE=$(curl -sf --max-time "$LOCAL_LLM_TIMEOUT" \
  -X POST "${LOCAL_LLM_HOST}/api/generate" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" 2>/dev/null) || exit 1

printf '%s' "$RESPONSE" | jq -r '.response // empty' 2>/dev/null

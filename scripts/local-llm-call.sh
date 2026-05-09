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

# Entry tracer — proves the script was invoked at all. Survives every
# downstream early-exit, so a missing telemetry row that has a tracer line
# means the failure is in the telemetry block (not before).
TRACE_LOG="${LOCAL_LLM_TRACE_LOG:-$HOME/.claude/local-llm-trace.log}"
{
  mkdir -p "$(dirname "$TRACE_LOG")" 2>/dev/null
  PARENT_CMD=$(ps -o args= -p "$PPID" 2>/dev/null | head -c 200)
  printf '%s\tpid=%s\tppid=%s\tparent=%s\n' \
    "$(date +%Y-%m-%dT%H:%M:%S%z 2>/dev/null)" "$$" "$PPID" "$PARENT_CMD" \
    >> "$TRACE_LOG" 2>/dev/null
} || true

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

T0=$(date +%s)
RESPONSE=$(curl -sf --max-time "$LOCAL_LLM_TIMEOUT" \
  -X POST "${LOCAL_LLM_HOST}/api/generate" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" 2>/dev/null)
CURL_EXIT=$?
T1=$(date +%s)

if [ "${LOCAL_LLM_TELEMETRY_DISABLE:-0}" != "1" ]; then
  # Pipefail off for the ps|grep|head pipeline — head -1 closing early can
  # otherwise mark the assignment "failed" under set -uo pipefail and
  # interact badly with later steps.
  set +o pipefail
  HOOK_NAME=$(ps -o args= -p "$PPID" 2>/dev/null \
    | grep -oE 'local-llm-[a-z-]+-hook' | head -1 || true)
  set -o pipefail
  HOOK_NAME=${HOOK_NAME:-unknown}
  TELEMETRY_LOG="${LOCAL_LLM_TELEMETRY_LOG:-$HOME/.claude/local-llm-fire.log}"
  TELEMETRY_ERR="${TELEMETRY_LOG}.errors"
  mkdir -p "$(dirname "$TELEMETRY_LOG")" 2>>"$TELEMETRY_ERR" || true
  TS=$(date +%Y-%m-%dT%H:%M:%S%z 2>/dev/null || echo "?")
  DURATION=$((T1 - T0))
  PROMPT_BYTES=${#USER_PROMPT}
  if ! printf '%s\t%s\t%d\t%d\t%d\n' \
    "$TS" "$HOOK_NAME" "${CURL_EXIT:-99}" "$DURATION" "$PROMPT_BYTES" \
    >> "$TELEMETRY_LOG" 2>>"$TELEMETRY_ERR"; then
    printf 'WRITE_FAIL %s pid=%s ppid=%s\n' "$TS" "$$" "$PPID" \
      >> "$TELEMETRY_ERR" 2>/dev/null || true
  fi
fi

[ $CURL_EXIT -eq 0 ] || exit 1
printf '%s' "$RESPONSE" | jq -r '.response // empty' 2>/dev/null

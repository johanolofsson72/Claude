#!/usr/bin/env bash
# Detect whether a local LLM (Ollama) is reachable and export config.
#
# Sourced by the local-llm-* hook scripts. After sourcing, callers should
# check $LOCAL_LLM_AVAILABLE (1 = ready, 0 = offline / disabled / missing).
#
# Honored env vars (all optional):
#   OLLAMA_HOST          base URL, default http://localhost:11434
#   LOCAL_LLM_MODEL      model tag, default llama3:8b
#   LOCAL_LLM_TIMEOUT    seconds for generation calls, default 15
#   LOCAL_LLM_DETECT_TIMEOUT  seconds for the reachability ping, default 1
#   LOCAL_LLM_DISABLE    set to 1 to force-disable the offload hooks

LOCAL_LLM_HOST="${OLLAMA_HOST:-http://localhost:11434}"
LOCAL_LLM_MODEL="${LOCAL_LLM_MODEL:-llama3}"
LOCAL_LLM_TIMEOUT="${LOCAL_LLM_TIMEOUT:-15}"
LOCAL_LLM_DETECT_TIMEOUT="${LOCAL_LLM_DETECT_TIMEOUT:-1}"

if [ "${LOCAL_LLM_DISABLE:-0}" = "1" ]; then
  LOCAL_LLM_AVAILABLE=0
elif command -v curl >/dev/null 2>&1 \
  && curl -sf --max-time "$LOCAL_LLM_DETECT_TIMEOUT" \
       "${LOCAL_LLM_HOST}/api/tags" >/dev/null 2>&1; then
  LOCAL_LLM_AVAILABLE=1
else
  LOCAL_LLM_AVAILABLE=0
fi

export LOCAL_LLM_HOST LOCAL_LLM_MODEL LOCAL_LLM_TIMEOUT \
       LOCAL_LLM_DETECT_TIMEOUT LOCAL_LLM_AVAILABLE

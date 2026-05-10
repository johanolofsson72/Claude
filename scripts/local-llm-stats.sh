#!/usr/bin/env bash
# Per-hook ROI report for local-LLM offload hooks.
#
# Reads the telemetry log written by local-llm-call.sh and prints a table:
#   hook  fires  ok%  avg(s)  fail_time(s)  avg_bytes
#
# Usage:
#   local-llm-stats.sh                       # this project (auto-detected)
#   local-llm-stats.sh --since 1d            # last 24h, this project
#   local-llm-stats.sh --since 2026-05-01    # since absolute date
#   local-llm-stats.sh --all                 # aggregate across all projects + global
#   local-llm-stats.sh --log <path>          # read a specific log

set -uo pipefail

# Argument parsing
SINCE=""
ALL=0
EXPLICIT_LOG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --since) SINCE="${2:-}"; shift 2 ;;
    --all)   ALL=1; shift ;;
    --log)   EXPLICIT_LOG="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

# Resolve which log(s) to read.
if [ -n "$EXPLICIT_LOG" ]; then
  LOGS=("$EXPLICIT_LOG")
elif [ "$ALL" = "1" ]; then
  # Walk every .claude/local-llm-fire.log under common project roots + global.
  LOGS=()
  for candidate in "$HOME/.claude/local-llm-fire.log" \
                   "$HOME/repos"/*/.claude/local-llm-fire.log \
                   "$HOME/Projects"/*/.claude/local-llm-fire.log; do
    [ -f "$candidate" ] && LOGS+=("$candidate")
  done
elif [ -n "${LOCAL_LLM_TELEMETRY_LOG:-}" ]; then
  LOGS=("$LOCAL_LLM_TELEMETRY_LOG")
else
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [ -n "$REPO_ROOT" ] && [ -f "$REPO_ROOT/.claude/local-llm-fire.log" ]; then
    LOGS=("$REPO_ROOT/.claude/local-llm-fire.log")
  elif [ -f "$HOME/.claude/local-llm-fire.log" ]; then
    LOGS=("$HOME/.claude/local-llm-fire.log")
  else
    echo "No telemetry log found. Run a few hooks first, or use --all / --log <path>."
    exit 0
  fi
fi

if [ "${#LOGS[@]}" -eq 0 ]; then
  echo "No telemetry logs found. Run a few hooks first."
  exit 0
fi

# Print which logs are in scope so the table can't lie about its source.
echo "Reading: ${LOGS[*]}"
echo

cutoff_seconds() {
  local since="$1"
  case "$since" in
    *d) echo "$(( ${since%d} * 86400 ))" ;;
    *h) echo "$(( ${since%h} * 3600  ))" ;;
    *m) echo "$(( ${since%m} * 60    ))" ;;
    *)  echo "0" ;;
  esac
}

NOW=$(date +%s)
FILTER_EPOCH=0
if [ -n "$SINCE" ]; then
  case "$SINCE" in
    *[0-9][dhm])
      FILTER_EPOCH=$(( NOW - $(cutoff_seconds "$SINCE") )) ;;
    *)
      FILTER_EPOCH=$(date -j -f "%Y-%m-%d" "$SINCE" +%s 2>/dev/null \
                  || date -d "$SINCE"      +%s 2>/dev/null \
                  || echo 0) ;;
  esac
fi

awk -v filter="$FILTER_EPOCH" '
  BEGIN { FS = "\t" }
  {
    ts = $1; hook = $2; exit_code = $3 + 0
    # Schema autodetect via NF.
    #   v1 (5 cols): ts hook exit duration_seconds prompt_bytes
    #   v2 (6 cols): ts hook exit duration_ms      prompt_bytes response_bytes
    #   v3 (7 cols): ts hook exit duration_ms      prompt_bytes response_bytes cache_hit
    cache = 0
    if (NF >= 7) {
      dur_ms = $4 + 0
      pb     = $5 + 0
      rb     = $6 + 0
      cache  = $7 + 0
      v3_rows++
    } else if (NF == 6) {
      dur_ms = $4 + 0
      pb     = $5 + 0
      rb     = $6 + 0
      v2_rows++
    } else {
      dur_ms = ($4 + 0) * 1000
      pb     = $5 + 0
      rb     = 0
      v1_rows++
    }
    if (filter > 0) {
      cmd = "date -j -f %Y-%m-%dT%H:%M:%S%z \"" ts "\" +%s 2>/dev/null \
             || date -d \"" ts "\" +%s 2>/dev/null"
      cmd | getline epoch; close(cmd)
      if (epoch + 0 < filter) next
    }
    fires[hook]++
    total_dur[hook]    += dur_ms
    total_prompt[hook] += pb
    total_resp[hook]   += rb
    total_cache[hook]  += cache
    if (exit_code == 0) ok[hook]++
    else fail_time[hook] += dur_ms
    grand++
    grand_cache += cache
    grand_prompt += pb
    grand_cache_prompt += (cache == 1 ? pb : 0)
  }
  END {
    if (grand == 0) {
      print "No fires in window."
      exit 0
    }
    printf "%-32s %6s %5s %7s %7s %12s %10s %10s\n", \
      "hook", "fires", "ok%", "cache%", "avg(s)", "fail_time(s)", "avg_prompt", "avg_resp"
    printf "%-32s %6s %5s %7s %7s %12s %10s %10s\n", \
      "----", "-----", "---", "------", "------", "-----------", "----------", "--------"
    for (h in fires) {
      n = fires[h]
      pct = (ok[h] + 0) / n * 100
      cpct = (total_cache[h] + 0) / n * 100
      avg_s = total_dur[h] / n / 1000
      ft_s  = (fail_time[h] + 0) / 1000
      ap = int(total_prompt[h] / n)
      ar = int(total_resp[h]   / n)
      printf "%-32s %6d %4.0f%% %6.0f%% %7.2f %12.1f %10d %10d\n", \
        h, n, pct, cpct, avg_s, ft_s, ap, ar
    }
    printf "\ntotal fires: %d", grand
    if (v3_rows > 0) {
      saved = grand_cache_prompt
      printf "  cache hits: %d (%.0f%%), prompt bytes spared by cache: %d", \
        grand_cache, (grand_cache / grand) * 100, saved
    }
    if (v1_rows > 0 && (v2_rows > 0 || v3_rows > 0)) {
      printf "  (mixed schema: %d v1, %d v2, %d v3)", v1_rows, v2_rows, v3_rows
    } else if (v1_rows > 0) {
      printf "  (v1 schema: avg_resp shows 0 because old logs did not record response bytes)"
    }
    printf "\n"
  }
' "${LOGS[@]}" | (
  read -r header
  read -r divider
  echo "$header"
  echo "$divider"
  sort -k2,2 -nr
)

#!/usr/bin/env bash
# Per-hook ROI report for local-LLM offload hooks.
#
# Reads the telemetry log written by local-llm-call.sh and prints a table:
#   hook  fires  ok%  avg(s)  fail_time(s)  avg_bytes
#
# Usage:
#   local-llm-stats.sh                   # all-time stats
#   local-llm-stats.sh --since 1d        # last 24h
#   local-llm-stats.sh --since 2026-05-01

set -uo pipefail

LOG="${LOCAL_LLM_TELEMETRY_LOG:-$HOME/.claude/local-llm-fire.log}"

if [ ! -f "$LOG" ]; then
  echo "No telemetry log at $LOG yet — run a few hooks first."
  exit 0
fi

SINCE=""
if [ "${1:-}" = "--since" ] && [ -n "${2:-}" ]; then
  SINCE="$2"
fi

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
    ts = $1; hook = $2; exit_code = $3 + 0; dur = $4 + 0; bytes = $5 + 0
    if (filter > 0) {
      cmd = "date -j -f %Y-%m-%dT%H:%M:%S%z \"" ts "\" +%s 2>/dev/null \
             || date -d \"" ts "\" +%s 2>/dev/null"
      cmd | getline epoch; close(cmd)
      if (epoch + 0 < filter) next
    }
    fires[hook]++
    total_dur[hook] += dur
    total_bytes[hook] += bytes
    if (exit_code == 0) ok[hook]++
    else fail_time[hook] += dur
    grand++
  }
  END {
    if (grand == 0) {
      print "No fires in window."
      exit 0
    }
    printf "%-32s %6s %5s %7s %12s %10s\n", \
      "hook", "fires", "ok%", "avg(s)", "fail_time(s)", "avg_bytes"
    printf "%-32s %6s %5s %7s %12s %10s\n", \
      "----", "-----", "---", "------", "-----------", "---------"
    for (h in fires) {
      n = fires[h]
      pct = (ok[h] + 0) / n * 100
      avg = total_dur[h] / n
      ab  = int(total_bytes[h] / n)
      printf "%-32s %6d %4.0f%% %7.2f %12d %10d\n", \
        h, n, pct, avg, fail_time[h] + 0, ab
    }
    printf "\ntotal fires: %d\n", grand
  }
' "$LOG" | (
  read -r header
  read -r divider
  echo "$header"
  echo "$divider"
  sort -k2,2 -nr
)

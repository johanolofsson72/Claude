#!/bin/bash
# tlc-cleanup.sh — kill TLC runs that outlived their bound; leave live runs and shells alone.
#
# Wired from PostToolUse(Bash), Stop, SubagentStop and SessionEnd, and run by /tla after each run.
# It used to `pkill -f tla2tools`, which matches whole command lines: it killed the hook's own shell
# and any Bash tool shell that mentioned the jar (exit 144, the 056 trap), and a /tla subagent's
# live run whenever another agent stopped (ekofak 005, hireflow 017 — register row 069).
#
# A TLC process here is a `java` process whose arguments name tla2tools or tlc2.TLC. /tla bounds
# every run with `timeout -k 10 300`, so a TLC process older than that has escaped its bound: that
# runaway is what this script kills. Anything younger is a live run and is left alone.
#
# PROJECT-SCOPED (spec 086, F070). Every project's Stop and SessionEnd hooks run this, so a machine-wide
# sweep let one project's session kill another project's deliberate long run. A TLC process counts only
# when its working directory is inside this project's root (CLAUDE_PROJECT_DIR, else the git toplevel,
# else $PWD), read from /proc on Linux and lsof elsewhere. A process whose directory cannot be read is
# left alone and named: killing what cannot be attributed is the defect. --any-project is the manual
# machine-wide sweep for the runaway nobody owns.
#
# Usage: tlc-cleanup.sh [--all] [--any-project] [--max-age SECONDS] [--only TEXT] [--dry-run]
#   --all        kill every TLC process whatever its age (manual use; no hook passes it)
#   --any-project  whatever project it runs in (manual use; no hook passes it)
#   --max-age N  age in seconds past which a run is runaway (default $TLC_MAX_SECONDS or 320)
#   --only TEXT  also require TEXT in the arguments (default $TLC_CLEANUP_ONLY; tests scope with it)
#   --dry-run    print what would be killed, kill nothing
# Exit: 0 nothing left running, 1 a process survived SIGKILL, 2 bad argument or no project root,
#       3 cannot list processes.

MAX_AGE="${TLC_MAX_SECONDS:-320}"
ONLY="${TLC_CLEANUP_ONLY:-}"
ALL=0; DRY=0; ANY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --all) ALL=1 ;;
    --any-project) ANY=1 ;;
    --dry-run) DRY=1 ;;
    --max-age) MAX_AGE="${2:-}"; shift ;;
    --only) ONLY="${2:-}"; shift ;;
    *) echo "tlc-cleanup: unknown argument '$1'" >&2; exit 2 ;;
  esac
  shift
done
case "$MAX_AGE" in ''|*[!0-9]*) echo "tlc-cleanup: --max-age wants whole seconds, got '$MAX_AGE'" >&2; exit 2 ;; esac
[ "$ALL" -eq 1 ] && MAX_AGE=-1

SCOPE=""
if [ "$ANY" -eq 0 ]; then
  SCOPE=${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}
  SCOPE=$(cd -P -- "$SCOPE" 2>/dev/null && pwd -P) || {
    echo "tlc-cleanup: project root '${CLAUDE_PROJECT_DIR:-}' does not exist — nothing was cleaned" >&2; exit 2; }
fi

cwd_of() { # cwd_of PID — the process's working directory, physical, or nothing
  local d=""
  if [ -e "/proc/$1/cwd" ]; then
    d=$(readlink "/proc/$1/cwd" 2>/dev/null)
  elif command -v lsof >/dev/null 2>&1; then
    d=$(lsof -a -p "$1" -d cwd -Fn 2>/dev/null | awk '/^n/ { print substr($0, 2) }')
  fi
  [ -n "$d" ] && (cd -P -- "$d" 2>/dev/null && pwd -P)
}

# Reads list_runaways' lines on stdin and keeps this project's. A process whose directory cannot be
# read goes to stderr once, by pid, and is not killed.
in_scope() {
  local pid age args d
  while read -r pid age args; do
    [ -n "$pid" ] || continue
    if [ -z "$SCOPE" ]; then printf '%s %s %s\n' "$pid" "$age" "$args"; continue; fi
    # region: project-scope — a run in another project's tree is that project's to end
    d=$(cwd_of "$pid")
    if [ -z "$d" ]; then
      echo "tlc-cleanup: pid $pid (age ${age}s) — cannot read its working directory, so cannot tell whose run it is; left alone (--any-project kills it)" >&2
      continue
    fi
    case "$d/" in "$SCOPE"/*) ;; *) continue ;; esac
    # endregion
    printf '%s %s %s\n' "$pid" "$age" "$args"
  done
}

# Prints "<pid> <age-seconds> <args>" for each TLC process past MAX_AGE.
list_runaways() {
  local ps_out
  if ! ps_out=$(ps -A -o pid=,etime=,args= 2>/dev/null); then
    echo "tlc-cleanup: 'ps -A -o pid=,etime=,args=' is not supported here (Git Bash?) — nothing was cleaned" >&2
    return 3
  fi
  printf '%s\n' "$ps_out" | awk -v max="$MAX_AGE" -v only="$ONLY" '
    # etime is [[dd-]hh:]mm:ss
    function secs(e,   d, n, a, i, s) {
      d = 0
      if (index(e, "-")) { d = substr(e, 1, index(e, "-") - 1); e = substr(e, index(e, "-") + 1) }
      n = split(e, a, ":"); s = 0
      for (i = 1; i <= n; i++) s = s * 60 + a[i]
      return d * 86400 + s
    }
    {
      pid = $1; age = secs($2)
      args = $0; sub(/^[ \t]*[0-9]+[ \t]+[0-9:-]+[ \t]+/, "", args)
      if (args !~ /tla2tools|tlc2\.TLC/) next
      if (only != "" && index(args, only) == 0) next
      # region: argv0-java — a shell, timeout, editor or grep naming the jar is not TLC
      prog = $3; sub(/.*[\/\\]/, "", prog); sub(/\.exe$/, "", prog)
      if (prog != "java") next
      # endregion
      # region: age-bound — a run younger than the bound is live
      if (age <= max) next
      # endregion
      print pid, age, args
    }'
}

RUNAWAYS=$(list_runaways) || exit 3
RUNAWAYS=$(in_scope <<< "$RUNAWAYS")
[ -z "$RUNAWAYS" ] && exit 0

VERB="killed"; [ "$DRY" -eq 1 ] && VERB="would kill"
while read -r pid age args; do
  echo "tlc-cleanup: $VERB pid $pid (age ${age}s) $args"
  [ "$DRY" -eq 1 ] || kill "$pid" 2>/dev/null
done <<< "$RUNAWAYS"
[ "$DRY" -eq 1 ] && exit 0

# Re-list rather than reuse the PIDs: a PID freed by SIGTERM and reused by another program in the
# meantime no longer passes the filter and is not hit by SIGKILL.
sleep 1
SURVIVORS=$(list_runaways) || exit 3
SURVIVORS=$(in_scope <<< "$SURVIVORS" 2>/dev/null)
[ -z "$SURVIVORS" ] && exit 0
while read -r pid age args; do
  echo "tlc-cleanup: pid $pid ignored SIGTERM — sending SIGKILL"
  kill -9 "$pid" 2>/dev/null
done <<< "$SURVIVORS"
sleep 0.5
LEFT=$(list_runaways) || exit 3
LEFT=$(in_scope <<< "$LEFT" 2>/dev/null)
if [ -n "$LEFT" ]; then
  echo "tlc-cleanup: ERROR — still running after SIGKILL:"
  printf '%s\n' "$LEFT"
  exit 1
fi
exit 0

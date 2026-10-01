#!/usr/bin/env bash
. "$(dirname -- "$0")/self-test-env.sh" || exit 1
#
# test-on-linux.sh — run the template's own shell tests on GNU/Linux, from a Mac.
#
# WHY THIS EXISTS. The template is written on macOS and used on Linux (David) and
# Git Bash on Windows. Every portability bug found so far had the same shape: it
# passed on the machine it was written on and failed quietly on the other one —
# `find -printf` enumerating 0 of 135 test classes on macOS, `stat -f` filling a
# worktree age with filesystem info on Linux. portability_audit.py catches the
# constructs it knows about; this catches the rest, by actually running the tests
# under GNU coreutils and bash 5.
#
# How: an ubuntu:24.04 container with bash, python3, git, jq, coreutils. The repo
# is mounted READ-ONLY at /repo and copied into the container's own filesystem
# before anything runs, so a test that writes (and most do) can never touch the
# working tree on the host. Tests run as an unprivileged user, because several of
# them assert on permission failures that root would sail straight through.
#
# The image is built once and cached by Docker (tag below); the first run pays for
# apt, later runs start in about a second.
#
# Usage:
#   bash scripts/test-on-linux.sh                         # the default set below
#   bash scripts/test-on-linux.sh test-finding.sh ...     # just these (scripts/ names)
#   bash scripts/test-on-linux.sh --rebuild               # refresh the cached image
#
# Exit: 0 all passed, or SKIPPED because Docker is unavailable (says so loudly)
#       1 at least one test failed · 2 could not run (image build failed)

set -uo pipefail

SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd "$SELF_DIR/.." && pwd -P)
IMAGE="claude-template-linux-test:ubuntu-24.04"

DEFAULT_TESTS="validate-portability.sh validate-portability.sh:--all test-portability-audit.sh test-install-global-skills.sh test-pipeline-hooks.sh"

REBUILD=0; TESTS=""
for a in "$@"; do
  case "$a" in
    --rebuild) REBUILD=1 ;;
    -h|--help) sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "test-on-linux.sh: unknown argument '$a'" >&2; exit 2 ;;
    *) TESTS="$TESTS $a" ;;
  esac
done
[ -n "$TESTS" ] || TESTS="$DEFAULT_TESTS"

# A skip must be impossible to mistake for a pass: exit 0 so it can sit in a
# larger local run, but say in words that nothing was tested.
if ! command -v docker >/dev/null 2>&1; then
  echo "test-on-linux.sh: SKIPPED — docker is not installed. Nothing was tested on Linux."
  exit 0
fi
if ! docker info >/dev/null 2>&1; then
  echo "test-on-linux.sh: SKIPPED — docker is installed but the daemon is not reachable. Nothing was tested on Linux."
  exit 0
fi

# Git Bash rewrites /repo-style arguments into Windows paths unless told not to.
export MSYS_NO_PATHCONV=1

if [ "$REBUILD" -eq 1 ] || ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "test-on-linux.sh: building $IMAGE (cached after the first run)…"
  # procps: pgrep/pkill, which the TLC cleanup and several hooks use.
  docker build -q -t "$IMAGE" - >/dev/null <<'DOCKERFILE' || { echo "test-on-linux.sh: image build failed" >&2; exit 2; }
FROM ubuntu:24.04
RUN apt-get update -qq \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
      bash python3 git jq coreutils findutils diffutils grep sed gawk procps ca-certificates \
 && rm -rf /var/lib/apt/lists/*
RUN useradd -m tester \
 && su tester -c 'git config --global user.name "Linux Test" && git config --global user.email test@example.invalid && git config --global init.defaultBranch main'
USER tester
WORKDIR /home/tester
DOCKERFILE
fi

# The in-container runner. Each test is reported on one line; the full output is
# printed only for a failure, which is the case anyone reads it for.
# `name:args` in the list passes args (validate-portability.sh:--all).
RUNNER='
set -u
cp -a /repo /home/tester/work 2>/dev/null || { echo "copy of /repo failed"; exit 2; }
cd /home/tester/work
echo "== $(bash --version | head -1)"
echo "== $(stat --version | head -1)"
FAILED=0
for spec in $TESTS; do
  name=${spec%%:*}; args=""
  case "$spec" in *:*) args=$(printf "%s" "${spec#*:}" | tr ":" " ") ;; esac
  if [ ! -f "scripts/$name" ]; then
    echo "MISSING  $name"; FAILED=$((FAILED + 1)); continue
  fi
  out=$(bash "scripts/$name" $args 2>&1); rc=$?
  summary=$(printf "%s\n" "$out" | grep -E "passed|clean|Total|finding" | tail -1)
  if [ "$rc" -eq 0 ]; then
    echo "PASS     $name $args — $summary"
  else
    echo "FAIL     $name $args (exit $rc)"
    printf "%s\n" "$out" | tail -40 | sed "s/^/         /"
    FAILED=$((FAILED + 1))
  fi
done
echo "== $FAILED failing"
[ "$FAILED" -eq 0 ]
'

echo "test-on-linux.sh: running in $IMAGE — repo mounted read-only, copied before use"
docker run --rm -e TESTS="$TESTS" -v "$ROOT:/repo:ro" "$IMAGE" bash -c "$RUNNER"
RC=$?
[ "$RC" -eq 0 ] && echo "test-on-linux.sh: all passed on Linux" || echo "test-on-linux.sh: FAILURES on Linux (exit $RC)"
[ "$RC" -eq 0 ] && exit 0
[ "$RC" -eq 2 ] && exit 2
exit 1

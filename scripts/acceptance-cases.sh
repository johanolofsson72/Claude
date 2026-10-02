#!/usr/bin/env bash
# acceptance-cases.sh — developer-confirmed acceptance cases for a full or hardened spec (spec 080).
#
#   --check    <spec-dir>                    parse acceptance.md; exit 0 confirmed, 3 unconfirmed or
#                                            changed since confirmation, 1 malformed, 2 missing
#   --digest   <spec-dir>                    the digest a Confirmed line must carry
#   --question <spec-dir>                    the AskUserQuestion text to show (digest, every case in
#                                            full); the developer confirms by picking "Confirm"
#   --confirm  <spec-dir> --quote "<words>"  write the Confirmed line, quoting the developer's answer
#                                            (only after they answered an AskUserQuestion)
#   --coverage <spec-dir> [--root <dir>]     which <spec-id>-AC-<n> a test file names; exit 1 if any
#                                            case has none (root defaults to <spec-dir>/../..)
#   --is-test  <path>                        exit 0 when the path is a test file by convention
#
# The parser, digest and coverage scan live in acceptance_cases.py, shared with
# spec-interview-guard-hook.sh so the helper and the gate cannot disagree.

set -u
HERE="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PY="$HERE/acceptance_cases.py"

usage() { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

[ $# -ge 2 ] || usage
cmd="$1"; target="$2"; shift 2
case "$cmd" in
  --check)  exec python3 "$PY" check "$target" ;;
  --digest) exec python3 "$PY" digest "$target" ;;
  --question) exec python3 "$PY" question "$target" ;;
  --is-test) exec python3 "$PY" is-test "$target" ;;
  --confirm)
    [ "${1:-}" = "--quote" ] && [ $# -ge 2 ] || usage
    exec python3 "$PY" confirm "$target" "$2" ;;
  --coverage)
    root=""
    if [ "${1:-}" = "--root" ] && [ $# -ge 2 ]; then root="$2"; fi
    # The guard scans the project root (the directory holding specs/INDEX.md), so the default
    # here is the same directory: <root>/specs/<id>-<slug>.
    if [ -z "$root" ]; then root=$(cd "$target/../.." 2>/dev/null && pwd) || { echo "acceptance-cases: cannot find the project root of $target; pass --root" >&2; exit 2; }; fi
    base=$(basename "$target")
    spec_id="${base%%-*}"
    exec python3 "$PY" coverage "$target" "$root" "$spec_id" ;;
  *) usage ;;
esac

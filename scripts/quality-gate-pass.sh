#!/usr/bin/env bash
# quality-gate-pass.sh — see scripts/quality_gates.py (spec 020).
#   bench: bash scripts/quality-gate-bench.sh [--corpus DIR] [--table FILE] [--only hook,hook]
#          exit 0 scored · 2 corpus does not load · 3 no model (nothing changed)
#   pass:  bash scripts/quality-gate-pass.sh [--table FILE]   (run from inside the project)
#          exit 0 ran or nothing to do · 3 no model (nothing changed)
set -u
exec python3 "$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/quality_gates.py" pass "$@"

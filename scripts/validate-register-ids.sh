#!/usr/bin/env bash
# Gate: every id in specs/INDEX.md must be one the resolver can classify (row H7b).
#
# WHY THIS EXISTS
# ---------------
# scripts/spec_active.py's id grammar drifted away from the register's own naming convention and nothing
# noticed for 18 days. 69 of 114 rows classified "unparseable", both PreToolUse guards answer that with
# deny, and 56 of those rows shipped anyway — through Bash, which was not gated. The drift was invisible
# because nothing ever compared the grammar to the register.
#
# That comparison is one loop, and it is this file. A grammar that narrows, or a register row that adopts a
# shape the grammar has not learned, is now a red gate at the next stop instead of a silent denial.
#
# It also PRINTS THE HISTOGRAM every run, pass or fail. The spec's acceptance criteria claim "zero
# unparseable, exactly five checkpoints"; a gate that only says "ok" turns those numbers back into claims.
#
# Usage:  bash scripts/validate-register-ids.sh
# Env:    REGISTER  override the register path (for scripts/test-register-ids.sh only — the production
#                   caller, scripts/run-gates.sh, passes nothing, so the gate that gates gates the real file)
#
# Exit: 0 every id classified · 1 at least one malformed id (each is named, with its line) ·
#       2 the register could not be read — a DIFFERENT fact from "the register is bad", and the two must
#         not share an exit code (the H6y/H6s lesson, and the defect this row's own guards had)
#
# Covers: SC-1428 SC-1429 SC-1430 SC-1443

set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REGISTER_PATH="${REGISTER:-$REPO_ROOT/specs/INDEX.md}"

if [ ! -f "$REGISTER_PATH" ]; then
  echo "validate-register-ids: register not found: $REGISTER_PATH" >&2
  exit 2
fi

REGISTER_PATH="$REGISTER_PATH" HOOK_DIR="$SCRIPT_DIR" python3 <<'PY'
import os
import sys

sys.path.insert(0, os.environ["HOOK_DIR"])
try:
    from spec_active import ROW_RE, classify_id, _kind_for
except Exception as exc:                                    # noqa: BLE001
    print("validate-register-ids: cannot import the resolver: %s" % exc, file=sys.stderr)
    sys.exit(2)

path = os.environ["REGISTER_PATH"]
try:
    with open(path, "r", encoding="utf-8", errors="ignore") as fh:
        lines = fh.readlines()
except OSError as exc:
    print("validate-register-ids: cannot read %s: %s" % (path, exc), file=sys.stderr)
    sys.exit(2)

counts = {"spec": 0, "checkpoint": 0, "unparseable": 0}
bad = []
rows = 0

for lineno, line in enumerate(lines, 1):
    m = ROW_RE.match(line.rstrip())
    if not m:
        continue
    rows += 1
    _status, raw_id, _slug, track_field = m.groups()
    parts = raw_id.strip().split()
    token = parts[0] if parts else ""
    ident, shape = classify_id(token)
    kind = _kind_for(shape, track_field)
    counts[kind] = counts.get(kind, 0) + 1
    if kind == "unparseable":
        bad.append((lineno, token))

# A register with no rows at all is not "clean" — it is a register this gate cannot speak about, which is
# the same class of answer as an unreadable file.
if rows == 0:
    print("validate-register-ids: %s parsed, but it holds ZERO register rows." % path, file=sys.stderr)
    print("  Nothing was checked. That is not a pass.", file=sys.stderr)
    sys.exit(2)

print("Register: %s" % path)
print("Rows: %d  |  spec: %d  checkpoint: %d  unparseable: %d"
      % (rows, counts["spec"], counts["checkpoint"], counts["unparseable"]))

if not bad:
    print("PASS — every row id is classifiable.")
    sys.exit(0)

print("", file=sys.stderr)
print("FAIL — %d row id(s) the resolver cannot classify:" % len(bad), file=sys.stderr)
for lineno, token in bad:
    print("  %s:%d   id token: %r" % (path, lineno, token), file=sys.stderr)
print("", file=sys.stderr)
print("Both PreToolUse pipeline guards answer an unclassifiable ACTIVE row with deny, and the deny is", file=sys.stderr)
print("correct — without a usable id there is no way to tell whether the row owes artifacts. So this is", file=sys.stderr)
print("not a cosmetic complaint: any of the rows above becomes a total edit block the moment it goes", file=sys.stderr)
print("active.", file=sys.stderr)
print("", file=sys.stderr)
print("The grammar is in scripts/spec_active.py:", file=sys.stderr)
print("  NUMERIC_ID_RE  ^[0-9]+[a-z]*$              007, 007m, 007ab", file=sys.stderr)
print("  ALPHA_ID_RE    ^[A-Za-z]+[0-9]+[A-Za-z0-9]*$   H1, H6a, H6s2, F2b", file=sys.stderr)
print("", file=sys.stderr)
print("Fix the row, or — if the token IS the house convention and the grammar is what is behind —", file=sys.stderr)
print("widen the grammar and add the case to scripts/test-register-ids.sh so it cannot narrow again.", file=sys.stderr)
sys.exit(1)
PY

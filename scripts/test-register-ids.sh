#!/usr/bin/env bash
# Self-test for scripts/validate-register-ids.sh and the id grammar it gates (row H7b).
#
# WHY THIS EXISTS. A gate whose failing arm has never been observed is not known to work — spec 007f's
# rule, and this row is the proof of it: the id grammar was wrong for 18 days while every artifact around
# it was green, because nothing ever ran the comparison. Shipping the comparison without an executable
# check ON the comparison would be the same mistake wearing a shell script.
#
# WHAT IT PINS
#   * the three-state exit contract — 0 clean, 1 malformed id, 2 the register could not be read — and
#     specifically that 2 is DISTINCT from 1. "exit != 0" would conflate "this register is bad" with
#     "I could not look", which is the exact conflation that cost this row 56 register rows.
#   * that the grammar accepts the house convention, INCLUDING H6s2 (letters-digits-letter-digit). The
#     first fix attempt for this row was `[a-z]?`, which fells H6s2 — the same defect one carve later.
#   * that H6s2 comes back WHOLE. "H6s" is another real register row, so a truncating match would resolve
#     to a different spec. Same property 007ab pinned on the numeric side.
#   * that kind comes from the TRACK FIELD, not the id shape — a letter-led id on a `full`/`spec-only`
#     track is a spec that owes its artifacts, not an exempt checkpoint. 14 of 19 rows were exempt on the
#     strength of a letter before this row.
#   * that a register with zero rows is not a pass.
#
# Scenario map: SC-1428, SC-1429, SC-1430, SC-1443, SC-1445 (specs/SCENARIOS.md, row H7b).
#
# Exit: 0 all expectations met · 1 an expectation failed · 2 the harness itself broke, OR a precondition
#       could not be met (no register to narrow the grammar against) — SC-1683.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$ROOT/scripts/validate-register-ids.sh"
[ -f "$GATE" ] || { echo "HARNESS ERROR: gate not found: $GATE" >&2; exit 2; }

WORK=$(mktemp -d 2>/dev/null) || { echo "HARNESS ERROR: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "  ok    $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL  $1"; }

check_rc() {
  local label="$1" expected="$2" actual="$3"
  if [ "$actual" -eq "$expected" ]; then ok "$label (rc=$actual)"; else bad "$label — expected rc=$expected, got rc=$actual"; fi
}

check_says() {
  local label="$1" needle="$2" text="$3"
  case "$text" in *"$needle"*) ok "$label (names \"$needle\")" ;; *) bad "$label — output never names \"$needle\"" ;; esac
}

make_register() {
  local name="$1"; shift
  local f="$WORK/$name.md"
  { echo "# Spec register"; echo; echo "## Specs"; echo; printf '%s\n' "$@"; } > "$f"
  printf '%s' "$f"
}

echo "== the grammar itself (unit level) =="
GRAMMAR=$(HOOK_DIR="$ROOT/scripts" python3 <<'PY' 2>&1
import os, sys
sys.path.insert(0, os.environ["HOOK_DIR"])
from spec_active import classify_id, _kind_for
cases = [
    # token,        expected ident, expected shape
    ("007",         "007",   "numeric"),
    ("007m",        "007m",  "numeric"),
    ("007ab",       "007ab", "numeric"),
    ("**364",       "364",   "numeric"),
    ("H1",          "H1",    "alpha"),
    ("H6a",         "H6a",   "alpha"),
    ("H6s2",        "H6s2",  "alpha"),      # letters-digits-letter-digit: the case `[a-z]?` would miss
    ("**H7b**",     "H7b",   "alpha"),
    ("F2b",         "F2b",   "alpha"),
    ("7-x",         "7-x",   "malformed"),  # a character outside [A-Za-z0-9]
    ("H",           "H",     "malformed"),  # letters, no digit
    ("checkpoint",  "checkpoint", "malformed"),
]
bad = 0
for token, want_id, want_shape in cases:
    got_id, got_shape = classify_id(token)
    if (got_id, got_shape) != (want_id, want_shape):
        print("SHAPE-MISMATCH %r -> %r/%s, wanted %r/%s" % (token, got_id, got_shape, want_id, want_shape))
        bad += 1

# H6s2 must never come back as H6s — that is a different real register row.
ident, _ = classify_id("H6s2")
if ident != "H6s2":
    print("TRUNCATION H6s2 -> %r" % ident); bad += 1

# kind comes from the TRACK FIELD.
kind_cases = [
    ("alpha", "checkpoint",           "checkpoint"),
    ("alpha", "full track",           "spec"),
    ("alpha", "spec-only",            "spec"),
    ("alpha", "full track [hardened]", "spec"),
    ("numeric", "checkpoint",         "checkpoint"),
    ("numeric", "light track",        "spec"),
    ("malformed", "checkpoint",       "unparseable"),   # no id => no exemption, whatever the track says
    ("malformed", "full track",       "unparseable"),
]
for shape, track, want in kind_cases:
    got = _kind_for(shape, track)
    if got != want:
        print("KIND-MISMATCH %s + %r -> %s, wanted %s" % (shape, track, got, want)); bad += 1
print("GRAMMAR-OK" if bad == 0 else "GRAMMAR-BAD %d" % bad)
PY
)
case "$GRAMMAR" in
  *GRAMMAR-OK*) ok "id grammar + kind derivation (20 cases)" ;;
  *) bad "id grammar / kind derivation:"; printf '%s\n' "$GRAMMAR" | sed 's/^/        /' ;;
esac

echo "== the gate, green arm =="
REG=$(make_register clean \
  '- [x] 007 — preview — full track — done' \
  '- [x] 007ab — later-suffix — full track — done' \
  '- [x] H1 — integration-hardening — checkpoint — regression sweep' \
  '- [/] H6s2 — carved-from-a-carve — spec-only — in progress' \
  '- [ ] H7b — next — spec-only — later')
OUT=$(REGISTER="$REG" bash "$GATE" 2>&1); RC=$?
check_rc  "clean register" 0 "$RC"
check_says "clean register reports the histogram" "unparseable: 0" "$OUT"
check_says "clean register counts the ONE checkpoint-track row" "checkpoint: 1" "$OUT"

echo "== the gate, red arm (this is the arm that had never been observed) =="
REG=$(make_register broken \
  '- [x] 007 — preview — full track — done' \
  '- [/] 7-x — malformed-id — spec-only — in progress' \
  '- [ ] H — no-digit — full track — later')
OUT=$(REGISTER="$REG" bash "$GATE" 2>&1); RC=$?
check_rc   "malformed ids" 1 "$RC"
check_says "names the first offender"  "7-x" "$OUT"
check_says "names the second offender" "'H'" "$OUT"
check_says "names the line number"     ":6"  "$OUT"
check_says "points at the grammar"     "spec_active.py" "$OUT"

echo "== the gate, cannot-look arm (must NOT share an exit code with the red arm) =="
OUT=$(REGISTER="$WORK/does-not-exist.md" bash "$GATE" 2>&1); RC=$?
check_rc "missing register" 2 "$RC"

REG=$(make_register norows)   # header only, zero rows
OUT=$(REGISTER="$REG" bash "$GATE" 2>&1); RC=$?
check_rc   "register with zero rows is not a pass" 2 "$RC"
check_says "and says so"     "ZERO register rows" "$OUT"

echo "== SC-1445: the directory is resolved for every well-formed id, not only for kind==spec =="
DIRCHECK=$(HOOK_DIR="$ROOT/scripts" WORKDIR="$WORK" python3 <<'DIRPY' 2>&1
import os, sys
sys.path.insert(0, os.environ["HOOK_DIR"])
from spec_active import resolve

work = os.environ["WORKDIR"]
root = os.path.join(work, "dircheck")
os.makedirs(os.path.join(root, "specs", "H1-integration-hardening"), exist_ok=True)
with open(os.path.join(root, "specs", "INDEX.md"), "w", encoding="utf-8") as fh:
    fh.write("# Spec register\n\n## Specs\n\n")
    fh.write("- [/] H1 - integration-hardening - checkpoint - full-system regression\n".replace(" - ", " — "))

info = resolve(root)
bad = 0
# The exemption still holds...
if info["kind"] != "checkpoint":
    print("KIND %r, wanted checkpoint" % info["kind"]); bad += 1
# ...and the directory is resolved anyway, so .specify/feature.json and
# check-prerequisites.sh can answer for this row. Before H7b the glob ran only
# under `if kind == "spec"`, which is why check-prerequisites.sh failed outright
# on H7b itself.
if info["dir"] != os.path.join("specs", "H1-integration-hardening"):
    print("DIR %r, wanted specs/H1-integration-hardening" % info["dir"]); bad += 1
if not info["found"]:
    print("FOUND false for a directory that exists"); bad += 1
if info["slug"] != "integration-hardening":
    print("SLUG %r" % info["slug"]); bad += 1
# A malformed id has no usable glob and must stay empty rather than guess.
root2 = os.path.join(work, "dircheck2")
os.makedirs(os.path.join(root2, "specs"), exist_ok=True)
with open(os.path.join(root2, "specs", "INDEX.md"), "w", encoding="utf-8") as fh:
    fh.write("# Spec register\n\n## Specs\n\n- [/] 7-x - broken - spec-only - x\n".replace(" - ", " — "))
info2 = resolve(root2)
if info2["kind"] != "unparseable" or info2["dir"] is not None:
    print("MALFORMED %r / %r" % (info2["kind"], info2["dir"])); bad += 1
print("DIR-OK" if bad == 0 else "DIR-BAD %d" % bad)
DIRPY
)
case "$DIRCHECK" in
  *DIR-OK*) ok "a checkpoint-track row resolves its directory, a malformed id resolves nothing" ;;
  *) bad "directory resolution:"; printf '%s\n' "$DIRCHECK" | sed 's/^/        /' ;;
esac

echo "== falsification: a narrowed grammar must turn this gate red =="
# The point of the whole row. If narrowing the grammar back to its pre-H7b shape leaves this gate green,
# the gate is decorative. Run the classifier with the OLD regex against the REAL register.
#
# PRECONDITION, and it is a THIRD state rather than a failure (row H7t). This block needs a real register
# with real rows; a synthetic one would only re-prove SC-1430, which is already asserted above. Repos that
# legitimately have none — the template itself, a project before /project-wizard writes its register —
# used to reach the `bad` branch and report "this gate cannot detect the defect it was built for", which
# is a false accusation against a healthy gate and precisely the wrong-diagnosis failure the H7b row spent
# 18 days inside. Missing precondition is not PASS and it is not FAIL: it is "I cannot tell you", and this
# harness's own header already promises those are different facts (exit 2).
PRECOND_UNMET=0
if [ ! -f "$ROOT/specs/INDEX.md" ]; then
  echo "  ----  no register at $ROOT/specs/INDEX.md — the falsification needs real rows, so it did not run"
  PRECOND_UNMET=1
else
NARROW=$(HOOK_DIR="$ROOT/scripts" REG="$ROOT/specs/INDEX.md" python3 <<'PY' 2>&1
import os, re, sys
sys.path.insert(0, os.environ["HOOK_DIR"])
import spec_active
spec_active.ALPHA_ID_RE = re.compile(r"^\**\s*([A-Za-z]+[0-9]+)\**\s*$")   # the pre-H7b shape
n = 0
for line in open(os.environ["REG"], encoding="utf-8", errors="ignore"):
    m = spec_active.ROW_RE.match(line.rstrip())
    if not m:
        continue
    _s, raw, _g, track = m.groups()
    tok = (raw.strip().split() or [""])[0]
    ident, shape = spec_active.classify_id(tok)
    if spec_active._kind_for(shape, track) == "unparseable":
        n += 1
print("NARROWED-UNPARSEABLE %d" % n)
PY
)
COUNT=$(printf '%s' "$NARROW" | sed -n 's/.*NARROWED-UNPARSEABLE \([0-9]*\).*/\1/p')
if [ -n "$COUNT" ] && [ "$COUNT" -gt 0 ]; then
  ok "the pre-H7b grammar still fells $COUNT rows of the real register — the gate has something to catch"
else
  bad "narrowing the grammar changed nothing — this gate cannot detect the defect it was built for"
fi
fi

echo
if [ "$fail" -ne 0 ]; then
  echo "FAIL — $fail of $((pass + fail)) expectations missed"
  exit 1
fi
if [ "$PRECOND_UNMET" -ne 0 ]; then
  echo "INCONCLUSIVE — $pass expectations met, but the falsification could not run (no register in this repo)."
  echo "The grammar's own cases passed; what is unproven here is that the gate would catch a narrowed"
  echo "grammar, because that check needs a real register to narrow against. Not a pass."
  exit 2
fi
echo "PASS — $pass/$pass expectations met"
exit 0

# 048 — sc-id-space-is-three-digits-and-full

Track: spec-only. No entity, no state machine, five files touched. No hardening trigger fires.

Evidence: ighweld-2026 F065 (961 of 999 ids used), F057, F078 (spec 112 minted four-digit ids).
Diagnosis in `specs/INDEX.pending.md`.

## The defect

`.claude/rules/scenarios.md` says an SC-id is `SC-NNN`, "three digits". ighweld has used 961 of the
999, and its free ids are low gaps, which are the worst ones to reuse because an old test may still
name them. It already mints `SC-1000+`, so the project runs four-digit ids against a rule that says
three.

Row 060 made `next-scenario-id.sh` grow past `SC-999`, and `scenarios.md` mentions that in one
sentence. The rest of the rule and two tools still assume three or four digits:

- The SC-id bullet in `scenarios.md` still says "three digits".
- The single-file locate recipe in `scenarios.md` greps `SC-0[0-9]{2}`, which finds only ids below
  100.
- `validate-fixture-map-ids.sh` counts an id only if it has 3 or 4 digits (five places). A five-digit
  id is invisible to R1, R2 and R3.

**The namespace interaction.** Row 007 separated the map's permanent handles from spec-kit's Success
Criteria by digit width: a reference with fewer digits than the map's narrowest id belongs to the
other sequence. Four-digit map ids do not move that line, because the gate measures the NARROWEST id
and a grown map still starts at three digits. But nothing tests the width rule at all (no case in
`test-validate-scenario-traceability.sh`), so a change that measured the widest or most common width
would pass the suite. On a grown map it would file a three-digit citation of a missing scenario as
a criterion, so a real dangling reference would stop failing the gate.

## Decision

1. **The id is three digits minimum, not exactly.** `SC-NNN` is zero-padded to three and grows past
   `SC-999` to `SC-1000`, `SC-1001` and so on. It never wraps, never takes a low gap, and existing ids
   are never re-padded to the new width. A re-pad would rename every permanent handle and every test
   that cites one.
2. **The namespace line stays where it is, and gets a test.** The out-of-range split keeps using the
   map's narrowest width plus its floor. `scenarios.md` names both rules and says why growth does
   not move them. A new traceability case pins the width rule on a mixed-width map, and two
   sabotage arms prove the case bites.
3. **No upper bound in the fixture gate.** `validate-fixture-map-ids.sh` treats any id with three or
   more digits as an id. The lower bound is the one that keeps criteria and shellcheck codes out, and
   it stays.

## Functional requirements

- **FR-01** `scenarios.md` SC-id bullet: at least three digits, zero-padded to three, growing past
  999; never re-padded, never a reused gap.
- **FR-02** `scenarios.md` locate recipe matches ids of any width ≥ 3.
- **FR-03** `scenarios.md` namespace paragraph names both discriminators (floor and narrowest width)
  and states that a grown map keeps a three-digit narrowest width.
- **FR-04** `validate-fixture-map-ids.sh` accepts ids of three or more digits in the population
  check, the heredoc-row check, R1, R2 and R3.
- **FR-05** `test-validate-scenario-traceability.sh` case48: on a map holding three- and four-digit
  rows, a four-digit reference covers its row, a three-digit reference covers its row, a two-digit
  criterion is out-of-range, and a missing three-digit id above the floor is dangling.
- **FR-06** Sabotage arms: width measured from the widest id turns case48b red; the width rule
  removed turns case48a red.
- **FR-07** `test-fixture-map-ids.sh`: an owned five-digit id in a fixture row is reported (R1), and a
  five-digit id shown as map syntax in a comment is reported (R3). C11 stays green.

## Non-goals

- Renumbering ighweld's map or reusing its gaps.
- A separate prefix for spec-kit criteria. `scenarios.md` already tells specs to letter their
  criteria. Changing spec-kit's template is upstream work.
- Rows 061 and 007 behaviour beyond pinning the width rule.

## Clarifications

### Session 2026-09-30

- Q: Should a map re-pad its old ids once it passes 999, so every id has four digits? → A: No. An id
  is a permanent handle cited by tests, and a re-pad renames all of them. Mixed width is the
  intended state of a grown map.
- Q: Keep an upper bound in the fixture gate (say, six digits)? → A: No. The upper bound guarded
  nothing; the lower bound and the hyphen are what keep shellcheck codes and criteria out. C11 already
  shows that a wider token is compared by its whole number, not truncated.
- Q: Does a map that starts at four digits (never had three-digit ids) need special handling? → A: No.
  Its narrowest width is four, so a three-digit reference is out-of-range. The floor would also catch
  it. case27 already covers the floor side.

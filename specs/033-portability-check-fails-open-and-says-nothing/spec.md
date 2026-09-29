# 033 — portability check fails open and says nothing

Track: spec-only. No entity, no state machine, no new surface. Not hardened: one section of one
existing script, plus its self-test and two fixtures that must now carry the stubs.

Evidence: fundit finding F002 (2026-09-04, from spec 016a), `~/repos/fundit/specs/FINDINGS.md`.
Reported to this register as one of rows 032/033/034.

## Problem as filed

fundit commit 57b6ea1 synced the portability call site in `project-maintenance.sh` without
`scripts/validate-portability.sh` and `scripts/portability_audit.py`. Section 6c is guarded by
`[ -f ] && [ -f ]` with no `else`, so the pass skipped the check and still printed
`project-maintenance: clean`.

## What was measured (2026-09-29)

A git fixture holding only a passing `project-freshness.sh` stub, run against HEAD:

```
project-maintenance: clean — no secrets, no CVEs, no register drift, no context bloat.
[note] maintenance ledger: python3 or scripts/maintenance_ledger.py missing — this pass ran unmeasured.
rc=0
```

Nothing says portability did not run. Section 6c has three silent paths:

| Path | Today |
|---|---|
| both scripts missing (the fundit case) | silent, `clean` |
| one of the two missing | silent, `clean` (validate-portability.sh would exit 2 on its own, but the guard never calls it) |
| both present, run exits neither 0 nor 1 (exit 2 "could not run", 127 no python3) | silent, `clean` |

Both scripts are CORE (`template-autosync.sh` lists them, and no CORE file declares them
`optional-project-script`). Their absence is a sync defect, which is what `[SETUP]` already means
for `project-freshness.sh` (section 1).

## Decision

- A missing portability script is a `[SETUP]` finding that names each missing file and says
  `/project-update` restores it. It counts, so the pass is red. A note would let the pass read
  `clean` again, and that is the defect.
- A run that exits anything other than 0 or 1 is a `[PORTABILITY]` finding with its exit code and
  the first lines of its output. This matches section 6b and the SIGPIPE gate (C24): a check that
  could not run is never a clean read.
- Exit 0 stays silent. Exit 1 keeps today's wording.

## Functional requirements

- **FR-01** Both scripts missing → `[SETUP]` finding naming both, pass exit 1.
- **FR-02** Exactly one missing → `[SETUP]` finding naming only that one, pass exit 1.
- **FR-03** Both present, run exits ≥ 2 → `[PORTABILITY] ... could not run (exit N)` with the
  run's first lines, pass exit 1.
- **FR-04** Both present, run exits 0 → no portability line, pass unaffected.
- **FR-05** Both present, run exits 1 → today's `[PORTABILITY] construct(s) ...` finding, unchanged.
- **FR-06** Fixtures in other self-tests that run `project-maintenance.sh` and assert a finding count
  or a clean exit carry passing portability stubs, so they test their own section, not this one.

## Scenarios

- SC-033-01 no portability scripts → `[SETUP]` names both, rc 1.
- SC-033-02 only `validate-portability.sh` → `[SETUP]` names `portability_audit.py` only.
- SC-033-03 only `portability_audit.py` → `[SETUP]` names `validate-portability.sh` only.
- SC-033-04 stub exits 2 → `could not run (exit 2)` plus the stub's reason, rc 1.
- SC-033-05 stub exits 0 → no `PORTABILITY` and no `portability` in `[SETUP]`, rc 0.
- SC-033-06 stub exits 1 with a hit → `[PORTABILITY] construct(s)` with the hit line, rc 1.

## Out of scope

- The other `[ -f ]`-guarded sections (6b carve shape, 2c SIGPIPE, census). 6b also requires
  `specs/INDEX.md`, which a project legitimately may not have. The census scripts are declared
  optional. Recorded as a finding for the next review, not fixed here.
- Rows 032 and 034.

## Clarifications

### Session 2026-09-29

- Q: Finding or note? → A: Finding (`[SETUP]`). The scripts are CORE; section 1 already treats a
  missing CORE check as `[SETUP]`, and a note leaves the verdict `clean`.
- Q: Should python3 missing get its own message? → A: No. It surfaces as `could not run (exit 127)`
  with the shell's own line, which names python3. One path for every non-0/1 exit.

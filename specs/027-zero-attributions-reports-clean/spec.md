# 027 — zero attributions reports clean

Track: spec-only. No entity, no state machine, no new surface. Not hardened: one verdict and one
exit code in a report script, plus the one caller that branches on it.

Evidence: agentcrm 2026-09-04 (`specs/INDEX.pending.md` § 027).

## Problem as filed

`scripts/carve_audit.py` prints `carve shape: clean — 0 attributed row(s)` and exits 0 when no row
carries `carved by` / `found by` / `opened by` / `from`. With `parent` empty, `over` and `deep` are
empty by construction, so the word "clean" there means only that nothing was measured.
`.claude/rules/carve-budget.md` §4b already says the zero is the finding. agentcrm held a depth-3
chain and a six-carve row on the day the audit said clean.

## What was measured (2026-09-29)

The audit was run over all 30 registers under `~/repos`:

- 18 of 30 print `clean — 0 attributed row(s)`. Their sizes run from 4 rows to 119 rows
  (msroute: 119 rows, 103 ticked). The template repo itself says it about its own 75 rows.
- 3 more print `clean` with 1 attributed row out of 35–53. That is thin, but it is a measurement,
  and this spec leaves it alone.
- The row count alone does not tell a young register from an unattributed one. A ticked count does.
  §5 already refuses to read a carve ratio below 10 ticked rows, for the same reason: below that
  there is too little history for the absence of a signal to mean anything. Of the 18, only
  ighweld-web-license (3 ticked) is under 10.

## Decision

Three verdicts instead of one:

| Attributed | Ticked | Verdict | Exit |
|---|---|---|---|
| ≥ 1, none over budget, none past depth 2 | any | `clean` | 0 |
| ≥ 1, over budget or past depth 2 | any | `[CARVE BUDGET]` / `[CARVE DEPTH]` | 1 |
| 0 | ≥ 10 | `unmeasurable` | 3 |
| 0 | < 10 | `too young to measure` | 0 |

Exit 3 follows the convention in `register-convergence.sh` of this repo, where 3 means "not enough to
tell". It stays out of 1, which `project-maintenance.sh` reads as "budget exceeded", and out of 4,
which means the audit could not run at all.

## Functional requirements

- **FR-01** 0 attributed rows and ≥ 10 ticked rows: print
  `carve shape: unmeasurable — 0 attributed row(s) of N (T ticked); ...` and exit 3.
- **FR-02** 0 attributed rows and < 10 ticked rows: print a line that says so. It must not contain
  the word `clean`. Exit 0.
- **FR-03** `clean` is printed only when at least one attribution resolved and nothing is over budget or past depth 2.
- **FR-04** Unresolved attributions are still listed. They are also counted in the unmeasurable
  line, because every citation failing to resolve looks the same as having none.
- **FR-05** `project-maintenance.sh` reports exit 3 as its own `[CARVE SHAPE]` finding. The text
  names the missing attributions; it does not claim the budget was exceeded. Any exit other than
  0/1/3 is reported as "could not run", never dropped.
- **FR-06** `register-convergence.sh --help` documents the `--carves` exit codes, and
  `carve-budget.md` §4b names the new verdict.
- **FR-07** `scripts/test-register-convergence.sh` pins all four rows of the table, plus the
  unresolved-only case.

## Acceptance

- `bash scripts/test-register-convergence.sh` passes, and each new arm fails on the old
  `carve_audit.py`.
- Run over the template's own register (75 rows, 34 ticked, 0 attributed), `--carves` exits 3.

## Clarifications

### Session 2026-09-29

- Q: Threshold by rows or ticked rows? → A: Ticked, ≥ 10 (reuses §5's floor). Rows do not work:
  wizard registers are planned up front and can have 20+ rows before the first carve.
- Q: Exit 1 or a new code? → A: New code 3. Exit 1 means "the budget was exceeded" to the only
  caller that branches on it, and that claim would be false here.
- Q: Should registers with 1–2 attributions count as thin? → A: No. That is a heuristic this spec
  has no measurement for. Recorded as a finding instead.

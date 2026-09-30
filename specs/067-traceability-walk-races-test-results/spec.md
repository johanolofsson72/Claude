# 067 — traceability-walk-races-test-results

Track: spec-only. No entity, no state machine, no new surface. Touches
`scripts/validate-scenario-traceability.sh` and its harness
`scripts/test-validate-scenario-traceability.sh`. No hardening trigger.

Evidence: fundit F116 (2026-09-10). Diagnosis in `specs/INDEX.pending.md`. Sibling of 044.

## The defect

Three runs on identical input gave 141, 0 and 0 of 148 while a Playwright suite rewrote
`test-results/`. 044 made the zero case refuse. The partial case still reports: the reference walk
collects `find` and `grep` errors in `scan.err` and prints them only when the scan found no id at
all. A walk that lost a directory mid-way (vanished, unreadable) and still found *some* ids prints
`coverage: 141 of 148` and exits 1, which reads as seven real gaps. Reproduced on HEAD with a
`chmod 000` subdirectory: `coverage: 1 of 2`, exit 1, no word about the error.

`test-results/` itself is already pruned by name (since 6bf2e52). Playwright's other output
directories are not.

## Requirements

- **FR-01** A reference walk that reported any error (from `find` or from `grep`) refuses with
  exit 4 and prints no `coverage:` line. A partial read is not a coverage result.
- **FR-02** The refusal names the error count, the first 10 error lines, and the files read per
  root, and tells the reader to rerun when nothing is writing under the roots.
- **FR-03** The 044 zero-ids refusal is unchanged for an error-free empty scan.
- **FR-04** Playwright's `blob-report/` and the common report directories `allure-results/` and
  `.nyc_output/` are pruned like `test-results/`: ids inside them are neither coverage nor dangling.
- **FR-05** An error-free walk behaves exactly as before (every existing case stays green).

## Acceptance

- AC1 an unreadable subdirectory under a root → exit 4, no `coverage:` line, the error quoted.
- AC2 an unreadable file under a root → exit 4, same.
- AC3 the refusal lists `tests: N file(s)`.
- AC4 an id cited only inside `tests/blob-report/`, `tests/allure-results/` or `tests/.nyc_output/`
  is not reported dangling, and does not cover a row.
- AC5 sabotage: removing the new guard turns AC1/AC2 red; removing the new prune names turns AC4 red.

## Clarifications

### Session 2026-09-30

- Q: Exit 4 or a new exit code? → A: 4. It already means "the references could not be read"
  (missing root, zero-ids scan); a partial walk is the same fact. A new code would need every
  caller that maps exit codes to learn it.
- Q: Tolerate errors for files that vanished (they no longer exist, so they cite nothing)? → A: No.
  A tree changing under the walk means the result describes no single moment; the diagnosis asks
  for "unreadable, not zero". Refuse and ask for a rerun.
- Q: Prune `coverage/` too? → A: No. It is a plausible name for a real test folder, and no sighting
  involves it. Only names that are unambiguously tool output.

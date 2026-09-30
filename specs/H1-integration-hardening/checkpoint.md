# H1 — integration-hardening checkpoint (template repo)

First checkpoint on the template register. It covers the rows ticked since 2026-09-03. The
template ships to six projects, so a seam that breaks here breaks in all of them.

## 1. Full-system regression

All 57 `scripts/test-*.sh`, run one after another (about 10 minutes).

- First run: 55/57. Both reds came from one file, `scripts/test-validate-rule-citations.sh`,
  which spec 041 added:
  - It ran `template-autosync.sh` directly, which the sandbox gate from specs 010/011 forbids.
    It now queries through `drive_sync_readonly`.
  - Its printf fixtures held literal rule paths, so the validator it tests flagged its own test
    file (F036). The planted citations are now spelled with a split extension; the validator
    was not widened.
- After the fix: 57/57.
- `test-validate-scenario-traceability.sh` passed 45/45 in 151 s, with every sabotage arm
  surgical. That contradicts row 064 and F011 (F046).

## 2. Cross-cutting security sweep

- `project-freshness.sh`: trufflehog found no verified secrets. The key-shape scan flagged the
  scanner's own PuTTY fixture (F034). `.secret-shapes-allow` now exempts the scanner, its test
  and spec 023, with a reason for each. Result: green. npm/.NET/OSV not applicable.
- `security-scanner` adversarial pass: 8 confirmed findings, a fail-open matrix and a
  speculative list.
  - Fixed in place: `sync-prompt.md` fetched two scripts with `curl -sL`, so a 404 page could
    be written as the script. Now `-fsSL`.
  - Duplicate: the `tlc-cleanup.sh` pkill finding is row 069.
  - Recorded as F037–F045. The largest is F037: autosync syncs unpinned `main`, and a dirty
    local clone, into six projects and pushes.

## 3. Scenario-map reconciliation

Not applicable. The template has no language marker and no `specs/SCENARIOS.md`, and the map
hook is silent on it by design.

## 4. Mutation spot-check

Stryker has no bash target. Instead, a sampled operator-mutation pass (`-eq/-ne`, `-z/-n`,
`&&/||`, `exit`/`return` codes, `-f`) ran on the three most-changed modules since 2026-09-03,
in a detached worktree, with each module's tests.

| Module | Commits | Killed | Finding |
|---|---|---|---|
| `template-autosync.sh` | 23 | 2/12 (16%), across all 16 suites that run it | F050 (row proposal) |
| `project-maintenance.sh` | 16 | 7/12 (58%) | F049 |
| `project-freshness.sh` | 5 | 5/10 (50%), 2 echo-text mutants excluded | F048 |

Two harness traps were caught before any number was reported:

- Under zsh, `$T` did not word-split, so every test "failed" with exit 127 and every mutant
  looked killed. This is the row 037 bug.
- `test-drive-sync.sh` is red in a worktree outside `$HOME`, because the helper judges the
  sandbox by location.

## Carve budget

Freeze is on, so no rows were added. Findings: F037–F049 recorded, F034 and F036 fixed and
resolved.

# H8 — integration-hardening checkpoint (template repo)

This is the eighth checkpoint. It covers the specs ticked since H7: 105, 106, 107, 108 and 109.
`checkpoint-cadence.sh` reported `since=H7 count=5 due=1`. Everything ran in one session on
2026-11-18.

## 1. Full-system regression

`project-maintenance.sh --full --suite` ran all 97 `scripts/test-*.sh` one at a time under bash
with the 900 s cap. All of them passed with no timeouts, and the suite was stamped. The pass
exited 1 on two things:

- F225 is unchanged: `install-guard-notice-mod.sh` and `test-guard-notice-mod.sh` lack the
  executable bit, and only the developer can fix that.
- The mutation module gate failed (section 4).

After the in-place fixes in section 2, the 15 tests that cover the changed files ran again and
passed: `test-run-mutation-gate.sh`, every `test-template-autosync-*.sh`, `test-drive-sync.sh`,
`test-template-clone-refresh.sh`, `test-sync-count-honesty.sh`, `test-core-machinery-guard.sh`,
`test-guard-notice-mod.sh` and `test-validate-hooks.sh`.

## 2. Cross-cutting security sweep

`project-freshness.sh` came back clean: no verified credentials and no committed key material. OSV
found no lockfiles. The `security-scanner` agent read the focus files changed between 79ca070 and
512cb74. It was scoped to defensive gaps, told not to write bypass recipes, and told to skip
anything already recorded up to F285. It returned ten items. I checked 1, 2, 3, 4, 7 and 8
against the source myself.

Three items were fixed in place, because each fix was one line and smaller than recording it:

- `template-autosync.sh:1452`: the tarball `mktemp -d` had no failure check, unlike its two
  siblings. On failure the download target would have become `/template.tar.gz`. It now returns 1.
- `run-mutation-gate.sh:492`: the stale-run sweep tested the run marker with `-f`. A concurrent run
  could see the marker after `mkdir` but before the pid was written. `kill -0 ""` then fails, and
  the sweep would delete a live run's directory. It now tests `-s`.
- `run-mutation-gate.sh:611`: the sandbox `env -i` list now sets `PYTHONDONTWRITEBYTECODE=1`, so a
  Python mutant and its restored original cannot share cached bytecode.

Recorded as F286–F292:

- F286 (verified): the crash-repair exemption in `settings-edit-guard-hook.sh:216` and
  `trust-anchor-guard-hook.sh:752` matches a `file_path` key anywhere in the raw tool input and
  never checks `tool_name`. A tool-name regex on raw text could be fooled the same way, so the fix
  needs a parsed check. That makes it bigger than an in-place fix.
- F287 (verified): `guard_field` in `guard-lib.sh` returns different results under jq and python3
  for a non-object path and for JSON `false`.
- F288 (suspected): python3 stdio uses the locale encoding, which on Git Bash can break UTF-8
  paths.
- F289 (verified): `hook_audit.py` never reads `disableAllHooks` and never looks at what follows
  the script operand.
- F290 (verified): `install-guard-notice-mod.sh` checks only the leaf staged file for a symlink,
  and it cuts the pin digest to 16 hex characters.
- F291 (suspected): a mutation worker's reused worktree carries untracked test state from one
  mutant to the next.
- F292 (verified): `project-maintenance.sh` leaks three temp files on timeout, on a signal and on
  early exit.

That accounts for all ten scanner items: three fixed in place, seven recorded.

One more came from this session rather than the scanner. The settings guard refused a read-only
`find . -name '*.json' -newer …` with no `-delete` or `-exec`. That is the false-positive class 108
covered, recorded as F295.

## 3. Scenario-map reconciliation

Not applicable, as at H1–H7: the template has no language marker and no `specs/SCENARIOS.md`.

## 4. Mutation spot-check

The suite pass's `--full` run used the default table with today's seed (20261118) and 12 mutants
per module. The headline was 83.3%, above the runner's break, but the per-module gate failed:

| Module | Killed |
|---|---|
| `bash_write_targets.py` | 6/12 |
| `shell_glob.py` | 6/12 |
| `sensitive_paths.py` | 8/12 |
| `validate-scenario-traceability.sh` | 8/12 |
| `settings_guard.py` | 9/12 |

The survivors are recorded as F293 (bash) and F294 (Python). This is the same class as F284 and
F285, because a fresh seed draws new sites. Three `shell_glob.py` sites (:47, :133, :145) survived
under both seeds, so those tests are actually weak there, not just unlucky in the sample.

The default table leaves out three modules that changed most in 105–109. A custom
`MUTATION_TARGETS` table covered them with seed 8 (H7 used 7):

| Module | Killed | Finding |
|---|---|---|
| `run-mutation-gate.sh` | unmeasured: the baseline is red in its own sandbox | F296 |
| `hook_audit.py` | 7/12 | F297 |
| `install-guard-notice-mod.sh` | 11/12 | F297 |

The spot-check scored 18/24 (75.0%), below the 80% break. `hook_audit.py` is not in the default
table, and only `test-validate-hooks.sh` reaches it. That is why it scored lowest.

## Carve budget

No row was carved. The register is converging (ratio 0.73, with 8 rows added and 11 ticked since
2026-10-30). F286–F297 wait for the findings review, which is due now: 37 findings were open
before this checkpoint, plus these 12. F293, F294, F296 and F297 fit a mutation-tooling follow-up,
F295 fits 108's parser area, and F286 and F287 are guard fail-open seams. Folding them is the
developer's decision at that review.

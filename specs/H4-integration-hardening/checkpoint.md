# H4 — integration-hardening checkpoint (template repo)

Fourth checkpoint. It covers what was ticked since H3 (eb791de): 085, 086, 087, 088 and 089.
`checkpoint-cadence.sh` reported `since=H3 count=5 due=1`.

## 1. Full-system regression

All 92 `scripts/test-*.sh` ran one at a time under bash, with a 900 s cap per file, while the
mutation run below used the same machine.

- 91/92 green in 1101 s on the first run. The slowest were `test-validate-scenario-traceability.sh`
  (207 s), `test-bash-write-guard.sh` (65 s) and `test-project-maintenance.sh` (63 s).
- The red one was `test-stryker-guard.sh` S19, the failure F086 described. F086 had been dropped on
  2026-10-02 because it did not reproduce. Here it failed 2 runs in 3. Fixed in place, see below.
- The working tree held only this checkpoint's own edits afterwards, so no suite wrote into the repo.

Fixed, red first (F126):

- `stryker_guard.py` asked `lsof` for the cwd of every stryker-shaped pid in the `ps` table. A pid
  that exited between the two calls had no cwd to read, landed in the "blind" list, and the sweep
  kept `.stryker-tmp` for a run that was already over. Under a concurrent mutation run, which spawns
  stub stryker processes, that happens often. A pid that no longer exists (`ESRCH`) is now skipped;
  one owned by another user still counts as alive. New fixture S20b uses a fake `ps` naming an exited
  pid, and it was red before the fix. The suite then passed 4 runs in 4 with the mutation run going.

## 2. Cross-cutting security sweep

`project-freshness.sh` came back clean: no verified credentials, and no key material beyond the 3
allowed hits. osv-scanner is still not installed. The template has no lockfiles, so that left
nothing unscanned.

The `security-scanner` agent swept the seams between 085 and 089 in "assume it's exploitable" mode.
A safety classifier stopped its first report. The second pass was scoped to defensive gaps: fail-open
conditions, claims the code does not keep, and missing fixtures, with no bypass commands. It did not
reach the 086 validators, `core-machinery-guard-hook.sh` or `core-owed-tick-guard-hook.sh`. Every
item was checked against the code here, and three were reproduced in a scratch project.

Recorded as F114–F122:

- F114 (reproduced): `settings_guard.py` allows any shell command that names no settings file,
  whatever its verb. `git checkout HEAD -- .`, `git restore --source=… .`, `git stash pop` and
  `git apply` all pass. The same checkout that names the file is denied.
- F115 (reproduced): only `hooks`, `disableAllHooks` and `env` are guarded. Edits adding
  `apiKeyHelper`, `statusLine` or `enabledMcpjsonServers` pass, and each one runs a command or adds a
  tool surface in the next session. The three keys were developer decision O1/O2 in 089, so the
  developer decides whether the list grows.
- F116 (reproduced): the guard matchers list built-in tools only. An MCP or plugin write tool reaches
  the settings files and the trust stores with no guard run.
- F117: `run-mutation-gate.sh` keeps the real `HOME`, and `template-autosync.sh` looks for the
  template at `$HOME/repos/Claude`. A mutant that flips one of the two 084 sandbox checks could fetch
  or push from the real clone. It did not happen in this run (reflog unchanged), but the header's
  "share nothing with the real repository" is stronger than the code.
- F118: `acceptance_cases.py` fails open on a git timeout without announcing it, and its `_git` keeps
  `GIT_DIR`, `GIT_COMMON_DIR` and `GIT_WORK_TREE` (overlaps F107, row 091).
- F119: the 088 trust prompt (R2) accepts any pseudo-terminal, so it shows that a pty exists, not
  that a person is at it.
- F120: the three pipeline guards exit 0 when no language marker exists up to the git root. Removing
  the only marker turns all three off.
- F121: `reads()` judges environment set in the same simple command only, not a variable exported
  earlier on the line. Also two false positives for row 090: `sed -n` on the settings file is
  refused, and trust-anchor-guard refuses the trust option's name inside `finding.sh` prose. Both
  happened during this checkpoint.
- F122: a linked worktree is a guard root, so a worktree at a commit from before the register runs
  no gate. F106 covers `--no-checkout` only.

Checked and holding: the named-path forms of `git checkout` against the settings file, the `hooks` key
on Edit, and the `run_test` credential scrub in `run-mutation-gate.sh`.

## 3. Scenario-map reconciliation

Not applicable. The template has no language marker and no `specs/SCENARIOS.md`, as at H1–H3.

## 4. Mutation spot-check

The first checkpoint with the runner from row 085: `run-mutation-gate.sh`, seed 4 (H3 used 3), 12
mutants per module, 2 jobs. The three modules with the most commits since H3 were measured. The bash
pre-layer is not in the default table, so a custom `MUTATION_TARGETS` added it.

| Module | Commits since H3 | Killed | H3 | Finding |
|---|---|---|---|---|
| `template-autosync.sh` | 5 | 8/12 (67%) | 5/12 | F123 |
| `project-maintenance.sh` | 4 | 7/12 (58%), 1 timeout | 6/12 | F124 |
| `bash-write-guard-hook.sh` | 2 | 7/12 (58%) | — | F125, F127 |

Overall 22/36 (61.1%), below the 80% break. Row 092 is already the place to kill survivors, so
F123–F125 list them for it.

- Fixed in place (F127): all three mutants on `bash-write-guard-hook.sh` L120 survived, including
  one that makes the pre-layer allow every readable payload. L120 is the field read used when jq is
  missing, and no fixture ever ran the hook without jq. That is the default on Git Bash and on
  minimal Linux images. New fixture `nojq` puts a `PATH` without jq in front of the same deny and
  allow cases, plus an unreadable payload that has to allow on exit 0 and announce it. L120
  re-measured 3/3 killed, and the suite passed 141/141.
- The `project-maintenance.sh` L1091 timeout is not counted as a kill
  (`.claude/rules/mutation-timeouts.md`).

## Carve budget

No row was carved. 14 findings were recorded (F114–F127). F126 and F127 were fixed here, and the
other 12 wait for the next finding review. Most of F114–F122 fit rows 090 and 091, and F123–F125
fit row 092.

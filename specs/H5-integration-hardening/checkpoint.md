# H5 — integration-hardening checkpoint (template repo)

Fifth checkpoint. It covers what was ticked since H4 (149eda0): 090, 091, 092, 093 and 094.
`checkpoint-cadence.sh` reported `since=H4 count=5 due=1`.

Three other Claude sessions (fundit, agentcrm, hireflow) ran on the same machine the whole time.
Load average sat between 24 and 36 on 12 cores. The timings below measure a busy machine, not
slower code.

## 1. Full-system regression

All 94 `scripts/test-*.sh` ran one at a time under bash, with a 900 s cap per file, while the
mutation run below used the same machine.

- 94/94 green in 1458 s (H4: 1101 s for 92, on a quieter machine). The slowest were
  `test-validate-scenario-traceability.sh` (249 s), `test-settings-edit-guard.sh` (100 s),
  `test-bash-write-guard.sh` (78 s) and `test-project-maintenance.sh` (63 s).
- Afterwards the working tree held only this checkpoint's own register edits, so no suite wrote
  into the repo.

## 2. Cross-cutting security sweep

`project-freshness.sh` was clean: no verified credentials, no key material beyond the 3 allowed
hits. osv-scanner is still not installed, and the template has no lockfiles for it to read.

The `security-scanner` agent read the seams between 090 and 094, scoped to defensive gaps
(fail-open conditions, claims the code does not keep, missing fixtures) with no bypass commands, and
told which findings row 095 already holds. Every item was checked against the code, and the first
one was reproduced in a scratch repository.

Recorded as F139–F145:

- F139 (reproduced): `trust-anchor-guard-hook.sh` tests only the last path component for a symlink.
  With an existing link `gd -> .git`, a Write to `gd/info/exclude` or `gd/description` names no
  trigger word and is allowed. bash-write-guard refuses to create the link with `ln`, so the gap
  needs a committed link or one made by a route no guard reads. The other guards got the ancestor
  walk in 090 R2 through `guard-precheck.sh`; this one does not source it.
- F140 (plausible, not reproduced): `_committed_unchanged` (091 R9) trusts the upstream
  remote-tracking ref because "R2 keeps the agent from moving it", but a plain `git push` moves
  `refs/remotes/*` as a side effect and is allowed.
- F141: core-machinery-guard and core-owed-tick-guard exit 0 without a word when the sync root has
  no settings directory or no `template-autosync.sh`, against `guard-lib.sh`'s own rule. Removing
  one file turns both off, the same shape as F120.
- F142: the guard root walk in `guard-lib.sh` runs git with no timeout, and a missing or failing git
  silently moves the root.
- F143: the mutation sandbox scrubs a denylist of nine variables; `GIT_SSH_COMMAND`,
  `GIT_CONFIG_COUNT/KEY/VALUE`, `GIT_CONFIG_SYSTEM` and cloud tokens still reach mutant tests, a
  local-path remote is not refused, and rc 137 under the limit counts as a kill.
- F144: the once-per-session fail-open notice is deduplicated through a predictable stamp in
  `$TMPDIR`, and it reaches only the model (`additionalContext`), never the developer.
- F145: three more false positives of the F121 kind, all hit during this checkpoint. The settings
  guard refused `git diff -- scripts <settings dir> | tail` and a pipeline holding the grep pattern
  `[a-z]*`; trust-anchor-guard refused a `sed -i` on a scratchpad file whose expression only named
  the git config path. A fourth refusal, a shell command that named a trust store in a test payload,
  was correct.

Checked and holding: the Write tool into `.git/` under its own name, and through a symlink when the
name carries a trigger word; `ln -s .git <name>` through bash-write-guard.

## 3. Scenario-map reconciliation

Not applicable. The template has no language marker and no `specs/SCENARIOS.md`, as at H1–H4.

## 4. Mutation spot-check

`run-mutation-gate.sh`, seed 5 (H4 used 4), 12 mutants per module, 2 jobs. The three modules
changed most since H4 had never been measured, so a custom `MUTATION_TARGETS` added them to the
default table. No mutant timed out, so the load did not reach the score.

| Module | Commits since H4 | Killed | H4 | Finding |
|---|---|---|---|---|
| `template-autosync.sh` | 3 | 6/12 (50%) | 8/12 | F150 |
| `trust-anchor-guard-hook.sh` | 3 | 9/12 (75%) | — | F151, F152 |
| `core-owed-tick-guard-hook.sh` | 3 | 9/12 (75%) | — | F151, F152 |
| `core-machinery-guard-hook.sh` | 3 | 10/12 (83%) | — | F151 |

Overall 34/48 (70.8%), below the 80% break. The samples differ by seed, so the autosync drop from
8/12 to 6/12 is a different dozen sites, not a regression.

Five of the eight guard survivors are `exit 0 -> exit 1` on an allow path (F151). Exit 1 is a
non-blocking hook error: the call still runs and the harness prints stderr, so the change is
observable, but no suite asserts that an allow exits with exactly 0. Two of those lines are F141's
silent exits, which row 095 rewrites. Two trust-anchor survivors look equivalent (F152).

## Also decided here

- The CLI's new dangerous-`rm` prompt timeout (2.1.281) does not collide with
  destructive-command-guard, which denies `rm -rf` in every spelling first (F147).
- Claude Code mods as a possible guard layer for MCP and plugin write tools (F116), and the
  claude.ai skill and plugin sync, are recorded for row 095 (F146).
- Two row proposals from the Claude Code 2026-10 update go to the developer at this stop: F148
  (a mod that shows guard notices and register state to the developer) and F149 (apply the
  `/claude-api prompt-audit` report).

## Carve budget

No row was carved. 14 findings were recorded (F139–F152), two of them row proposals for the
developer. Nothing was fixed in place: every gap found lands in code row 095 rewrites.

# H6 — integration-hardening checkpoint (template repo)

Sixth checkpoint. It covers what was ticked since H5: 095, 095a, 096, 097, 098 and 099.
`checkpoint-cadence.sh` reported `since=H5 count=6 due=1`.

The work ran in two sessions. Sections 2 and 4 ran on 2026-10-04 and their findings (F184–F195)
were committed then. The first suite run that day hit its cap (section 1), so the suite ran again
on 2026-11-16 before the row was ticked.

## 1. Full-system regression

The 2026-10-04 run never finished. `test-validate-scenario-traceability.sh` passed its 900 s cap
while the mutation run shared the machine, and no test failed, but the suite went unstamped.

On 2026-11-16 all 96 `scripts/test-*.sh` ran one at a time under bash with the same cap, on a
machine at load ~7. That run took 1181 s, and three tests were red: `test-on-linux.sh`,
`test-portability-audit.sh` and `test-self-test-prologue.sh`. All three came from
`test-worktree-root-detection.sh` (d6cc25c, after H5), whose first statement was not the
self-test prologue. The prologue check refused it, the portability audit flagged its
`cd "$(dirname "$0")/.."` without `CDPATH=''`, and test-on-linux re-runs the audit. The prologue
line was added here and all three went green.

The second maintenance run was red again, and again the report named no test (F224). A third
per-test run found `test-stryker-guard.sh` G21, which is flaky rather than a regression: alone
it passed three times out of three. `spawn` starts the fake Stryker inside `$(...)`, so the
process is not the test shell's child, `stop`'s `wait` returns at once, and on a loaded machine
G21 asks the guard before SIGTERM has landed. `stop` now polls `kill -0` for up to ~5 s. The
other 95 tests were green in that run.

After both fixes were committed (80261b0), `project-maintenance.sh --suite` ran on a clean tree:
96/96 green in 1290 s, stamped `pass`. The pass still exits 1 on its two hygiene findings (the
register's context cost and F225's executable bit), not on the suite. The secrets and CVE job ran
in the same passes and was stamped too.

Two more items from this section:

- F224: `project-maintenance.sh --suite` keeps only the tail of the loop's output, so the first run
  said "failed (exit 1)" without naming a test. Finding the three failures took a second run.
- F225: `install-guard-notice-mod.sh` and `test-guard-notice-mod.sh` lack the executable bit. The
  095a guard refuses an agent `chmod` on the mod installer, as it should, so this one is the
  developer's to run with `!`.

## 2. Cross-cutting security sweep

`project-freshness.sh` was clean. The `security-scanner` agent read the seams between 095 and 099,
scoped to defensive gaps (fail-open conditions, claims the code does not keep, missing fixtures)
with no bypass commands. It returned ten items. Three were reproduced in a scratch repository and
the rest were checked against the code.

Recorded as F184–F193:

- F184 (reproduced): `rm -r .git` and `rmdir` under it pass every guard; only `rm -rf` and
  `find -delete` are denied. With `.git` gone, `guard_git_boundary` finds no root, so
  spec-register, core-machinery and core-owed-tick exit 0 without a word. 098 TB4 names only
  chmod, mv and chown.
- F185: the 096 guard-notice mod, installed user-wide, runs the project's own
  `scripts/maintenance-due.sh` in every project that holds `specs/INDEX.md`, outside any tool call.
  Spec 096 says it widens no trust boundary.
- F186: 096 R6 refuses the mod installer by filename shape only. A quoted program string with
  arguments skips the nested re-judge unless it names git or claude, and the installer copies
  agent-editable mod source with no pin.
- F187 (reproduced): `touch` and `mkdir` under `.git/claude-hook-notices/` pass every guard. The
  stamp name is a sha256 of fixed text, so a literal path can pre-plant the once-per-session stamp
  and silence both the 098 notice and the 096 toast.
- F188: `_guard_notice_base` follows an ancestor `.git` file into its git dir, but trust-anchor
  protects only `$CLAUDE_PROJECT_DIR/.git` and harness-state-gc sweeps only a `.git` directory.
  Worktrees and submodules keep unguarded, unswept stamps.
- F189: `template-identity.sh` runs `git config` and `git rev-list` with no timeout and no `GIT_*`
  scrub, and three guards call it. F142 residue outside what 098 R4 claims.
- F190: the `hook_audit` matcher check (098 R8) reports a wrong matcher but not a guard that was
  never wired. A project-local settings group masks the committed one, and wiring is found by
  substring.
- F191: project-maintenance treats ratchet exit 77 as a note with no count or cap, `--unattended`
  does not fail on it, and with no `timeout` or `gtimeout` the ratchets run unbounded.
- F192: spec 095a R1(e)/R2 say project skill folders are denied for any content. The settings guard
  makes them soft (Edit and Write allowed, placing verbs refused). The hook header is right and the
  spec text overstates.
- F193 (reproduced): settings guard false positives. `STDOUT_FILTERS` lacks
  sort/uniq/rev/paste/tac, so `git log -- <settings dir> | sort | uniq` is refused, and the deny
  text names no rule. Same kind as F145.

## 3. Scenario-map reconciliation

Not applicable. The template has no language marker and no `specs/SCENARIOS.md`, as at H1–H5.

## 4. Mutation spot-check

`run-mutation-gate.sh`, seed 6 (H5 used 5), 12 mutants per module. A custom `MUTATION_TARGETS`
table covered the four modules 095–098 changed most.

| Module | Killed | Finding |
|---|---|---|
| `guard-lib.sh` | 11/12 | F195 |
| `trust-anchor-guard-hook.sh` | 11/12 | F195 |
| `settings-edit-guard-hook.sh` | 11/12, +1 timeout | F195 |
| `hook-notice.sh` | 8/12 | F194 |

Overall 41/48 (85.4%), above the 80% break. The timed-out mutant is not counted as a kill.

- F194: `hook-notice.sh` survivors at :76 (`-z`→`-n`, `&&`→`||`), :159 (`return 0`→`1`) and :176.
  No test asserts the SessionStart banner or the no-hasher path.
- F195: `trust-anchor-guard-hook.sh:123` `exit 0`→`1` survives on the cannot-load-guard-lib deny
  path. Exit 1 is a non-blocking error, so the deny JSON may be dropped: F151's class, on a deny.
  `guard-lib.sh:223` survives the same way.

Both fit row 100, which already owns the earlier survivors.

## Carve budget

No row was carved. Fourteen findings were recorded (F184–F195, F224, F225). The one fix made in
place was the missing prologue line, which was smaller than a finding. F194 and F195 belong to
row 100, and the rest wait for the next findings review.

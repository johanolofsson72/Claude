# 085 — template mutation runner and core coverage

Track: full, hardened (trigger 4: one new runner plus tests and fixes in at least six files; the
runner is also a command the 082 nightly executes unattended, so it sits on a trust boundary).
Findings: F047 (mutation half), F048, F049, F058, F071, F072, F073, verbatim in `specs/FINDINGS.md`.

## Problem

`maintenance-due.sh` has said "mutation kill rate (Stryker) — never run in this project" on the
template since the job existed, and it always will. `project-maintenance.sh --full` looks for
`scripts/run-mutation-gate.sh`, then a .NET solution, then StrykerJS. The template has none of
them, so it notes "no mutation runner for this stack" and stamps nothing. Stryker has no bash
target. The only mutation numbers this repository has ever produced came from H1 and H2 by hand,
from scripts nobody kept, and each one recorded survivors that no later spec killed:

- **F048** `project-freshness.sh` 5/10: the `AUDIT_RC -eq 0` branch, workspaces detection, the awk
  DP-key length test, the `--secrets` scope flag, the `--fix` path.
- **F049** `project-maintenance.sh` 7/12: the register-bytes non-empty guard, a missing-file return,
  the FAST_OUT preview, the ledger record on LEDGER_OK, `--help`.
- **F071** `template-autosync.sh` 3/12 on a fresh sample after 078 armed H1's own ten: the
  no-template-found exit, the empty-candidates exit, the claimed-vs-parsed count check, the
  commit/in-progress branch, the held-name limit.
- **F072** `project-maintenance.sh` 7/12 again at H2: the CARVE_RC branch, the empty SK_VER branch,
  the TRACE_DUP and TRACE_COV notes, an `exit 0`.
- **F073** one H2 mutant (`--help`'s `exit 0` → `exit 1` in `validate-scenario-traceability.sh`)
  made its self-test run the full 600 s instead of failing.
- **F058** `maintenance_ledger.py report` prints "ready for 075" when the ledger spans five ticked
  specs, even when no heavy job (mutation, suite) has a single run in it.

F071 also names the structural problem: a fixed sample gets armed and the file does not. A runner
that draws a fresh sample each time is the thing that keeps measuring the file.

## Requirements

- **R1 — A template mutation runner.** `scripts/run-mutation-gate.sh`, already on
  `TEMPLATE_ONLY_SCRIPTS` (never shipped). It mutates bash scripts with operator mutants and runs
  each module's own self-tests against every mutant.
  - **Targets** are a table inside the runner: module → the self-tests that drive it. The defaults
    are `template-autosync.sh`, `project-maintenance.sh`, `project-freshness.sh` and
    `validate-scenario-traceability.sh`. `--module <path>` (repeatable) restricts the run to listed
    modules. A module that is not in the table is a usage error (exit 2), never a guess.
  - **Operators**, one class each: arithmetic comparison (`-eq`↔`-ne`, `-lt`↔`-ge`, `-gt`↔`-le`),
    string test (`-z`↔`-n`), boolean (`&&`↔`||`), exit/return code (`exit 0`↔`exit 1`,
    `return 0`↔`return 1`), file test negation (`[ -f X` → `[ ! -f X` for `-f -d -e -s -x`).
    Comment lines and heredoc bodies are never mutated. A line carrying
    `# mutant-equivalent: <reason>` is not mutated; the reason is the record.
  - **Sampling.** `--sample N` per module (default 12), stratified round-robin across operator
    classes, from a seeded RNG. `--seed S` (default today's UTC date as `YYYYMMDD`, so each day draws
    a new sample and a run is reproducible). The seed is printed.
  - **Named sites.** `--lines <module>:<line>[,<line>…]` mutates every site on the named lines and
    nothing else. It is how a recorded survivor is re-measured.
  - **Isolation.** The working tree, including untracked files that are not ignored, is
    snapshotted through a temporary index into a run-private object directory (the real index,
    HEAD and object store are never written). It is checked out into one independent `git init`
    repository per worker (no `.git` link, remote or hooks; review #2) under
    `${MUTATION_WORKDIR:-$HOME/.cache/claude-mutation}` (under `$HOME` because
    `test-drive-sync.sh` judges its sandbox by location; the H1 trap). `--jobs N` (default 4, at
    most 16). The run dir is removed at exit, on success, on failure and on interrupt.
  - **Baseline first.** Each module's tests run once unmutated. A red or timed-out baseline makes
    the whole run UNMEASURED: no score is printed, exit 2, and the failing test is named. A mutant
    measured against a red suite is not a measurement.
  - **Bounded.** Every test run has a limit of `max(60, 3 × its baseline seconds)` through
    `timeout`/`gtimeout`. A timeout is recorded as a Timeout and is **not a kill**
    (`.claude/rules/mutation-timeouts.md`).
  - **Kill.** A mutant is killed when one of its module's tests exits non-zero without timing out.
    The first kill stops the remaining tests for that mutant.
  - **Infrastructure failure.** A copy or test that is gone, or a `timeout` that cannot start its
    command (125/126), gives the mutant no verdict, and the report then refuses to score (exit 2).
    It is neither a kill nor a survivor (review #3).
  - **Output contract** (the one in `project-maintenance.sh` section 5): one line per module
    `<module>: <killed>/<valid> killed (<P>%)`, each survivor as
    `  survived <module>:<line> <class> '<before>' -> '<after>'` (timeouts say `timeout`), then
    `mutation score <N>%`, the strict score (killed / valid, one decimal) over all modules.
    A Stryker schema-1 JSON report goes to `.claude/state/mutation/mutation-report.json`
    (gitignored), so the per-module half of section 5 reads it. A timed-out mutant is written as
    `Survived` with `statusReason: "timeout — not a kill"`, so the per-file score there is strict too.
  - **Exit.** 0 when the score is at least the break (`MUTATION_BREAK`, default 80), 1 below it,
    2 when nothing could be measured (usage error, red baseline, missing `git`/`python3`/`timeout`).
  - **Portable.** bash 3.2, BSD and GNU userland. A missing `timeout`/`gtimeout` is exit 2, not an
    unbounded run.
- **R2 — The template's mutation job gets stamped.** `project-maintenance.sh --full` in the template
  runs the runner through its existing first branch, reads the score and the JSON report, and
  stamps the job. `maintenance-due.sh` stops reporting "never run". No change to section 5 is
  needed or wanted; R1 meets the contract that is already written.
- **R3 — The named survivors are killed or proven equivalent.** Every site F048, F049, F071 and
  F072 names is re-measured with `--lines` at its current line. Each non-equivalent survivor gets a
  test in that module's existing self-test that fails against the mutant. Each equivalent one is
  listed in this spec with the reason, and its line carries `# mutant-equivalent:`.
- **R4 — F073 is diagnosed and closed.** Re-run the H2 mutant alone, bounded. If the self-test
  hangs, find the wait and make it fail fast. If it does not hang (the 600 s was load), record the
  measured time, and the runner's baseline-relative limit (R1) is the fix: a slow test under load
  reads as a Timeout, which is honest, rather than a pass.
- **R5 — Ledger readiness counts measurements (F058).** `maintenance_ledger.py report` says
  "ready for 075" only when the span is met **and** each heavy job (`mutation`, `suite`) has at
  least one recorded run. Otherwise it says `keep measuring — no run of: <jobs>`.

## Out of scope

- Shipping the runner to projects. Project stacks have Stryker; the bounding is generic but the
  target table is the template's. It stays on `TEMPLATE_ONLY_SCRIPTS`.
- Arming every operator site in the four modules. 530 sites in autosync alone. The daily sample is
  what keeps measuring the file; this spec closes the survivors already recorded.
- Mutating Python helpers. The operators are bash operators.
- Any GitHub Action (`.claude/rules/github-actions.md`).

## Threat model

Written before implement (`.claude/rules/spec-hardening.md`). Trust boundaries: the runner reads
committed scripts and executes committed self-tests, and the 082 nightly may run it unattended.

| STRIDE | Threat | Mitigation |
|---|---|---|
| Tampering | A changed runner runs unattended at night | Unchanged 082/088 path: the nightly runs the runner only when its bytes match what the developer trusted in a terminal; the runner adds no trust path |
| Tampering | A mutant escapes the worktree and edits the real checkout | Mutations are applied to `<copy>/<module>` only. A table path must be relative, with no `..` and nothing outside `[A-Za-z0-9._/-]`; no component of it may be a symlink in the copy; `apply` checks the real path stays inside the copy and replaces the file rather than writing through it. Each copy is an independent `git init` repository (no `.git` link, remote or hooks), and tests run without `SSH_AUTH_SOCK`, `GH_TOKEN`, `GITHUB_TOKEN` or askpass helpers (review #1, #2) |
| Tampering | A crashed run leaves a mutant in a worktree that a later run reuses | Each run makes a fresh `mktemp -d` run dir; worktrees are never reused across runs; stale dirs older than a day are pruned |
| Repudiation | A score with no record of what was measured | The seed, sample size and per-mutant verdicts are printed and written to the JSON report |
| Information disclosure | Untracked secrets copied into the snapshot | The snapshot honours `.gitignore` (the temp-index add skips ignored files), its blobs go to a run-private object directory (the real store is only read, as an alternate), and the copies live under `$HOME`; all of it is removed at exit, and nothing is pushed or sent anywhere (review #11) |
| Denial of service | A mutant that loops forever pins the machine all night | Per-test limit `max(60, 3 × baseline)` through `timeout -k 5`; `--jobs` caps parallelism; a timeout is recorded, never retried |
| Denial of service | Disk fills with copies from killed runs | At start, remove marked run dirs whose owner pid is gone; the EXIT trap (INT, TERM, HUP routed to it) is installed before the run dir exists (review #4, /tla GAP-2) |
| Elevation | A crafted line in a module makes the Python site-finder execute it | The site-finder only reads text and does string replacement; nothing in a module is evaluated by the runner itself, only by the module's own tests inside the worktree |
| Spoofing | Output that looks like a score from a run that measured nothing | A red baseline, a usage error and a missing tool print no `mutation score` line (section 5 then reports "failed to complete"); a timeout is never counted as a kill |

Residuals: the runner executes the module self-tests, which are repository code; that is the
same trust the suite job already has (082).

## Clarifications

### Session 2026-10-01 (auto-picked, recommended option)

- Q: Does a killed mutant need every test to fail? → A: No. One non-zero, non-timeout exit kills it,
  and the rest are skipped. That is Stryker's semantics and it keeps a run near ten minutes.
- Q: What score does the runner print when one module is UNMEASURED? → A: None. A baseline failure in
  any module stops the run before mutants (exit 2). A partial score over the modules that happened to
  be green would read as the template's score.
- Q: How does `--lines` interact with `--sample`? → A: `--lines` replaces sampling for the modules it
  names; `--module` is implied. Every site on the named lines is measured.
- Q: Where does the runner's own self-test run its fixtures? → A: In a throwaway git repo under
  `mktemp -d` with a tiny module and tests, and `MUTATION_TARGETS` pointing at a fixture table. The
  real table is not used by the self-test, so it stays fast.
- Q: Is the target table overridable? → A: Yes, by `MUTATION_TARGETS=<file>` (lines
  `<module> <test> [<test>…]`), used by the self-test. The default table lives in the runner.
- Q: What counts as "equivalent" for R3? → A: A mutant no test can distinguish because the program's
  observable behaviour is unchanged (for example `exit 0` at the end of a script that already exits
  0). The reason is written on the line and repeated in `## Survivors` below.

## Survivors (R3, 085-AC-3)

Re-measured on 2026-10-01 with `run-mutation-gate.sh --lines` at the current line numbers. Every
site on each named line was measured, not only the one H1/H2 sampled.

| Module | Before | After | Where the arms live |
|---|---|---|---|
| `project-freshness.sh` (F048) | 4/11 | 9/9 runner sites, plus both awk sites by hand | `test-project-freshness.sh` K8, K16, C10 |
| `project-maintenance.sh` (F049, F072) | 8/23 | 18/18 on the eight lines still surviving | `test-project-maintenance.sh` C101–C109 |
| `template-autosync.sh` (F071) | 2/9 | 6/6, one equivalent | `test-template-autosync-arms.sh` M13, M15–M19 |
| `validate-scenario-traceability.sh` (F073) | 0/1 | 1/1 | `test-validate-scenario-traceability.sh` case0 |

Equivalent, with the reason on the line:

- `template-autosync.sh` `[ -n "$_cands" ] || exit 0` in `unlisted_core_shaped`: the exit ends a
  subshell whose status becomes the function's return value, and all five callers read only its
  stdout, which is empty either way. The script has no `set -e`.

Equivalent in practice but not marked: `project-maintenance.sh` `mutation_break_of`'s
`[ -f "$1" ] || return 0` (its one caller reads stdout only). The line also holds a killable `||`
site, and a marker would hide it, so C106 tests the function's contract directly.

The awk sites in `project-freshness.sh` (`length(t[i]) >= min` and the `<value>` `>= 40`) are inside
a quoted awk program, which the runner does not mutate. They were applied by hand: both are killed by
the 40-character Data Protection key in K8.

F073 was not a hang. Alone, the mutant (`--help` `exit 0` → `exit 1`) ran the self-test for 189 s and
passed 59/59: no case called `--help`, so the mutant survived, and H2's 600 s was load from four
parallel workers. `case0-help` kills it, and the runner's baseline-relative limit reports a slow run as
a timeout and never as a pass.

## Adversarial review (hardened, security-scanner in "assume exploitable" mode)

Fourteen flags. Each one was fixed, or dismissed with a reason. The fixed ones have an arm in
`test-run-mutation-gate.sh` (sabotage S6, S8–S11) or `test-maintenance-ledger.sh`.

1. **High:** a symlinked module would be written through. **Fixed:** `no_link` checks the copy, `apply` checks the real path and replaces the file. Arm `arm_hostile_paths`, S9.
2. **High:** linked worktrees shared `.git`, the remote and the hooks, and the tests inherited credentials. **Fixed:** independent `git init` copies via `checkout-index`, and the credential variables are unset for tests.
3. **Medium:** an infrastructure failure counted as a kill. **Fixed:** a missing copy or test, or a `timeout` exit of 125/126, gives no verdict, so the report refuses to score (exit 2). Timing uses `$SECONDS`. Arm `arm_infra_is_not_a_kill`, S11.
4. **Medium:** stale cleanup ran `rm -rf` on any `run.*` dir under `MUTATION_WORKDIR`. **Fixed:** the dir must be absolute and must not be `/`, `$HOME`, inside the repository or above it. The runner removes only dirs that carry its marker and whose owner pid is gone. Arm S10. `/security-review` then showed the `/` arm could never match, because the guard tests `"$WORKDIR/"` and `/` reads as `//` there. Fixed in place, arm S12.
5. **Medium:** `MUTATION_*` variables sit outside the 082 byte hash. **Dismissed, mitigated by disclosure:** the environment of an unattended run is set by whoever installed the nightly, which is the trusted party. The settings in force are now printed (`settings: …`) and written to the JSON.
6. **Medium:** trust covers the runner and not the tests it runs. **Dismissed as a duplicate of F092** (suite identity hashes the line, not the files). This is the same residual, already recorded.
7. **Low:** a colon, a tab or a control character in a table path or an exit token. **Fixed:** the path character class, and `exit`/`return` must be followed by spaces only. Arm S8.
8. **Low:** CRLF was rewritten. **Fixed:** `newline=""` on every read and write.
9. **Low:** a second signal could abort the cleanup, and HUP had no trap. **Fixed:** the cleanup ignores INT, TERM and HUP, and HUP exits 129.
10. **Low:** an empty table, a module with no tests, `--lines mod:` and a Python crash each became exit 1 or a vacuous run. **Fixed:** all four exit 2. Arm `arm_hostile_paths`.
11. **Low:** snapshot objects stayed in the real store. **Fixed** by #2's private object directory. The `state()` check now includes `git count-objects`, sabotage S6.
12. **Low:** the seed and sample were missing from the JSON. **Fixed.**
13. **Low:** `--jobs 08` was read as octal and `--jobs` had no cap. **Fixed:** base 10, 1–16. The runner now calls `bash -- "$test"`, and `git worktree prune` is gone. `set -f` was not added: table paths can no longer hold glob characters, and the runner's own globs need it off.
14. **Low (ledger):** a `nan`/`inf` row crashed `report`. **Fixed:** `num()` returns None for them. Counting a failed heavy run as a measurement is **kept on purpose**: duration and memory are what 075 places, and a gate that fails was still measured.

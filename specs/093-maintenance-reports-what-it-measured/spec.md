# 093 — maintenance reports what it measured

Track: spec-only. No entity, no state machine, no new external surface. Five fixes to what the
maintenance pass and the production scripts say about a run. Not hardened: no trigger fires. Every
change makes a report more exact or a script less sensitive to the caller's environment. None of
them widens what runs. Findings verbatim in `specs/FINDINGS.md`.

## Problem

| Finding | Where | What goes wrong today |
|---|---|---|
| F109 | `project-maintenance.sh` section 5 | With `scripts/run-mutation-gate.sh` as the runner, the scope reads "a bare `bash scripts/run-mutation-gate.sh` reads only stryker.conf.json" and the threshold reads "this config states no break". The runner chooses its own targets and prints its break on a `settings:` line, and section 5 reads neither |
| F110 | the nightly and the due banner | The template's default mutation run took 3604 s and the suite about 40 min. The ledger has the numbers. The banner that says "Run now: … --full" does not, so the developer finds out by waiting |
| F111 | `.claude/.suite-command`, `project-maintenance.sh` suite section | A self-test that hits its 900 s `timeout` at load 7–8 prints `FAIL` and the pass reports "`…` failed". A timeout measured nothing: neither green nor red |
| F113 | 88 command substitutions in 52 production scripts | `$(… \| head -1)` and friends. Under an inherited `SIG_IGN` (.NET parents) the writer gets EPIPE and prints "Broken pipe" to stderr, which fails any caller that asserts silent stderr (msroute F008) |
| F087 | ~80 `cd "$(dirname …)"` lines in production scripts | Run by hand as `bash scripts/x.sh`, `dirname` is `scripts`, a relative path, so `cd` searches `CDPATH` first and can land in another clone. When it does, `cd` also prints the directory, so `$(cd … && pwd)` holds two lines |

## Requirements

- **R1 (F109).** When the mutation command is the project runner, section 5 says so. Scope reads
  "the project runner decides what it mutates (scripts/run-mutation-gate.sh)". The threshold comes
  from the runner's own `settings:` line (`break N`). A runner that prints no break gets the ~80%
  default, and the report says "the runner printed no break". The timeout note stops calling the
  number Stryker's: how a timeout counts is the runner's to state.
- **R2 (F110).** `maintenance_ledger.py estimate JOB…` prints each job's median seconds at this
  place and the run count, or `unknown` with zero runs. The due banner (`maintenance-due.sh`, brief
  and long) adds one `Expected:` line for the heavy jobs that are due, from that estimate. With no
  ledger runs it says the cost is unmeasured. `install-nightly-maintenance.sh` prints the same
  estimate when it installs.
- **R3 (F110, in passing).** When the full suite is due, the banner's command includes `--suite`.
  `--full` alone never runs the suite, so the line it printed could not clear that job.
- **R4 (F111).** The template's `.suite-command` prints `TIMEOUT <test> — unmeasured after 900s`
  for exit 124 and exits 124 when timeouts are the only non-green results. Any failure still exits 1.
  The suite section reads exit 124 as UNMEASURED, worded apart from FAIL, not stamped. An aborted
  verdict still wins. A red run that also had timeouts names them.
- **R5 (F113).** No early-exit pipeline in a command substitution in a production script. Each site
  is rewritten by hand to a reading consumer (`sed -n 1p`, `sed -n 1,Np`, `awk` on the file, a
  variable substring for `head -c`, `od -N` for the random run name). `validate-no-sigpipe-assertions.sh
  --leaks` is clean on the template, and its self-test pins that at zero on the real tree.
- **R6 (F087).** Every `cd` whose argument is built from `$(dirname …)` in a production script is
  `CDPATH='' cd`. `portability_audit.py` gets a check for the unguarded form, so the defect cannot
  come back. A script that sources `self-test-env.sh` is exempt because it already unset `CDPATH`.

## Non-goals

- A time budget that refuses to start a job. R2 reports cost; it does not enforce it.
- Rewriting relative `cd` arguments that do not come from `dirname` (hook-supplied absolute paths,
  `git rev-parse` output).
- Changing the runner's sample size or job count to make the nightly shorter.
- Leaks in self-tests: `--strict` and the assertion scan already cover those.

## Success criteria

- **SC-A.** A fixture runner that prints `settings: break 70` and `mutation score 75.0%` is reported
  as passing its own break of 70, scope names the runner, and no line says `stryker.conf.json`.
- **SC-B.** With a ledger holding mutation and suite runs, the due banner prints an `Expected:` line
  naming both. With an empty ledger it prints "unmeasured".
- **SC-C.** A suite command that exits 124 is reported UNMEASURED and is not stamped.
- **SC-D.** `validate-no-sigpipe-assertions.sh --leaks` exits 0 on the template.
- **SC-E.** `validate-portability.sh --all` is clean, and a fixture with an unguarded
  `cd "$(dirname "$0")"` is flagged.

## Clarifications

### Session 2026-10-03

- Q: Does R1 parse the break from any line, or only `settings:`? → A: Only a line starting
  `settings:`, matching `break <int>`. That line is the runner's declared output contract, and a
  wider grep would read numbers out of test output.
- Q: Which ledger runs feed the estimate: all places, or this one? → A: This place only. Cloud and
  local run times differ, and the banner speaks to the machine it is printed on.
- Q: Does a failed run count toward the median? → A: Yes. A red suite took that long too, and the
  developer is asking about wall time, not about the verdict.
- Q: Exit code for timeouts only: 124 or a new value? → A: 124. It is `timeout(1)`'s own code,
  so a project that wraps its whole suite in `timeout` gets the same reading for free.
- Q: `head -c N` on a variable: bytes or characters? → A: Characters (`${V:0:N}`). These caps
  bound a prompt's size, and a character cut never splits a multibyte sequence.

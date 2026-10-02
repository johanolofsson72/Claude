# 086 — maintenance and gate blind spots

Track: spec-only. No entity, no state machine, no new external surface. Sixteen small, independent
fixes to reporting and helper scripts. Not hardened: no trigger fires. The one input-handling
change (F069, quoting a path that `sh -c` runs) is a hardening of an existing local path, and the
new hook audit reads configuration only and runs nothing. Findings verbatim in `specs/FINDINGS.md`.

## Problem

Each finding is a place where a check passes, or stays quiet, about something it never looked at.

| Finding | Where | What it misses today |
|---|---|---|
| F033 | `project-maintenance.sh` §1 | `project-freshness.sh` exits 0 on a `NOT SCANNED` result, and the pass reads 0 as clean |
| F032 | `project-maintenance.sh` §2c, §6b | a missing CORE script (`validate-no-sigpipe-assertions.sh`, `register-convergence.sh`, `carve_audit.py`) skips the section in silence |
| F051 | `mutation_break_of` | reads the Stryker config with bare `json.load` and case-sensitive keys; a commented config loses its `break` |
| F052 | `stryker_guard.py`, `bash_write_targets.py` | two heredoc strippers; the shared one handles only the first heredoc on a line |
| F023 | maintenance | no project without a gate runner ever runs a CORE self-test, so a project-specific red is invisible |
| F001 | nothing | no check that a user-global or plugin hook command resolves (a literal `${CLAUDE_PLUGIN_ROOT}` failed at every session start for months) |
| F003 | `test-hook-channels.sh` | sees `scripts/*-hook.sh` only; a project-authored hook registered elsewhere carries the inert-deny defect unseen |
| F025 | `spec-register-orientation-hook.sh` | offers a row as Next without reading its `needs …` clause |
| F027 | `validate-no-sigpipe-assertions.sh` | `--all/--strict` skip assignment-shaped pipelines (`X=$(… \| head -1)`), so `--strict` clean reads as "no leak" |
| F005 | `validate-scenario-traceability.sh` | a scenario proven by a script self-test cannot be credited without making `scripts/` a root, which admits source comments |
| F060 | `detect-verify-command.sh` | derived `nUnitTest/` (a Playwright recording) while CLAUDE.md names `club/Tests`; derived a test project with zero `.cs` files |
| F069 | `detect-verify-command.sh` | prints raw `find` paths into a command `template-sync-verify.sh` runs with `sh -c` |
| F068 | `install-nightly-maintenance.sh` | log and PATH file keyed by `basename(ROOT)`; two repos with one basename share them and `--remove` of one breaks the other |
| F070 | `tlc-cleanup.sh` | machine-wide: one project's Stop hook kills another project's long deliberate TLC run |
| F059 | `test-stryker-guard.sh` | carries `dotnet stryker` lines as fixtures; a project scan for runners counts it |
| F010 | msroute's `mutation-gate-repeat.sh` | prints "build failed before run N" and swallows the build output |

## Requirements

- **R1 (F033).** When `project-freshness.sh` exits 0 with `NOT SCANNED` in its RESULT, the pass
  does not read it as clean. A secret pass not scanned (`trufflehog`, `key-shape`) is a
  `[SECRETS/DEPS] NOT SCANNED` finding that quotes the RESULT line. Only `deps(…)` unchecked
  manifests is a note: an ecosystem osv-scanner cannot read stays that way, and a permanent red is
  an ignored one.
- **R2 (F032).** §2c and §6b report a missing CORE script as `[SETUP] … missing — run
  /project-update`, the shape §6c already has. §6b still applies only when `specs/INDEX.md` exists.
- **R3 (F051).** `mutation_break_of` reads the config through `stryker_guard.py break <file>`:
  bounded read, BOM, `//` and `/* */` comments, trailing commas, case-insensitive
  `stryker-config` / `thresholds` / `break`. Unreadable or absent still echoes nothing.
- **R4 (F052).** One heredoc helper, in `bash_write_targets.py`, handles every heredoc opened on a
  line, in order. `blank_heredoc_bodies` and the interpreter-region scan use it, and
  `stryker_guard.py` imports it instead of keeping its own `strip_heredocs`.
- **R5 (F023).** `project-maintenance.sh --full` runs every CORE self-test that
  `core-gates.sh` lists, each bounded by `MAINTENANCE_CORE_TEST_TIMEOUT` (default 300 s). A red or
  timed-out one is a `[CORE SELF-TEST]` finding naming it and pointing at the template register
  (`T0`). A missing or failing `core-gates.sh` is `[SETUP]`. In the template repository itself
  the section is a note: the template's own suite runs these already.
- **R6 (F001, F003).** A new CORE gate, `scripts/validate-hooks.sh` (logic in
  `scripts/hook_audit.py`), reads every command hook Claude Code would load: the project's
  `.claude/settings.json` and `settings.local.json`, the user's `~/.claude/settings.json`, and the
  `hooks/hooks.json` of each enabled plugin. For each, it expands `$CLAUDE_PROJECT_DIR`,
  `${CLAUDE_PLUGIN_ROOT}` (plugin hooks only), `$HOME` and a leading `~` the way the shell would,
  without running anything, and reports a command whose program is not found, whose script file is
  missing, or which keeps an unexpanded variable. For each project-registered hook whose script
  lives in the project and is not CORE, it applies the two output-channel checks of
  `test-hook-channels.sh`: a top-level `additionalContext`, and a `hookSpecificOutput` with no
  `hookEventName`. Exit 0 clean, 1 findings, 2 cannot read. `project-maintenance.sh` runs it on
  every pass as a `[HOOKS]` finding.
- **R7 (F025).** When the Next row carries a `needs …` clause, the orientation banner says so.
  An id-shaped entry naming a row that is not ticked is a `⚠ blocked` line naming the entry and
  the register-rewrite route. Words it cannot check (`five ordinary specs ticked under its ledger`)
  are quoted with "check this before starting". Selection does not move: the guards resolve the
  active spec through `spec_active.py`, and a banner that skipped the row would disagree with them.
- **R8 (F027).** Under `--all`, a pipeline into an early-exit consumer inside a command
  substitution in a production script is counted as a **leak**, quoted or not. The count and the
  first lines are printed in every branch, `clean` included, and `--leaks` makes them fail the
  run. `--strict` keeps its meaning. The template's existing sites are not bulk-rewritten here:
  msroute M2 showed a bulk pass turning a suite red. They are recorded as one finding.
- **R9 (F005).** A reference root may end in a file glob (`scripts/test-*.sh`). The directory part
  must exist and the glob must match at least one file, or the gate refuses as it does for a
  missing root. Only matching files are read. Works from `--roots` and from
  `specs/traceability-roots`.
- **R10 (F060).** `detect-verify-command.sh` first reads CLAUDE.md: when exactly one distinct
  `dotnet test <path>` without `--filter` names an existing test project (or its directory) whose
  name is not E2E/UI shaped, that is the command, provenance `named in CLAUDE.md`. Otherwise
  derivation is as before, except a test project with no `.cs` file under its directory is not a
  candidate.
- **R11 (F069).** Paths in the emitted command are quoted for POSIX `sh` when they hold anything
  outside `[A-Za-z0-9._/+-]`. A plain path prints unchanged.
- **R12 (F068).** The log and PATH file are keyed `<basename>-<cksum of the full root>`. A legacy
  `<basename>.path` is removed by `--remove` or a reinstall only when no remaining crontab line
  references it.
- **R13 (F070).** By default `tlc-cleanup.sh` kills only TLC processes whose working directory is
  inside the project root (`CLAUDE_PROJECT_DIR`, else the git toplevel, else `$PWD`). A process
  whose working directory cannot be read is left alone and named. `--any-project` restores the
  machine-wide sweep for manual use.
- **R14 (F059).** `test-stryker-guard.sh` says in its header that it runs no Stryker, and
  `.claude/docs/testing.md` tells a project scan for runners to skip CORE files
  (`template-autosync.sh --list-core-scripts`).
- **R15 (F010).** `.claude/docs/testing.md` says a repeat wrapper prints the tail of a failed
  build. msroute owns the script, so the fix there is a notice, not an edit.

## Non-goals

Moving Next past a blocked row. Rewriting the ~79 assignment-shaped SIGPIPE sites. Editing
msroute. Checking hook *behaviour* (only resolution and output-channel shape).

## Clarifications

### Session 2026-10-02

- Q: Does `validate-hooks.sh` belong in `core-gates.sh`'s gate list? → A: Yes, by default: it is
  gate-shaped and runnable in any project. Its self-test fakes `HOME`, so it never reads the real
  user configuration.
- Q: Does a hook command that is plain shell (`echo '{…}'`, `INPUT=$(cat); …`) count as unresolved?
  → A: No. Only the first simple command's program and an interpreter's script argument are judged;
  a compound command is judged on its first program alone.
- Q: Should `--leaks` imply `--all`? → A: Yes, as `--strict` does.
- Q: Does the needs line appear in the short (`MSG`) banner form too? → A: A needs warning counts as
  actionable, so the banner switches to the full form and prints it right under `Next:`.

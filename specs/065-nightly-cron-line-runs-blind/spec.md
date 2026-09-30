# 065 — nightly-cron-line-runs-blind

Track: spec-only. No entity, no state machine. One script plus a new test suite:
`scripts/install-nightly-maintenance.sh`, `scripts/test-install-nightly-maintenance.sh`, and the
sync list in `scripts/template-autosync.sh`. No hardening trigger fires (no new surface; the crontab
side effect already exists and keeps its marker).

Evidence: fundit F084 and F086 (2026-09-08/09). Diagnosis in `specs/INDEX.pending.md`.

## The defect

1. The line runs under cron's PATH (`/usr/bin:/bin:/usr/sbin:/sbin`). dotnet, node, npm, npx,
   docker and timeout are not on it. fundit's mutation pass failed every night from 2026-09-04 with
   `dotnet: command not found`.
2. The redirect to the log sits at the end of the command. A command that fails to parse never
   reaches the redirect, so the log keeps an old run. "Never fired", "failed to parse" and "ran and
   wrote nothing" look the same.
3. `$ROOT` and `$LOG` go into the line unquoted. A path with a space splits into two words, and a
   `%` becomes a newline in cron.

## Requirements

- **FR-01** The maintenance run gets the PATH the installer runs under, captured at install time
  into `~/.claude/nightly/<project>.path` and read by the line (`PATH=$(cat …) && export PATH`).
  Empty and relative entries are dropped, duplicates removed, order kept. A missing PATH file stops
  the run with a logged failure; it never runs blind. `--remove` deletes the file.
- **FR-02** The line opens the log before it does anything else (`exec >LOG 2>&1`), then writes a
  start heartbeat with the date and a final `claude-nightly: end exit=<rc>` line. A run that fires
  always changes the log, even when `cd` or the maintenance script fails.
- **FR-03** Every path in the line (root, log, PATH) is single-quoted, with embedded `'` escaped
  as `'\''`. A path containing `%` or a newline is refused (exit 2) and the message names it, because
  cron turns `%` into a newline before the shell ever sees it.
- **FR-04** Before `crontab` is touched (install and `--dry-run`), the command part of the line is
  syntax-checked with `/bin/sh -n`. A line that fails the check is not installed: exit 1, the line
  and the shell's error are printed, and the crontab stays as it was.
- **FR-05** The install message lists which of dotnet, node, npm, npx, docker and timeout/gtimeout
  resolve on the captured PATH and which do not, and says to re-run the installer after installing a
  toolchain.
- **FR-07** The cron command stays within BSD/macOS cron's 999 characters (`MAX_COMMAND` 1000,
  read by `get_string`, which drops the rest without a word). A longer command is refused, exit 2,
  and the message names the limit. This is why the PATH is in a file: a developer PATH alone is
  ~1,900 characters on this machine.
- **FR-06** `--list` marks any of our lines that carries no `PATH=` as stale: it runs under cron's
  bare PATH and should be reinstalled.

## Acceptance

- AC1 the installed line, run by `/bin/sh -c` under `env -i PATH=/usr/bin:/bin`, finds a tool that
  was only on the install-time PATH.
- AC2 the log opens with a `claude-nightly: start` line and ends with `claude-nightly: end exit=0`.
- AC3 a moved root (cd fails) still writes the start line and a non-zero `end exit=` to the log.
- AC4 a root containing a space and a `'` installs, parses, and cd's into the right directory.
- AC5 a root containing `%` is refused with exit 2; the crontab is unchanged.
- AC6 a failing `sh -n` (stubbed parse shell) refuses with exit 1; the crontab is unchanged.
- AC7 a relative and an empty PATH entry are dropped; duplicates appear once.
- AC8 the install message names a tool missing from the captured PATH.
- AC9 `--list` flags a legacy line without `PATH=` as stale, and does not flag a new one.
- AC10 re-install replaces this project's line (one line, not two) and keeps an unrelated line.
- AC11 `--remove` removes only this project's line, and its PATH file.
- AC12 the command fits in 999 characters; a root that pushes it past is refused (exit 2, names 999),
  crontab unchanged.
- AC13 a deleted PATH file → maintenance does not run, the log ends with a non-zero `end exit=`.

## Clarifications

### Session 2026-09-30

- Q: Crontab-wide `PATH=` variable or per-command? → A: Per-command. A crontab-wide assignment would
  change the developer's own jobs.
- Q: Hard-code tool directories (Homebrew, ~/.dotnet)? → A: No. Capture the installer's PATH; it is
  the one the developer's tools already work under, on every platform and version manager.
- Q: Refuse install when a tool is missing? → A: No, report it. A project may not use dotnet or
  docker at all, and the maintenance run already says what it skipped.
- Q: PATH inline in the line or in a file? → A: A file. Found during implement: the inline line was
  ~1,900 characters and BSD cron truncates at 999, which reproduces F086 exactly while `sh -n` passes
  the untruncated text. The file keeps the line short on every machine.
- Q: How is the `sh -n` check tested when the generator never produces a bad line? → A: A seam,
  `NIGHTLY_PARSE_SHELL` (default `/bin/sh`), set by the test to a stub that fails.

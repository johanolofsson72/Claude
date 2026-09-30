# Spec interview — 065-nightly-cron-line-runs-blind

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. Spec-only, no hardening trigger (no new surface, no entity, three files), so no overflow.

## Q1 — Scope boundary
**Q:** What is in, what is out?
**A (auto):** In: PATH capture, log-first heartbeat, quoting, `sh -n` pre-check, tool report, stale-line flag in `--list`. Out: the Windows `schtasks` branch, log rotation, alerting when a run fails.

## Q2 — Primary actor
**Q:** Who is hurt today?
**A (auto):** A developer who installed the nightly job. Every run fails on a missing tool, or never runs, and the log cannot tell which (fundit F084/F086).

## Q3 — Happy path
**Q:** What does done look like?
**A (auto):** The installed line finds the same dotnet/node/docker as the install shell, and every run that fires leaves a start and an end line in the log.

## Q4 — PATH scope
**Q:** Crontab-wide `PATH=` or per command?
**A (auto):** Per command. A crontab-wide line would change the developer's own jobs.

## Q5 — PATH source
**Q:** Capture the installer's PATH or hard-code known tool directories?
**A (auto):** Capture. It covers Homebrew, ~/.dotnet, nvm, asdf and Linux without a list to maintain.

## Q6 — PATH hygiene
**Q:** What happens to empty, relative and duplicate entries?
**A (auto):** Empty and relative entries are dropped, because they would resolve against the cron cwd. Duplicates are removed and order is kept.

## Q7 — Log-first
**Q:** How does a run that fails early still show up?
**A (auto):** `exec >'LOG' 2>&1` comes first in the line, then a start heartbeat with `date`. The end line records the exit code.

## Q8 — Parse failure
**Q:** How is a line that cannot parse prevented?
**A (auto):** `/bin/sh -n -c` on the command part before `crontab` is written. On failure: exit 1, print the line and the error, leave the crontab alone.

## Q9 — The `%` trap
**Q:** What about `%` in a path?
**A (auto):** Refuse with exit 2 and name the path. Cron turns an unescaped `%` into a newline, `sh -n` never sees that, and escaping it is not portable across cron implementations.

## Q10 — Quoting
**Q:** How are spaces and quotes in paths handled?
**A (auto):** Single-quote every path, and escape an embedded `'` as `'\''`. A newline in a path is refused, the same as `%`.

## Q11 — Missing tools
**Q:** Should install fail when dotnet or node is not on the captured PATH?
**A (auto):** No. Report found/missing per tool and tell the developer to re-run after installing one. Projects differ in which tools they need.

## Q12 — Existing installs
**Q:** What about lines installed before this fix?
**A (auto):** `--list` marks our lines without `PATH=` as stale and says to reinstall. Re-install replaces them, because the marker is unchanged.

## Q13 — Error semantics
**Q:** Which exit codes?
**A (auto):** Bad input (`%`, newline, bad `--at`) → 2. The line fails `sh -n` or crontab refuses → 1. No crontab → 3, unchanged.

## Q14 — Test seam
**Q:** How is the `sh -n` refusal tested?
**A (auto):** `NIGHTLY_PARSE_SHELL` (default `/bin/sh`). The test points it at a stub that fails. The test also stubs `crontab` to a file, so it never touches the real crontab.

## Q15 — Acceptance
**Q:** What proves it?
**A (auto):** AC1-AC11 in spec.md, in a new `scripts/test-install-nightly-maintenance.sh`, red on HEAD for the fixed behaviours. AC1 executes the installed line under `env -i` with cron's PATH.

## Q16 — Reversibility
**Q:** Rollback story?
**A (auto):** `--remove` is unchanged. Reverting the script and re-installing gives the old line back.

## Q17 — Sync
**Q:** Does the new test reach projects?
**A (auto):** Yes. It joins `install-nightly-maintenance.sh` in the template-autosync core list.

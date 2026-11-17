# Spec interview — 107-maintenance-report-honesty

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. Spec-only, not hardened (four production scripts, no risk domain), so no overflow.

## Q1 — Scope boundary
**Q:** What is in, what is out?
**A (auto):** In: F180, F181, F191, F200, F201, F202, F204, F224, F225 as the row names them. Out:
settings-guard false positives (row 108), mutation tooling (row 109), register/lane tooling (row 110).

## Q2 — Primary actor
**Q:** Who is hurt today?
**A (auto):** The developer reading a `--full --suite` pass, attended or from the nightly log. Each
of the four defects makes the report say less than the pass measured.

## Q3 — Which failure lines does R1 quote?
**Q:** Which suite output lines count as failure lines?
**A (auto):** Lines starting `FAIL`, `TIMEOUT`, `not ok` (TAP), and `Failed ` after leading
whitespace (dotnet test). Jest prints `FAIL path`, which the first pattern covers. Nothing broader,
so a test that prints the word "fail" is not quoted.

## Q4 — Cap on quoted failure lines
**Q:** How many failure lines are quoted?
**A (auto):** 40, then `… and N more failure line(s)`. A 95-script suite that fails wholesale should
not turn the report into the suite log.

## Q5 — Keep the tail?
**Q:** Does the tail stay when failure lines are quoted?
**A (auto):** Yes, the last 12 lines under `last lines:`. The tail carries the summary line
(`suite: N scripts`, dotnet's `Failed! - Failed: 3`).

## Q6 — How does an interrupted pass report?
**Q:** Stream to stdout, or trap and flush?
**A (auto):** Both. Each entry goes to a partial file as it happens, and a TERM/INT/HUP trap prints the
buffer. Streaming to stdout would break the report's shape (count header first), and `--quiet`
relies on printing nothing when clean.

## Q7 — Partial file location
**Q:** Where does the partial file live?
**A (auto):** `<git-dir>/maintenance-report.partial`, beside `claude-trusted-commands`. It is never
committed and never synced, and a worktree has its own.

## Q8 — Interrupted exit code
**Q:** What does an interrupted pass exit with?
**A (auto):** 128 + the signal number (143 for TERM), the shell convention, so `timeout` callers and
cron see a signal death, not a finding count.

## Q9 — Does an interrupted pass stamp?
**Q:** Does anything get stamped before the stop?
**A (auto):** No. Stamps run after the verdict, and the trap exits before that. The message says so.

## Q10 — Mutation bound default
**Q:** What is the default mutation bound?
**A (auto):** 7200 s. The longest measured runner pass is fundit's 41 min. agentcrm's bare run passed
four hours and was not going to finish. Override with `MAINTENANCE_MUTATION_TIMEOUT`.

## Q11 — Mutation with no timeout binary
**Q:** With neither `timeout` nor `gtimeout`, what runs?
**A (auto):** A project runner runs (it bounds itself by contract), with a note. Bare
`dotnet stryker` / `npx stryker run` are refused as a finding. The unbounded bare tool is the
documented five-hour runaway (fundit 2026-09-08).

## Q12 — Mutation timeout outcome
**Q:** What does a mutation run cut off by the bound report?
**A (auto):** `[MUTATION] UNMEASURED`, a finding, not stamped, so the job stays due. It never reads
as a failed gate or a crash.

## Q13 — Ratchet streak cap
**Q:** After how many consecutive exit-77 passes does a ratchet become a finding?
**A (auto):** 5 by default (`MAINTENANCE_RATCHET_ABSENT_CAP`). A nightly pass makes that a working
week with the precondition absent every time.

## Q14 — Ratchet streak reset
**Q:** What resets the streak?
**A (auto):** Any outcome other than 77: pass, fail or timeout. A skip marker does not touch it,
since that ratchet was never started.

## Q15 — Ratchets under --unattended without a bound
**Q:** Should the nightly run ratchets unbounded?
**A (auto):** No. It runs none and reports one finding. Attended runs keep running with the existing
note, since a developer at a terminal can stop a hung one.

## Q16 — Duplicate scan scope in the pass
**Q:** Should the pass keep scanning `~/repos/*/` as well as this project?
**A (auto):** No, this project only (`--dir "$PWD"`). Cross-project pairs belong to the manual
run. Including them would put other projects' open rows in this project's findings.

## Q17 — Meaning of --open-only
**Q:** Change the flag or add a new one?
**A (auto):** Redefine `--open-only` to "pairs with at least one open row". The pass is the only
caller, and the old meaning answers a question nobody asks (two open rows duplicating each other is
a subset of the new set).

## Q18 — Error/empty states
**Q:** What does each new path say when there is nothing to say?
**A (auto):** No failure lines → today's tail. No git dir → no partial file, streak untracked
(note). No open rows → the scan reports no pairs. Zero ratchets → no ratchet note.

## Q19 — The mod files' mode bits
**Q:** Does the agent set +x on the two mod files?
**A (auto):** No. The mod guard (095a) refuses any agent write to a mod installer. The status
summary gives the developer the one `!` command.

## Q20 — Tests
**Q:** Where do the tests go, and do they need Ollama?
**A (auto):** `[107]` cases in test-project-maintenance.sh for R1–R5a (stubbed similarity, suite,
stryker and ratchets). R5b's pair filter is a pure function, tested without Ollama. One live case
runs when Ollama is up.

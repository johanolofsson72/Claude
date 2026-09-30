# Spec interview — 067-traceability-walk-races-test-results

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. Spec-only, no hardening trigger (one script and its harness, no new surface, no entity), so no overflow.

## Q1 — Scope boundary
**Q:** What is in, what is out?
**A (auto):** In: refusing a walk that errored; pruning Playwright's other outputs; harness cases and sabotage arms. Out: retrying the walk automatically, locking the tree, changing the exit-code table.

## Q2 — Primary actor
**Q:** Who is hurt today?
**A (auto):** A developer or Claude reading the gate while a test run writes under the roots (fundit F116). They see seven "uncovered" rows that are a race.

## Q3 — Happy path
**Q:** What does done look like?
**A (auto):** A racing or unreadable walk prints a refusal naming the errors, exit 4; a quiet tree prints the same report as today.

## Q4 — Detection signal
**Q:** How does the script know the walk was partial?
**A (auto):** `scan.err` is non-empty. `find` and `grep` both already write there since 044; the signal exists and is ignored.

## Q5 — Exit code
**Q:** Which exit code?
**A (auto):** 4, the existing "references unreadable" code (see Clarifications).

## Q6 — Vanished files
**Q:** Is a file that vanished between `find` and `grep` harmless?
**A (auto):** No. It proves the tree changed during the walk; refuse.

## Q7 — Guard placement
**Q:** Before or after the zero-ids guard?
**A (auto):** Before. An errored walk is refused whatever it found; the zero-ids guard then only sees clean walks, which is its 044 meaning.

## Q8 — Error message content
**Q:** What does the refusal print?
**A (auto):** Error count, first 10 lines, files read per root, and the rerun advice naming a test run as the usual cause.

## Q9 — Prune list
**Q:** Which extra directories?
**A (auto):** `blob-report`, `allure-results`, `.nyc_output`. Unambiguous tool output only.

## Q10 — `coverage/`
**Q:** Prune it?
**A (auto):** No; could be a real test folder, no sighting.

## Q11 — Stdout vs stderr
**Q:** Where does the refusal go?
**A (auto):** stderr, like the other exit-4 refusals.

## Q12 — Concurrency
**Q:** Anything to lock?
**A (auto):** No. The gate is read-only; the fix is to report the race, not prevent it.

## Q13 — Error / empty / loading states
**Q:** The four states for a CLI?
**A (auto):** Success: report, exit 0/1/6. Error: named refusal on stderr, exit 4. Empty: the 044 zero-ids refusal, unchanged. Loading: none, a sub-second script.

## Q14 — Testing a race deterministically
**Q:** How do tests reproduce a race?
**A (auto):** With `chmod 000` on a directory and on a file. Both produce the same `scan.err` lines a vanished path does, deterministically. Skipped as inconclusive when running as root (root reads anything).

## Q15 — Id literals in fixtures
**Q:** Any constraint on the harness?
**A (auto):** Ids built from `$P` at runtime, never literal (case15 enforces it).

## Q16 — Portability
**Q:** Platform constraints?
**A (auto):** bash 3.2, BSD and GNU find/grep, Git Bash. `-name` prune only; no new flags.

## Q17 — Reversibility
**Q:** Rollback story?
**A (auto):** Reverting the commit restores the old behaviour; no data changes.

## Q18 — Acceptance
**Q:** What proves it?
**A (auto):** AC1-AC5 in `spec.md` as harness cases, red on HEAD first, plus sabotage arms.

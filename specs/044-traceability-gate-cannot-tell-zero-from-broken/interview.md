# Spec interview — 044-traceability-gate-cannot-tell-zero-from-broken

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. No overflow: no auth, PII, upload, new external surface, state machine or entity. The script reads and reports; it writes nothing.

## Q1 — Scope boundary
**Q:** What is in, what is out?
**A (auto):** In: the zero-ids refusal, the captured scan stderr, printing the extractor's refused rows, the harness arms. Out: the fundit root cause, scenario-map-rows.sh, project-maintenance.sh.

## Q2 — Primary actor
**Q:** Who is hurt today?
**A (auto):** A developer reading `coverage: 0 of 182` who starts hunting 182 missing tests when the scan failed, and a developer told a map was partly unreadable with no handle on which rows.

## Q3 — Happy path
**Q:** What does done look like?
**A (auto):** The fundit shape exits 4 and names the roots and file counts. The agentcrm F316 shape prints `file:line` for each refused row and the count.

## Q4 — The trigger condition
**Q:** Exactly when does the gate refuse?
**A (auto):** When at least one row claims ✓ or ◐ and the de-duplicated reference set is empty after every root is scanned.

## Q5 — Map claiming nothing
**Q:** Refuse when nothing is claimed?
**A (auto):** No. With nothing claimed there is no catastrophic report, and an all-☐ roadmap is a legitimate state (case5's argument).

## Q6 — Exit code
**Q:** New code or 4?
**A (auto):** 4. Its meaning is "I could not look", and project-maintenance.sh already maps it to "could not run". A new code would fall into the same catch-all anyway.

## Q7 — Out-of-range ids
**Q:** A scan that found only spec-criteria ids (out-of-range): refuse?
**A (auto):** No. Any kept id proves the scan read files. Only a truly empty set is the broken-scan signature.

## Q8 — Scan stderr
**Q:** Where does the scan's error output go?
**A (auto):** Into a temp file, printed (first lines) only inside the refusal. The normal report is unchanged.

## Q9 — File counts
**Q:** How are files counted without a second walk?
**A (auto):** The find output is teed to a list per root and counted by NUL bytes. One walk, as before.

## Q10 — Error state: the refusal text
**Q:** What does the refusal say?
**A (auto):** That no scenario id was found under the roots while the map claims M rows; each root with its file count; the scan's errors if any; rerun, check the roots; and that a suite citing no id at all leaves every claim unbacked.

## Q11 — Error state: partial read
**Q:** What does a partial read print?
**A (auto):** The extractor's own stderr lines (each naming file:line), then a line with the refused count that points above only when lines exist.

## Q12 — Extractor stderr on a clean read
**Q:** Print extractor warnings at exit 0 too (a whole file read as commentary)?
**A (auto):** Yes. They describe rows the gate cannot see, and dropping them is the same silence. Stderr, so the stdout report is unchanged.

## Q13 — Empty state
**Q:** A root that exists but holds no files?
**A (auto):** Counted as 0 files in the refusal. That is exactly the handle a reader needs.

## Q14 — Concurrency
**Q:** Anything order-dependent?
**A (auto):** No. The fundit flip (0 then 175) suggests files changing mid-scan; the refusal makes that rerunnable rather than believable. No locking.

## Q15 — Volume
**Q:** How much stderr is printed?
**A (auto):** The first 10 lines of scan errors, with a count of the rest. Every refused map row, because each one is a row lost from the check.

## Q16 — Sabotage
**Q:** How is the guard proven load-bearing?
**A (auto):** A marked region `zero-refs-guard`, a harness arm that deletes it and requires the new case to go red, and case1-clean surviving it.

## Q17 — Reversibility
**Q:** Rollback?
**A (auto):** One CORE script and its harness; revert the commit and the next sync restores the old reporting.

## Q18 — Acceptance
**Q:** How is it proven?
**A (auto):** New cases red on HEAD and green after, all existing cases green, the sabotage arm red, and the suites of the callers (maintenance, core-gates) green.

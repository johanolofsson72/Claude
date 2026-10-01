# Spec interview — 020-quality-gate-hooks-unwired-for-latency-we-no-longer-pay

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. Hardened by size; the overflow (O1-O4) went to the developer, two of them threat surface.

## Q1 — Scope boundary
**Q:** Does 020 wire any hook back into settings.json?
**A (auto):** No. In-session latency and memory were the reason they came out; 020 moves them to the night.

## Q2 — Scope boundary
**Q:** Which hooks?
**A (auto):** The 15 file-triggered advisory hooks named in spec.md. Bash-triggered ones have no file to replay; humanize, todo-catalog, task-traceability and allium-openq are covered by other machinery.

## Q3 — Primary actor
**Q:** Who runs the bench and the pass?
**A (auto):** The pass: `project-maintenance.sh --full` (nightly via install-nightly-maintenance.sh, or by hand). The bench: a developer, on `--bench-quality-gates`.

## Q4 — Happy path
**Q:** What does success look like?
**A (auto):** The table says which hooks are worth reading; at 02:30 those run on the day's changes; the morning banner says how many flags there are and where.

## Q5 — Data model
**Q:** Where does the verdict live?
**A (auto):** `scripts/quality-gates.tsv`, tracked and CORE, so every project inherits the measured verdicts; a re-bench rewrites it in a diff.

## Q6 — Data model (corpus)
**Q:** How is a true flag told from a false one?
**A (auto):** A seeded defect has a marker word; a flag line naming it is a catch. Any flag line on a clean file is a false flag.

## Q7 — Validation
**Q:** What if a hook prints a flag line without its marker on a bad file?
**A (auto):** Not a catch. It flagged something, but not the seeded defect; counting it would reward noise.

## Q8 — Observable states
**Q:** What do the scripts print?
**A (auto):** Success: per-hook line / report path. Error: the hook that failed and its exit. Empty: "no changed files since <sha>". No model: one line, nothing changed (AC-4).

## Q9 — Error semantics
**Q:** A hook that times out on one file?
**A (auto):** Counted as a miss on a bad file, no flag on a clean one, and its 120 s in the median. A slow hook earns `off` by the latency rule.

## Q10 — Concurrency
**Q:** Two passes at once?
**A (auto):** A lock directory under `.claude/state/quality-gates/`; the second exits with a line saying one is running.

## Q11 — Integration
**Q:** Does the pass go through local-llm-call.sh?
**A (auto):** Yes, by running the real hook scripts, so telemetry, caching and model choice are the ones in-session use had.

## Q12 — Integration (cache)
**Q:** local-llm-call caches by prompt. Does the bench measure cache hits?
**A (auto):** No. The bench sets a throwaway LOCAL_LLM_CACHE_DIR so every call reaches the model.

## Q13 — Edge cases
**Q:** Deleted or binary files in the changed set?
**A (auto):** Skipped: only regular text files that still exist at HEAD.

## Q14 — Non-functional
**Q:** How long may the bench take?
**A (auto):** ~60 calls; at the measured 2-16 s per call, under 15 minutes. It is opt-in for that reason.

## Q15 — Acceptance
**Q:** How is 020 accepted?
**A (auto):** Its four developer-confirmed cases, each named by a test in test-quality-gates.sh, plus a real bench run on this machine whose table is committed.

## Q16 — Reversibility
**Q:** How is it turned off?
**A (auto):** Set every verdict to `off`, or drop `--full`'s step with `QUALITY_GATES=off`. No state outside `.claude/state/`.

## O1 — Acceptance cases (overflow, developer)
**Q:** Confirm AC-1..AC-4.
**A:** Confirmed as written.

## O2 — Verdict rule (overflow, developer)
**Q:** When does a hook earn the nightly run?
**A:** Every seeded defect caught, at most one clean file falsely flagged, median ≤ 60 s.

## O3 — Banner text (overflow, developer, threat surface: disclosure + injection)
**Q:** What does the morning banner carry?
**A:** Count and path only; it never quotes model output, so a file attempting prompt injection cannot reach a session through SessionStart.

## O4 — Limits (overflow, developer, threat surface: resource exhaustion)
**Q:** Caps on the nightly pass?
**A:** 50 files, 30,000 bytes per file, 120 s per call; an over-cap file is listed as skipped, never silently dropped.

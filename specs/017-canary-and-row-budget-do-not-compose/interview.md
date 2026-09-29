# Spec interview — 017-canary-and-row-budget-do-not-compose

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO (base auto-answered with the recommended option). No hardened trigger fires (no entity,
no auth/PII/upload, no concurrency, five files), so there are no overflow questions. Q3 was the only
candidate for escalation. It has a conservative answer that builds nothing irreversible, so it was
auto-answered and the alternative was recorded as a finding.

## Q1 — Scope boundary
**Q:** Does this spec shrink any project's register?
**A (auto):** No. It changes what the canary says. Moving agentcrm's prose is agentcrm's own edit.

## Q2 — Scope boundary
**Q:** Is the scenario-map half of the canary touched?
**A (auto):** No. Row 008 already gave the map its own remedy. This spec handles `INDEX.md` only.

## Q3 — Scope boundary
**Q:** msroute's bytes are compliant ticked rows. Does this spec build a fold that moves them out?
**A (auto):** No. 13 consumers count ticked rows in `INDEX.md` (next-register-id, the checkpoint cadence, register-convergence, maintenance-due, spec_active.py and others). A fold changes their input and is full-track work. The canary stops pretending a move exists, and the fold is recorded as a finding with that evidence.

## Q4 — Primary actor & trigger
**Q:** Who is hurt, and when?
**A (auto):** The developer and the model at every SessionStart on a register over 25 KB. They get a canary whose advice cannot be taken, and `project-maintenance.sh` reports a red verdict nobody can clear.

## Q5 — Happy-path outcome
**Q:** What does success look like?
**A (auto):** The canary names the part holding the bytes and the one move that shrinks it. When no move exists it says so in one line and stays out of attention mode.

## Q6 — Data model
**Q:** What are the parts?
**A (auto):** rows (every status row plus its indented continuation lines), history (the `## Register history` section), prose (everything else), and total. Each has bytes and an integer share.

## Q7 — Validation rules
**Q:** What counts as a row?
**A (auto):** A line matching `^- \[[ x/!]\]`, the same grammar as `spec_active.py` and the archiver. Indented non-blank lines directly after it belong to it. A blank line or an unindented line ends it.

## Q8 — Validation rules
**Q:** What is the prose threshold?
**A (auto):** 4096 bytes, absolute. Measured: template preamble ~1.2 KB, msroute 2.4 KB (legitimate), agentcrm 33 KB.

## Q9 — The four observable states
**Q:** What does each state look like at SessionStart?
**A (auto):** Under 25 KB: silent (unchanged). Over with a move: attention-mode canary with a breakdown and moves. Over and compliant: one info line and no attention mode. Helper missing or failing: the old wording, so the canary is never silenced by a partial sync.

## Q10 — Error semantics
**Q:** What does the helper do with a missing file or a bad argument?
**A (auto):** Exit 1 for a missing file and exit 2 for usage, each with a message on stderr. It never prints a partial breakdown.

## Q11 — Authorization
**Q:** Any authorization surface?
**A (auto):** None. It is a read-only local script.

## Q12 — Concurrency / ordering
**Q:** Ordering concerns?
**A (auto):** Moves are printed largest part first, with ties broken in a fixed order (rows, history, prose), so the output is deterministic and testable.

## Q13 — Integration points
**Q:** What consumes the helper?
**A (auto):** `spec-register-orientation-hook.sh` and `project-maintenance.sh`, both CORE. So the helper goes into `CORE_SCRIPTS`, and `core-gates.sh` classifies its self-test as a gate automatically.

## Q14 — Edge cases
**Q:** A register with no history heading, or no rows?
**A (auto):** The part is 0 bytes with 0 entries, and there is no move for it. A file of only prose over 4 KB gets the prose move.

## Q15 — Edge cases
**Q:** Is CRLF counted?
**A (auto):** Bytes are bytes. `wc -c` semantics, CR included. The regexes tolerate a trailing CR.

## Q16 — Non-functional limits
**Q:** Cost at SessionStart?
**A (auto):** One awk pass, milliseconds on a 360 KB register. No python, no git.

## Q17 — Acceptance criteria
**Q:** How is "the advice follows the measurement" proven?
**A (auto):** Fixture registers in the canary test: prose-heavy → the prose move and no `archive-completed-rows`; compliant row-heavy → no attention mode, the info line, and a clean maintenance verdict. Plus the live measurements on agentcrm and msroute.

## Q18 — Non-goals & assumptions
**Q:** Is the 300-byte budget or the 25 KB threshold changed?
**A (auto):** No. Both stay. The spec is about composing them, not moving either.

## Q19 — Reversibility
**Q:** Rollback story?
**A (auto):** Revert the commit. The helper is additive, and both consumers fall back to the old wording without it.

## Q20 — Portability
**Q:** Does it run under Git Bash and BSD userland?
**A (auto):** POSIX awk only (no gawk extensions), and `LC_ALL=C` so `length()` counts bytes. `validate-portability.sh` must be clean.

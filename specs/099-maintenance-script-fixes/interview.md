# Spec interview — 099-maintenance-script-fixes

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. No overflow: light track, no hardened trigger (no auth, PII, upload, new external
surface, state machine, concurrency or entity; five scripts plus moved rule text). Every question
below had a defensible recommendation.

## Q1 — Scope boundary
**Q:** What is in, what is out?
**A (auto):** In: F166–F169 as R1–R4, plus git-ignoring TLC state directories (R5), which 098 left
committed. Out: argument or probe markers for ratchets, depth acceptance, a lower cap, editing
ighweld's own ratchets or CLAUDE.md, rewriting register rows.

## Q2 — Primary actor
**Q:** Who is hurt today?
**A (auto):** The developer reading a maintenance report in a synced project (ighweld first). They
get two false ratchet failures, an undecidable carve warning and an unfixable budget overrun every
pass. Then an agent shortening register rows, trusting an "all archived" that was not true.

## Q3 — How a ratchet says "not here" (F166)
**Q:** Exit code, header marker, or probe command?
**A (auto):** Exit 77, the automake/TAP SKIP code. The ratchet knows its own precondition. A
marker-declared probe would make maintenance evaluate header text as a command, which is a new
execution surface with no benefit. The existing `# maintenance: skip` stays for "never here".

## Q4 — Is a 77 silent? (F166)
**Q:** Does a precondition skip vanish from the report?
**A (auto):** No. It joins the existing "ratchets skipped by their own marker" note, worded
"precondition absent (exit 77)" plus its last output line. A skip is never silent: the 052 rule.

## Q5 — Timeout versus 77 (F166)
**Q:** What if the ratchet times out?
**A (auto):** Unchanged: 124 under timeout is "timed out". Only a real exit 77 is a skip.

## Q6 — Unattended and untrusted (F166)
**Q:** Does exit 77 change the trust path?
**A (auto):** No. An untrusted ratchet is still not run under `--unattended`, so it never gets to
exit at all. 77 is read only after a trusted run.

## Q7 — Acceptance marker location (F167)
**Q:** Where does the developer record a decided carve excess?
**A (auto):** A header line in `specs/INDEX.md`, like `Freeze:`. One place both lanes and every
hook read. Per-row text would be lost when ticked rows are shortened to pointers.

## Q8 — Acceptance marker format (F167)
**Q:** What exactly is the line?
**A (auto):** `Carve accepted: <id>=<n>[, <id>=<n>…] · <YYYY-MM-DD> · <why>`. The count binds the
decision to what was decided. Several lines are allowed, one per decision.

## Q9 — Carving past the accepted count (F167)
**Q:** 097 is accepted at 3 and carves a 4th. What happens?
**A (auto):** It is over again, and the report says "accepted 3 on <date>, now 4". A decision
about three rows is not a licence for a fourth.

## Q10 — Malformed acceptance line (F167)
**Q:** A line starts `Carve accepted` but does not parse. Ignore it?
**A (auto):** Fail the audit (exit 1) and name the line. Ignoring it would silently keep a warning
the developer thinks they cleared, or worse, look like a clearing that never happened. Fail fast.

## Q11 — Depth acceptance (F167)
**Q:** Can a depth-3 chain be accepted too?
**A (auto):** No. carve-budget.md section 3 says there is no depth 3 and section 5 makes it a
convergence stop. Only the budget, which section 2 calls a ceiling with a decision attached.

## Q12 — Budget target (F168)
**Q:** How small must the template's rules be?
**A (auto):** ≤ 23,552 bytes (23 KB) for the always-loaded rules. ighweld's own CLAUDE.md plus
.claude/CLAUDE.md is 17,053 bytes, so 23,552 + 17,053 = 40,605 fits the 40,960 cap with room.
The cap itself stays at 40 KB.

## Q13 — What may move out of a rule (F168)
**Q:** Which text leaves the rule files?
**A (auto):** Examples, category lists, format illustrations and explanation, moved verbatim into
the rule's existing `-rationale.md`, with a pointer left behind. Every BLOCKING contract line, every
"Forbidden" item and every hook or script name a reader needs in order to act stays.

## Q14 — Which project is "synced" (F168)
**Q:** How does context-budget.sh know a project's rules belong to the template?
**A (auto):** `.claude/.template-sync` exists. template-autosync writes it in every synced project;
the template has none.

## Q15 — Synced over-budget message (F168)
**Q:** What does a synced project see when over the cap?
**A (auto):** The rules' total as template-owned ("trimmed in the template, a sync overwrites a
local edit"), the project's CLAUDE.md share, and the room left for it (cap − rules). Exit 1 as before.

## Q16 — Archived means what (F169)
**Q:** When is a ticked row archived?
**A (auto):** When its current text is in INDEX.completed.md verbatim. A heading alone proves only
that someone once wrote about that id.

## Q17 — Rows shortened after archiving (F169)
**Q:** A row was archived long and later shortened to a pointer. Its pointer text is not in the
archive. Append it too?
**A (auto):** Yes. It costs one short entry, once, and the rule then holds without heuristics:
every ticked row's text is preserved before anyone edits it again. Telling a shortened pointer from
a lost diagnosis would need a guess.

## Q18 — Where the appended copy goes (F169)
**Q:** Insert under the existing heading, or append at the end?
**A (auto):** Append at the end under a new `## <id> — <slug>` heading, like every other entry.
The script never edits earlier archive text: the archive is append-only.

## Q19 — Report wording (F169)
**Q:** What does a run say?
**A (auto):** "archived N row(s): A new, B whose text changed since their entry", listing the ids.
It says "all archived" only when every ticked row is verbatim-present. `--dry-run` says "would".

## Q20 — Four observable states
**Q:** Success, error, empty, loading?
**A (auto):** CLI scripts. Success: the report line and exit code per requirement. Error: a named,
specific message (a malformed `Carve accepted` line, a missing archive file). Empty: no ratchets,
no acceptance lines, no ticked rows, each a normal pass. Loading: N/A, synchronous.

## Q21 — Reversibility
**Q:** Undo story?
**A (auto):** Everything is git-tracked. The archive append is visible in `git diff`. An acceptance
line is deleted to withdraw it. Moved rule text is in the rationale docs, word for word.

## Q22 — Acceptance / verification
**Q:** How is done measured?
**A (auto):** One self-test arm per requirement in the existing suites (test-project-maintenance,
test-register-convergence, test-context-budget, test-archive-completed-rows). The F169 arm uses the
real shape from ighweld: a heading holding a `[/]` pre-tick form. The template's own totals are
measured, and every touched suite runs green.

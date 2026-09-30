# Spec interview — 049-a-held-row-cannot-be-written-to

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. Spec-only, no hardening trigger, so no overflow.

## Q1 — Scope boundary
**Q:** What is in, what is out?
**A (auto):** In: `--spec <id>` in the run-log hook, a `--id` lookup in `spec_active.py`, hint text on
the implicit failure paths, the rule's usage line, tests. Out: which row the implicit path picks,
the orientation hook's run-log tail.

## Q2 — Primary actor
**Q:** Who is hurt today?
**A (auto):** An agent or developer who has just held or ticked a row and wants the reason on disk
before `/clear`. ighweld hit it twice (F139, F195) and wrote the file by hand.

## Q3 — Happy path
**Q:** What does done look like?
**A (auto):** `spec-run-log-hook.sh --note "held: waiting on X" --spec 049` appends one line to
`specs/049-*/run-log.md` whether the row is `[ ]`, `[/]`, `[!]` or `[x]`, exit 0, no output.

## Q4 — Why not change the implicit resolution?
**Q:** Should the implicit path prefer a held row?
**A (auto):** No. A register keeps old holds (020 and 075 here), so a held-first rule would send
every note to the oldest hold. The two questions stay separate: the implicit path answers "which row
should I work?", and `--spec` answers "which row is this about?".

## Q5 — Data shape of the id lookup
**Q:** What does `spec_active.py --id` return?
**A (auto):** One JSON object: `id`, `dir` (relative to root), `found`, `status` (the row marker or
null). Same style as the resolver's existing output, so the shell caller parses `dir` the same way.

## Q6 — Validation
**Q:** Which tokens count as an id?
**A (auto):** Exactly what `classify_id` accepts: numeric (`049`, `007m`, `501.1`) or letter-led
(`H1`, `H6s2`). A malformed token is refused, never truncated or globbed loosely.

## Q7 — Directory versus id precedence
**Q:** `--spec X` where X is both an existing directory and a well-formed id?
**A (auto):** The directory wins. That keeps every existing call working unchanged (FR-04).

## Q8 — Error semantics
**Q:** Which exit codes?
**A (auto):** 0 recorded; 2 malformed id (caller's fault); 4 well-formed id with no directory, or a
resolver that cannot answer. The codes are the ones the hook already uses.

## Q9 — The four observable states
**Q:** Success, error, empty, loading?
**A (auto):** Success is silent, exit 0. Every error names what is missing on stderr. Empty is "no
active row": exit 3, now with the `--spec <id>` hint. There is no loading state because this is a
synchronous CLI.

## Q10 — Authorization / lanes
**Q:** Can `--spec <id>` write to the other lane's row?
**A (auto):** Yes. Naming the id is explicit, and the lane rule covers ticking and starting a row,
not writing a note on it.

## Q11 — Concurrency
**Q:** Two notes at once?
**A (auto):** Unchanged. `append_line` appends one line with `>>`. Nothing about the new lookup adds
shared state.

## Q12 — Edge: id not in the register
**Q:** An id with a directory but no row?
**A (auto):** Allowed, `status: null`. The note needs the directory, and a row may have been archived.

## Q13 — Edge: two directories for one id
**Q:** `specs/049-a` and `specs/049-b`?
**A (auto):** First in sorted order, the same as `resolve()`, since both use one shared function.
Not a new rule.

## Q14 — Edge: `.specify/specs/`
**Q:** Is the spec-kit location searched?
**A (auto):** Yes, second, as the resolver already does.

## Q15 — Hint content
**Q:** What does the failure hint say?
**A (auto):** One extra clause: `a held or ticked row is named with --spec <id>`, plus
`held: 020, 075` when there are any. No hint on the happy path.

## Q16 — Non-functional
**Q:** Performance?
**A (auto):** One python3 start, the same as the implicit path. It is a hand-typed CLI, not a hot path.

## Q17 — Acceptance criteria
**Q:** What proves it?
**A (auto):** Tests in `test-pipeline-hooks.sh`: a note lands on a `[!]` row and a `[x]` row by id;
an unknown id exits 4 and names it; a malformed id exits 2; an existing dir still wins; the implicit
failure paths carry the hint; the happy path stays silent. Plus `test-active-spec-resolution.sh` arms
for `--id`. Each new arm has to fail on HEAD.

## Q18 — Reversibility
**Q:** Rollback story?
**A (auto):** Additive: a new flag value form and a new resolver mode. Reverting the commit restores
the old behaviour. No data changes.

## Q19 — Non-goals and assumptions
**Q:** What is assumed?
**A (auto):** The directory is named `<id>-<slug>`, the same assumption every resolver caller makes.
Misfiling onto an N+1 row that already has a directory stays possible. It is documented, not fixed.

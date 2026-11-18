# Spec interview — 110-register-lane-tooling

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. Spec-only, not hardened (read-path corrections in existing scripts plus one opt-in
allocator input, no trust boundary), so no overflow.

## Q1 — Scope boundary
**Q:** What is in, what is out?
**A (auto):** In: the eleven findings on the row. Out: renumbering collisions already in projects,
register row ids, any network claim protocol.

## Q2 — Primary actor
**Q:** Who is hurt today?
**A (auto):** Two developers sharing one register (agentcrm), and any project whose register is not
in tick order (rocky). Each defect makes a number or a "next row" answer wrong without an error.

## Q3 — Collision-free design
**Q:** Lane prefix, date prefix, fetch-before-allocate, or numeric stripes?
**A (auto):** Numeric stripes keyed by a per-machine slot. Prefixes break every `F[0-9]+` reader;
a fetch cannot see unpushed work; stripes cannot overlap by construction.

## Q4 — Default behaviour
**Q:** What happens on a single-lane project?
**A (auto):** Nothing changes. With no `SPEC_LANE_SLOT`, the allocator returns max + 1 as today.

## Q5 — Stripe width
**Q:** Block size for findings and for scenario ids?
**A (auto):** 1 for findings (they are drawn one at a time), 100 for scenario ids (a spec takes a
block of 10–40). `next-scenario-id.sh --block` overrides.

## Q6 — Run larger than a block
**Q:** `--count 150` with a 100-id block under a slot?
**A (auto):** Exit 2 with the reason and the `--block` hint. Silently spanning two lanes' blocks
would reintroduce the collision.

## Q7 — Bad slot value
**Q:** `SPEC_LANE_SLOT=3/2` or `abc`?
**A (auto):** Exit 2 naming the variable and the value. A silent fallback to max + 1 is the old
collision with no sign.

## Q8 — Duplicate gate
**Q:** Build a new SC duplicate gate?
**A (auto):** No: `validate-scenario-traceability.sh` exits 6 on agentcrm today with 143 named. Pin
the split-layout case with a test so it cannot regress.

## Q9 — Which checkpoint is "since"
**Q:** Highest H number or newest tick date?
**A (auto):** Highest H number. The number is written on the row and does not depend on history;
the date decides only which feature rows count after it.

## Q10 — Tick time source
**Q:** How is "ticked after" decided?
**A (auto):** One `git log --reverse -p` pass over `specs/INDEX.md`: the first commit that adds a
`- [x] <id> ` line. Position in the log is the order. No repository → file order (today's reading).

## Q11 — Row ticked in the checkpoint's own commit
**Q:** Does it count?
**A (auto):** No, only strictly after. A checkpoint covers what was done before and with it.

## Q12 — Owner tag grammar
**Q:** What is a tag?
**A (auto):** `@name` preceded by whitespace or an em dash and followed by whitespace or end of line;
the last one wins. An email address is not a tag.

## Q13 — Same rule in all three readers?
**Q:** Fix only `lane_status.py` as F210 names?
**A (auto):** All three. The orientation hook and `spec_active.py` read the same tag; disagreeing
readers of one row are the defect class this repo keeps removing.

## Q14 — Phase-debt cleared mark
**Q:** Parse the Cleared column or look for `☑`?
**A (auto):** `☑` anywhere in the row, exactly as the banner does, so the two numbers agree.

## Q15 — Archive identity
**Q:** Compare by id only?
**A (auto):** By id, plus length: an archived ticked line for the id that is at least as long as the
current row. A row that grew after archiving is still appended, so nothing new is lost.

## Q16 — Pre-tick headings (row 099)
**Q:** Does a `## <id>` heading with a `- [/]` line count as archived?
**A (auto):** No. Only a `- [x] <id> —` line counts, which keeps ighweld F169's protection.

## Q17 — Slug outside specs/
**Q:** A `plan.md` outside `specs/`?
**A (auto):** Old reading (parent directory). Only paths with a `specs/<dir>/` component change.

## Q18 — CORE list source
**Q:** Where does `context-budget.sh` learn which rules are CORE?
**A (auto):** `template-autosync.sh --list-core-rules`, the sibling script. No second copy of the
list. If it cannot answer, fall back to today's message.

## Q19 — Paren form false positives
**Q:** Can `Foo_SC040(` admit shellcheck codes?
**A (auto):** It still needs a non-alphanumeric char before `SC`; `disable=SC2086` has `=` before it
but no `(` after. A shellcheck code followed by `(` in source has never been seen; the existing
negative cases stay in the suite.

## Q20 — Verification
**Q:** What proves it?
**A (auto):** Each script's own suite gains cases (R10), the full template suite runs green, and the
fixed readers are re-run on agentcrm and rocky read-only to compare the numbers in the findings.

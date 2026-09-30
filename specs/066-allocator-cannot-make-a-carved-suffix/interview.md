# Spec interview — 066-allocator-cannot-make-a-carved-suffix

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. Spec-only, no hardening trigger (one script, no new surface, no entity), so no overflow.

## Q1 — Scope boundary
**Q:** What is in, what is out?
**A (auto):** In: a `--suffix <parent>` form on `next-register-id.sh`, its tests, the rule/rationale pointer. Out: renumbering existing carved rows, changing the id grammar, enforcing carve depth.

## Q2 — Primary actor
**Q:** Who is hurt today?
**A (auto):** Claude or a developer carving a row. The rule forbids picking ids by eye, and for carved ids eye is the only allocator (fundit H3, 2026-09-27).

## Q3 — Happy path
**Q:** What does done look like?
**A (auto):** `bash scripts/next-register-id.sh --suffix 015` prints `015a` (or the next free letter) and that id is free everywhere.

## Q4 — Flag name
**Q:** `--suffix`, `--carve` or `--child`?
**A (auto):** `--suffix`, the name the diagnosis proposes. It says what it does to the id, not why.

## Q5 — Letter choice
**Q:** Lowest free letter or the one after the highest used?
**A (auto):** After the highest used. The numeric and alpha forms append; a retired `005b` must not be handed out again.

## Q6 — Case
**Q:** Upper or lower case letters?
**A (auto):** Lowercase. `spec_active.py`'s numeric grammar only accepts `[a-z]*` after the digits. Uppercase already in the register counts as taken.

## Q7 — Multi-letter children
**Q:** Does `007ch` block a letter on `007`?
**A (auto):** No. It is a child of `007c`. Only `<parent><one letter>` counts.

## Q8 — Depth-2 carve
**Q:** What does `--suffix 007c` return?
**A (auto):** `007c` plus the next letter, e.g. `007ci`. That is how the register already names depth-2 carves (`007ch`). Depth is recorded by attribution, not by the allocator.

## Q9 — Unknown parent
**Q:** Parent id not in the register or archives?
**A (auto):** Exit 2 and name it. Fail fast; a typo would otherwise produce an orphan id.

## Q10 — Malformed parent
**Q:** A parent that is not an id at all?
**A (auto):** Exit 2 with a usage message, before reading the register.

## Q11 — Exhaustion
**Q:** What happens past `z`?
**A (auto):** Exit 2, nothing on stdout. No wrap to `aa`: that is a different parent's namespace.

## Q12 — Flag conflict
**Q:** `--suffix` with `--alpha` or `--checkpoint`?
**A (auto):** Exit 2. Last-flag-wins would silently answer a different question.

## Q13 — Where "used" comes from
**Q:** Which files count?
**A (auto):** Same as today: rows in `INDEX.md` at any status, rows and `## ` headings in every `INDEX*.md` sibling.

## Q14 — Count
**Q:** Does `--count` work with `--suffix`?
**A (auto):** Yes, consecutive free letters. All-or-nothing: fewer than N free exits 2.

## Q15 — Error / empty / loading states
**Q:** Four observable states for a CLI?
**A (auto):** Success prints ids, exit 0. Error prints a named reason on stderr, exit 2. Empty (no register) is the existing exit 2. No loading state for a sub-second script.

## Q16 — Portability
**Q:** Platform constraints?
**A (auto):** bash 3.2 + python3, as today. No GNU-only flags. Must run under Git Bash.

## Q17 — Reversibility
**Q:** Rollback story?
**A (auto):** Additive flag. Reverting the commit restores the old behaviour; no data changes.

## Q18 — Acceptance
**Q:** What proves it?
**A (auto):** AC1-AC13 in `spec.md`, in `scripts/test-next-register-id.sh`, red on HEAD first.

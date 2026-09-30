# 066 — allocator-cannot-make-a-carved-suffix

Track: spec-only. No entity, no state machine, no new surface. Touches `scripts/next-register-id.sh`,
its test `scripts/test-next-register-id.sh`, and the one-line pointers in
`.claude/rules/spec-register.md` and `.claude/docs/spec-register-rationale.md`. No hardening trigger.

Evidence: fundit F095 (2026-09-09); fundit H3 picked `015a`/`015b` by eye on 2026-09-27.
Diagnosis in `specs/INDEX.pending.md`.

## The defect

Carved rows take the parent's id plus a lowercase letter (`002a`, `015b`, `007ch`, `H7u`). The
allocator has no form for that shape. `--alpha 005` treats `005` as a series prefix and returns
`0051`, so the one id shape carving produces is the one shape still picked by eye.

## Requirements

- **FR-01** `--suffix <parent>` returns `<parent><letter>` with the next free lowercase letter.
  Append, not fill-the-gap: the letter after the highest one already used on that parent, the same
  rule the numeric and `--alpha` forms follow.
- **FR-02** "Used" means what it means for the other forms: every row in the register at any status
  and every row or `## ` heading in every `INDEX*.md` sibling. A letter used in either case (`002A`)
  counts as taken.
- **FR-03** Only single-letter children of the parent count. `007ch` is a child of `007c`, not of
  `007`; `--suffix 007` ignores it.
- **FR-04** The parent must be an id the register or an archive knows. An unknown parent exits 2
  and names it. A typo'd parent would otherwise make up an orphan id.
- **FR-05** A malformed parent (`x y`, `005-`) exits 2 through FR-04: it can never be a known row.
  A missing parent argument exits 2 with its own message. (A separate grammar check was dropped in
  simplify: mutation showed FR-04 already refuses everything it refused.)
- **FR-06** `--count N` returns N consecutive free letters. Past `z` it exits 2 and says the letters
  ran out; it never wraps and never returns a partial list.
- **FR-07** `--suffix` together with `--alpha` or `--checkpoint` is a usage error (exit 2), not a
  silent pick of whichever came last.
- **FR-08** The help text, the rule line in `spec-register.md` and the rationale doc name the form.

## Acceptance

- AC1 `--suffix 005` on a register with `005` returns `005a`.
- AC2 with `005a` and `005c` present it returns `005d` (append past the highest letter).
- AC3 a `005b` that exists only in an `INDEX*.md` archive counts as taken.
- AC4 a ticked `005a` counts as taken.
- AC5 `--suffix 007` ignores `007ch` and returns the letter after `007c`.
- AC6 `--suffix H7` with `H7u` present returns `H7v`.
- AC7 `--suffix 999` on a register without `999` exits 2 and names `999`.
- AC8 `--suffix 'x y'` or `--suffix 005-` exits 2.
- AC9 `--suffix 005 --count 3` returns three distinct consecutive free ids.
- AC10 with `005z` present, `--suffix 005` exits 2 and prints nothing on stdout.
- AC11 `--suffix 005 --alpha S` exits 2.
- AC12 every returned id is free in its register and parses under the numeric grammar of
  `scripts/spec_active.py`.
- AC13 an uppercase `005A` counts as taken.

## Clarifications

### Session 2026-09-30

- Q: Should a letter-ending parent (`007c`) be refused? → A: No. The register already names depth-2
  carves that way (`007ch`, `H7u` under `H7`); refusing would push those back to picking by eye.
- Q: Should the parent's existence be checked against archives too? → A: Yes. A carve from a row
  that has moved to `INDEX.completed.md` is still a carve from a real row.

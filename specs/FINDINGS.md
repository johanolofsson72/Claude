# Findings

Things the pipeline found that are NOT yet register rows, and may never be.

A spec records what it found here and keeps going. Every 5 ticked specs these are presented as one
batch and the developer decides per finding: fix it now, make it a row, or drop it. That review is
the only thing that grows the register — see `.claude/rules/carve-budget.md`.

This file is git-tracked on purpose: a finding one lane records is one the other must see.

Status: `[ ]` open · `[x]` decided (the decision is on the line)

## Open

- [ ] F001 — gap — 2026-09-10 — nothing verifies that a user-global hook command actually resolves: superpowers' hooks.json carried a literal ${CLAUDE_PLUGIN_ROOT} and failed at every session start and /clear, in every project, unnoticed since February
- [ ] F002 — defect — 2026-09-11 · from spec 045 — four register rows (036, 042, 043, 044) exceed the 300-byte row budget; 043 and 044 need an INDEX.pending.md entry before they can be shortened

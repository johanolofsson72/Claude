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
- [ ] F003 — gap — 2026-09-12 · from spec 046 — project-authored hooks are invisible to every template gate: rocky's two SC-id guards carried the same inert-deny defect as the six CORE guards, and nothing in --owed, --unlisted or test-hook-channels could see them because they are not CORE. The fleet sweep that found them was written by hand.
- [ ] F004 — gap — 2026-09-12 · from spec 046 — the template ships test-coverage-hook.sh, a PostToolUse hook whose name matches the scripts/test-*.sh gate convention. Any aggregate runner globbing that pattern picks it up and hangs on cat waiting for hook JSON. consultpilot's run-gates.sh carries a hand-written exclusion for exactly this at line 159; nothing in the template warns the next project.
- [ ] F005 — gap — 2026-09-18 — ighweld F047: the scenario-traceability gate cannot credit a scenario proven by a script-level self-test; scripts/ is not listable as a root without admitting source comments as proof. Relates to rows 012/013.
- [ ] F006 — gap — 2026-09-18 — ighweld F068 (reference): a contrast check built on getComputedStyle mis-measures colour-mix() backgrounds. Chromium returns color(srgb 0-1 components), and an rgb() parser reads them as near-black. It produced a confident, wrong 'passes AA 6.36:1' for a 2.83:1 badge. Belongs in testing docs.
- [ ] F007 — gap — 2026-09-18 — ighweld F182: a security-scanner subagent reported spec 160 as entirely unimplemented while all of it was on disk and green. It read a stale or different tree. Agent reviews need a check that they are looking at HEAD.

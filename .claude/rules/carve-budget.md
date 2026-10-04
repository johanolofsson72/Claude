# Carve budget rule (the register has to converge)

Every other rule pushes toward creating rows. This one says when to stop. A **carve ratio** (rows added ÷ rows ticked) above 1.0 grows the backlog without bound. Long form (measurements, the `H7` cascade, the full pre-081 and pre-099 text): `.claude/docs/carve-budget-rationale.md`.

## The contract (BLOCKING)

1. **A finding is recorded, not rowed:** `bash scripts/finding.sh --add "<one line>" --spec NNN --kind gap` writes `specs/FINDINGS.md`. Disposition, in order: fix it inside the current spec when that is smaller than recording it; record it (the default); carve a row now only for work that blocks the next spec. A wanted row is a **proposal** with its need: `--propose-row --need "<who is hurt, where seen>"`.
2. **Every 5 ticked specs** the developer decides the open findings as one batch: fix, row or drop. Only that review grows the register (`scripts/register-similarity.sh --text "<row>"` is a report there). `SPEC_CARVE_BUDGET` (default 2) caps immediate carves; an ordinary spec carves **zero**. A decided excess is recorded once by the developer: `Carve accepted: <id>=<n> · <date> · <why>` in `specs/INDEX.md` (rationale §8).
3. **Carve depth stops at 2.** Mark it on the row: `— carved by H7u (d2)`. Depth 3 is a convergence stop.
4. **Harness defects** (`.claude/**`, `scripts/**`, hooks, skills) go to the template's register; a product register carries only the standing `T0 — harness-defects` row. One blocking the current spec is fixed in place AND filed in the template, same commit.
5. `scripts/register-convergence.sh` (`--carves`, `--freeze`) measures ratio and depth. A ratio **≥ 1.3 over 10+ ticked rows** is a **convergence stop**: finish the spec, report ratio, open rows then and now, heaviest carvers, deepest chain; offer **1. Freeze**, **2. Batch** open spec-only rows, **3. Cut** named rows.
6. **Freeze** is one header line: `Freeze: since <date> · last row <id> · lifts below <N> open`. While it holds, the only way in is a proposal approved at a spec stop (`finding.sh --review --proposals`, `--approve N` / `--decline N "<why>"`), and the row carries `approved F<nnn>`.
7. **Deleting a row is allowed**, with a one-line Register history entry naming it and why.

## Forbidden

Turning a finding into a row on the spot. Treating the 2-carve ceiling as an allowance. A third carve from one spec without folding. Depth 3. A harness defect on a product register as anything but `T0`. Continuing past a diverging ratio without telling the developer. "The finding was real" as the reason for a row. Writing a `Carve accepted` line the developer did not decide.

Surfacing is governed by `.claude/rules/validation-followup.md`; this rule governs rowing.

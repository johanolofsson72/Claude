# Carve budget rule (the register has to converge)

Every other rule pushes toward creating rows. This one says when to stop. A **carve ratio** (rows added ÷ rows ticked) above 1.0 grows the backlog without bound. Long form (measurements, the `H7` cascade, the full pre-081 text): `.claude/docs/carve-budget-rationale.md`.

## The contract (BLOCKING)

1. **A finding is recorded, not rowed:** `bash scripts/finding.sh --add "<one line>" --spec NNN --kind gap` writes to `specs/FINDINGS.md`. Disposition, in order: (1) fix it inside the current spec when that is smaller than recording it; (2) record it, which is the default; (3) carve a row now, the exception, only for work that blocks the next spec. A row someone wants is a **proposal** with its need: `--propose-row --need "<who is hurt, where seen>"`.
2. **Every 5 ticked specs** the open findings are reviewed as one batch, and the developer decides each one: fix, row or drop. Only that review grows the register. Run `bash scripts/register-similarity.sh --text "<row>"` there (a report, never a gate). `SPEC_CARVE_BUDGET` (default 2, 0 is legitimate) caps immediate carves. It is a ceiling, not an allowance; an ordinary spec carves **zero**.
3. **Carve depth stops at 2.** Mark it on the row: `— carved by H7u (d2)`. Depth 3 is a convergence stop.
4. **Harness defects** (`.claude/**`, `scripts/**`, hooks, skills) go to the template repo's register. A product register carries only the standing `T0 — harness-defects` row. If one blocks the current spec, fix it in place AND file the template row in the same commit.
5. `scripts/register-convergence.sh` (`--carves`, `--freeze`) measures the ratio and the depth. A ratio **≥ 1.3 over 10+ ticked rows** is a **convergence stop**: finish the current spec, then report the ratio, open rows before and now, the heaviest carvers and the deepest chain, and offer: **1. Freeze** carving, **2. Batch** the open spec-only rows into one, **3. Cut** named rows. The developer decides.
6. **Freeze** is one header line in `specs/INDEX.md`: `Freeze: since <date> · last row <id> · lifts below <N> open`. While it holds, the only way in is a proposal the developer approved at a spec stop (`finding.sh --review --proposals`, then `--approve N` / `--decline N "<why>"`). Such a row carries `approved F<nnn>`.
7. **Deleting a row is allowed**, with a one-line Register history entry naming it and why.

## Forbidden

Turning a finding into a row on the spot. Treating the 2-carve ceiling as an allowance. A third carve from one spec without folding. Depth 3. A harness defect on a product register as anything but `T0`. Continuing past a diverging ratio without telling the developer. "The finding was real" as the reason for a row.

Surfacing is governed by `.claude/rules/validation-followup.md`; this rule governs rowing.

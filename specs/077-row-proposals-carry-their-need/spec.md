# 077 — row proposals carry their need

Track: spec-only [hardened]. No entity, no state machine, no external surface. Hardened by the size
trigger (six or more files), so it gets the four additions, scaled to local shell tooling.
Requested by the developer 2026-09-29.

## Problem

The register was diverging at 3.80 (38 rows added against 10 ticked). On 2026-09-29 the developer
answered the convergence stop with a **freeze**: no new rows until fewer than 40 are open. Two things
are missing:

1. Nothing knows the freeze exists. The SessionStart banner keeps asking for "the three ways out",
   and a row added during the freeze looks like any other row.
2. A finding that someone thinks should become a row arrives as one line of text. Whether the need
   is real is left for the developer to reconstruct. Nothing checks for an existing row that already
   covers it, or for a cited file that has since disappeared.

The developer asked for the pipeline to report and validate the need behind every proposed row, and
to present it so each one can be approved or declined.

## Requirements

- R1 The register header line `Freeze: since <date> · last row <id> · lifts below <N> open · ...`
  is the freeze. `register-convergence.sh --freeze` reads it and prints one line. Exit 1 when there
  is no freeze, 0 when frozen and clean, 2 when frozen and a row with a numeric id above `last row`
  lacks `approved F<nnn>`, and 3 when open rows are below the target (the freeze can lift). H rows
  are exempt because the checkpoint cadence mandates them.
- R2 The orientation hook replaces the convergence-stop banner with a freeze banner while the freeze
  is on, names any unapproved rows, and says when the freeze can lift.
- R3 `finding.sh --add TEXT --propose-row --need EVIDENCE` records kind `proposal` with
  `need: EVIDENCE` on the line. `--propose-row` without `--need` is refused with exit 2 and the
  reason.
- R4 `finding.sh --review [--proposals]` prints each open finding with its age and need. It then
  runs three checks: the closest open row by word overlap (reported when the overlap is 0.25 or
  more), every cited path that does not exist in this repo, and a verdict. For proposals the verdict
  is `evidenced`, `no evidence`, `possible duplicate of <id>` or `cites a missing file`. The header
  shows the freeze state and the open-row count.
- R5 `finding.sh --approve N` resolves the finding as approved and prints the next row id plus the
  `approved F<nnn>` tag the row must carry. `--decline N REASON` resolves it as declined, and a
  missing reason is refused.
- R6 `spec-register.md`: the status summary gains `Row proposals:`, and the per-spec stop presents
  that spec's proposals (from `--review --proposals`) with `AskUserQuestion`, Approve or Decline per
  proposal. `carve-budget.md` records the freeze mechanism and the proposal form.

## Developer decisions (2026-09-29)

- An approved proposal becomes a row immediately. Approval is the gate; the freeze stops only
  unapproved rows.
- Proposals are presented at every spec stop. Plain findings still wait for the 5-spec review.
- Enforcement is report plus flagged violations, with no deny hook. Row 029 shows PreToolUse denies
  are inert under bypass permissions.

## Threat model

Local scripts that read and write git-tracked markdown. Trust boundary: text in FINDINGS.md and
INDEX.md, which another lane may have written.
- S: none. There are no identities, and approval is a local command the developer runs.
- T: a row can fake `approved F012` without an F012 decision. Mitigation: `--freeze` counts a tag as
  valid only when F<nnn> is resolved as approved in FINDINGS.md.
- R: decisions are appended to the finding line and committed, so git is the audit trail.
- I: none.
- D: a very large FINDINGS.md makes review quadratic in rows × findings. At 11 findings × 52 rows
  that is negligible; noted, not mitigated.
- E: finding text is passed to python as argv or environment and never evaluated. Paths are checked
  with `os.path.exists` under ROOT only. `..` segments are refused so a citation cannot probe outside
  the repo.

## Non-goals

Fixing F-id collisions across lanes (row 054). Semantic duplicate search, which stays with
`register-similarity.sh`. A deny hook.

## Acceptance

`test-finding.sh` and `test-register-convergence.sh` pass with new cases for R1, R3, R4 and R5,
including sabotage arms. The orientation hook shows the freeze banner on this repo. A review agent
pass gets explicit decisions.

## Clarifications

### Session 2026-09-29

- Q: approval vs freeze → A: row immediately (developer).
- Q: cadence → A: every spec stop (developer).
- Q: enforcement → A: report + flag (developer).

### Review round 2026-09-29 (adversarial + code review + independent security review)

- R1 changed: "added during the freeze" means any id missing from the register at the OLDEST commit
  that carries `Freeze: since <date>`. Suffixes (077b), non-numeric ids and ids below `last row` are
  all caught. Outside git it falls back to the number. One approval admits one row, and only an
  approved *proposal* counts. A crash exits 4, never 1. Two freeze lines, or a near-miss, exit 4.
- R1 new exit code: 5 means cannot evaluate (no engine, no register, no python3). The hook falls
  through to the convergence banner on 5. On 4 it says "fix the line" and does not claim a freeze.
- Hardening: newlines in text are stripped, `--kind` is validated, `APPROVE`/`DECLINE` are never
  inherited from the environment, and review output is stripped of control characters. Absolute
  paths, `~` and symlinked citations are refused. Decided findings cannot be re-decided.
- 074 follow-up: peak RSS is the process tree, sampled once a second, not the largest single child.

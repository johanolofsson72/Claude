# Acceptance cases — 020-quality-gate-hooks-unwired-for-latency-we-no-longer-pay

**Confirmed:** 2026-10-01 · 26ccd5f2b709 — "Confirmed as written"

Drafted by Claude, confirmed by the developer through AskUserQuestion. Tests name a case as
`020-AC-<n>`.

## AC-1 — The bench scores a hook
**Given** a hook's corpus with 2 seeded-defect files and 2 clean files
**When** the bench runs
**Then** quality-gates.tsv shows its caught/bad, false/clean and median seconds, and the verdict follows the rule

## AC-2 — Only passing hooks run at night
**Given** a table where test-realism is nightly and test-name is off
**When** the nightly pass runs over yesterday's changed test file
**Then** only test-realism's flags appear in latest.md

## AC-3 — Flags reach the morning
**Given** a latest.md with 3 flags
**When** the next session's maintenance banner prints
**Then** it says "quality gates: 3 flags from <date>" and names the file

## AC-4 — No model, no noise
**Given** Ollama is unreachable
**When** the bench or the pass runs
**Then** nothing is scored, the table keeps its last numbers, `last` does not move, and one line says the model was unreachable

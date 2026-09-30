# 052 — maintenance-runs-what-it-finds

Track: spec-only. No entity, no state machine. Two files plus this spec: `scripts/project-maintenance.sh`
and its test. No hardening trigger fires.

Evidence: ighweld-2026, 2026-09-18 (F062 and the dead-solution run). Diagnosis in `specs/INDEX.pending.md`.

## The defect

**Ratchets.** Projects add `scripts/check-*.sh` ratchets (ighweld has 13, fundit 5, agentcrm 3), and
nothing runs them. `project-maintenance.sh` does not know they exist, so a ratchet only runs when
somebody remembers it, and eventually nobody does.

**Build target.** With nothing declared, `--suite` falls back to `dotnet test` and `--full` to
`dotnet stryker`, both run from the repo root. When the root holds a stale solution, they build that
one. On ighweld the root `IGHWeld.Web.sln` pointed at deleted projects, and both steps failed with
MSB3202 while the real `src/welding/Welding.sln` was 7478/0 green. Row 051 added
`.claude/.suite-command` for the suite, but the undeclared fallback still takes whatever is at the root.

## Requirements

- **FR-01** Every pass runs each `scripts/check-*.sh` from the repo root with no arguments and stdin
  closed. A non-zero exit is a `[RATCHET]` finding naming the script, its exit code and the tail of
  its output. A green ratchet says nothing (attention mode).
- **FR-02** Each ratchet is bounded by `MAINTENANCE_RATCHET_TIMEOUT` seconds (default 300) through
  `timeout` or `gtimeout`. A ratchet that runs out of time is a `[RATCHET]` finding saying so. When
  neither binary exists, ratchets run unbounded and the pass notes that once.
- **FR-03** A ratchet opts out with a `# maintenance: skip <reason>` line in its first 30 lines.
  Skipped ratchets are listed in a note along with their reasons. A marker with no reason is
  ignored: the ratchet runs, and a note says why.
- **FR-04** When `--suite` would fall back to a detected `dotnet test` and the project holds more than
  one solution (`*.sln` / `*.slnx`, depth ≤ 3, outside `node_modules`), nothing runs. It is a
  `[SUITE]` finding that lists the solutions and names `.claude/.suite-command`, and nothing is stamped.
- **FR-05** When `--full` would fall back to a bare `dotnet stryker` under the same condition, nothing
  runs. It is a `[MUTATION]` finding that lists the solutions and names `scripts/run-mutation-gate.sh`,
  and nothing is stamped.
- **FR-06** A declared suite command or a project-owned mutation runner bypasses FR-04 and FR-05. One
  solution, or none, behaves as it does today.
- **FR-07** The usage header documents the ratchet step, the skip marker and the timeout variable.

## Acceptance

- AC1 a failing ratchet → `[RATCHET]` naming it, its exit code and its output; verdict red.
- AC2 a passing ratchet → no finding, no line; verdict green.
- AC3 a hanging ratchet under a 1-second limit → `[RATCHET]` timed out.
- AC4 a skip marker with a reason → not run, and the note names the reason.
- AC5 a skip marker with no reason → runs anyway, and the note says the marker was ignored.
- AC6 no `check-*.sh` → no ratchet output at all.
- AC7 ighweld shape (root dead `.sln` plus `src/x/Real.sln`, nothing declared) with `--suite` →
  `[SUITE]` naming both solutions and `.claude/.suite-command`, dotnet never invoked, not stamped.
- AC8 the same shape with `.claude/.suite-command` → runs the declaration, stamps on green.
- AC9 the same shape with `--full` and no runner → `[MUTATION]` naming both solutions and
  `scripts/run-mutation-gate.sh`, dotnet never invoked, not stamped.
- AC10 one solution → unchanged (C14-C87 stay green).

## Out of scope

Validating that a lone root solution's project references exist (dotnet reports MSB3202 on its own,
and the run fails red today). A shipped `check-all.sh` (the maintenance pass is the runner). A
mutation-command declaration file (051 already made `scripts/run-mutation-gate.sh` that declaration).

## Clarifications

### Session 2026-09-30

- Q: Run every `check-*.sh`, or only declared ones? → A: Every one, with a reasoned opt-out. The row's point is that a ratchet nobody remembers still runs. A declaration list would reproduce the forgetting one level up.
- Q: A separate `check-all.sh`? → A: No. It would be one more CORE file with its own sync and parity ceremony, doing what one loop in the maintenance pass already does.
- Q: A solution count > 1 with nothing declared — refuse or run the root one? → A: Refuse and name both declarations. A red suite over a stale solution is the failure this row records.

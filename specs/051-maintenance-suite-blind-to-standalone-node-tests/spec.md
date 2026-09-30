# 051 — maintenance-suite-blind-to-standalone-node-tests

Track: spec-only. No entity, no state machine. Three files: `scripts/project-maintenance.sh`, its
test, and this spec. No hardening trigger fires.

Evidence: emaljen F027 (bare `node tests/*.mjs`, no `package.json`, suite stamped by hand) and
iskvalp 2026-09-25 (jest in `client/package.json`, root has only `iskvalp.sln`, `--suite` ran
`dotnet test` alone and stamped the whole obligation green). Diagnosis in `specs/INDEX.pending.md`.

## The defect

`project-maintenance.sh --suite` knows two stacks: a root `package.json` `test` script and a .NET
solution. Anything else prints "nothing to run", so `suite` can never be discharged through the
command meant to discharge it. Worse, a detected stack is treated as the whole suite even when a
second test surface sits next to it, and the obligation ("unit + integration + E2E + visual
regression") is stamped over a half run. `--full` is also silent when no mutation runner exists
for the stack, so a PHP or bare-node project hears nothing about its mutation gap.

## Requirements

- **FR-01** `.claude/.suite-command` declares the suite: its first line that is neither blank nor a
  `#` comment. When present it is the command `--suite` runs, ahead of every detected stack.
- **FR-02** A declared command is judged like a detected one: exit code plus `run-verdict.sh`
  (abort → not stamped). Nobody second-guesses what a human declared, so there is no evidence gate.
- **FR-03** The report names the provenance: `declared in .claude/.suite-command` vs detected.
- **FR-04** When `dotnet test` is the DETECTED command and a nested `package.json` (depth ≤ 3, not
  under `node_modules`) carries a `test` script, a green run is **not stamped**. It becomes a
  `[SUITE]` finding naming the uncovered file(s) and telling the developer to declare the whole
  suite. A red or aborted run reports as before.
- **FR-05** With nothing declared and nothing detected, the note points at `.claude/.suite-command`.
  If `.claude/.template-sync-verify` declares a command, the note quotes it as a candidate but
  never runs it: that file may declare a unit-only slice, and running it here would stamp a half
  suite (the iskvalp failure).
- **FR-06** `--full` with no mutation runner for the stack says so as a note (not stamped, as
  today) and names the declaration: a project-owned `scripts/run-mutation-gate.sh` printing
  `mutation score N%`.
- **FR-07** The usage header documents `--suite` and `.claude/.suite-command`.

## Acceptance

- AC1 declared command runs and stamps on green, even with a `.sln` present (the declared-outranks-detected case).
- AC2 declared command red → `[SUITE]`, not stamped. Declared abort → not stamped.
- AC3 comments and blank lines before the command are skipped.
- AC4 iskvalp shape (sln + `client/package.json` test, no declaration) → green dotnet run not stamped, finding names `client/package.json`.
- AC5 the same shape WITH a declaration → stamped (the finding is the nudge, the declaration the fix).
- AC6 emaljen shape (only `tests/*.mjs`) → note names `.claude/.suite-command`, nothing stamped, exit 0.
- AC7 `.template-sync-verify` present, nothing else → quoted as a candidate, never executed.
- AC8 `--full` with no mutation runner → note names `scripts/run-mutation-gate.sh`.
- AC9 C37-C39 unchanged.

## Out of scope

Shipping a PHP/node mutation runner (stack-specific, not CORE). Reading `.template-sync-verify`
as the suite. Changing the `npm test` + .NET note, where `npm test` may call `dotnet test`.

## Clarifications

### Session 2026-09-30

- Q: Should `.template-sync-verify` stand in when `.suite-command` is absent? → A: No. It is often a unit slice by design (its own example is a unit csproj); quote it, never run it.
- Q: Refuse to run, or run and not stamp, on the iskvalp shape? → A: Run and not stamp. The dotnet result is still information; only the stamp is false.
- Q: Evidence gate for a declared command? → A: No. Same rule as `template-sync-verify.sh`: a declaration is never second-guessed; the abort gate still applies.

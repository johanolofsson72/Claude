# Spec interview — 051-maintenance-suite-blind-to-standalone-node-tests

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. Spec-only, no hardening trigger, so no overflow.

## Q1 — Scope boundary
**Q:** What is in, what is out?
**A (auto):** In: a declared suite command, the half-suite stamp on the iskvalp shape, the
nothing-detected note, the silent mutation gap on `--full`, and tests. Out: a shipped PHP/node mutation runner.

## Q2 — Primary actor
**Q:** Who is hurt today?
**A (auto):** A developer or agent on a project whose suite is not a root `npm test` or .NET. The
due banner never clears (emaljen), or it clears over a half run (iskvalp).

## Q3 — Happy path
**Q:** What does done look like?
**A (auto):** A one-line `.claude/.suite-command` makes `--suite` run the real suite and stamp it on green.

## Q4 — Data model
**Q:** Where does the declaration live and what shape is it?
**A (auto):** `.claude/.suite-command`, committed; first non-blank non-comment line. Same shape as `.template-sync-verify`, so there is one convention to learn.

## Q5 — Why not reuse `.template-sync-verify`?
**Q:** The diagnosis offers it as the fix. Use it?
**A (auto):** Quote it, never run it. Its own help text recommends a unit csproj, so as a suite it
would reproduce the half-suite stamp this spec exists to remove.

## Q6 — Precedence
**Q:** Declared vs detected?
**A (auto):** Declared wins, always (diagnosis: "a detected stack should not outrank a declared one").

## Q7 — Validation
**Q:** What does a malformed declaration do?
**A (auto):** An empty or all-comment file is no declaration and detection applies. No command parsing beyond that.

## Q8 — Four states
**Q:** Success / error / empty / in-progress?
**A (auto):** Green → note + stamp. Red → `[SUITE]` finding, not stamped. Nothing to run → note naming
the declaration, not stamped. Aborted → `[SUITE]` "ABORTED", not stamped. Every state names the command and where it came from.

## Q9 — Error semantics
**Q:** Is the iskvalp half-suite a finding or a note?
**A (auto):** A finding. A green half run that is not stamped must say why, or the job looks broken.

## Q10 — Authorization / trust
**Q:** Is running a command from a repo file a risk?
**A (auto):** `--suite` is an explicit developer invocation, the same trust as `template-sync-verify.sh`. No hook or SessionStart path runs it.

## Q11 — Concurrency
**Q:** Anything concurrent?
**A (auto):** No. One command, one run. N/A.

## Q12 — Integration points
**Q:** What else reads `suite`?
**A (auto):** `maintenance-due.sh --stamp suite` only. Its contract is unchanged.

## Q13 — Edge cases
**Q:** Nested package.json detection limits?
**A (auto):** Depth ≤ 3, `node_modules` pruned, root package.json excluded. A nested manifest
without a `test` script does not count. Only the dotnet-detected path refuses the stamp; a root `npm test` may drive workspaces.

## Q14 — Edge: emaljen with no declaration
**Q:** Should the note list the test files it sees?
**A (auto):** It names the declaration file and, when present, the `.template-sync-verify` candidate. Listing files adds noise.

## Q15 — Mutation gap
**Q:** Ship a PHP runner?
**A (auto):** No. The declaration mechanism exists (`scripts/run-mutation-gate.sh`, project-owned);
the defect is that `--full` says nothing when it is missing. Add the note.

## Q16 — Non-functional
**Q:** Cost?
**A (auto):** One `find` at depth 3 and one file read. Negligible.

## Q17 — Acceptance
**Q:** Measurable done?
**A (auto):** AC1-AC9 in spec.md, as arms in `scripts/test-project-maintenance.sh`, red on HEAD first.

## Q18 — Reversibility
**Q:** Rollback?
**A (auto):** Delete `.claude/.suite-command` and behaviour is the old detection, except the iskvalp shape now refuses the stamp. That refusal is the fix.

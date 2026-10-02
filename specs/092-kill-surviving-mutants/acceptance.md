# Acceptance cases — 092-kill-surviving-mutants

**Confirmed:** 2026-10-02 · 5424f49d7c62 — "Confirm"

Drafted by Claude, to be confirmed by the developer through AskUserQuestion. Tests name a case as
`092-AC-<n>`.

## AC-1 — A repository with no language marker is never gated
**Given** a git repository with a spec register whose active spec owes every artifact, and no package.json, *.csproj or *.sln anywhere above the edited file
**When** spec-interview-guard, pipeline-state-guard and spec-register-guard are asked about an edit of src/App.cs
**Then** spec-interview-guard and pipeline-state-guard answer no decision with exit 0, spec-register-guard does the same in that repository with its register removed, and one App.csproj beside the file turns each of the three into a deny

## AC-2 — A deny that exits non-zero is never read as a deny
**Given** a guard output carrying a well-formed PreToolUse deny
**When** hook_verdict reads it with exit code 1
**Then** the verdict is exit-1, not deny, and each spec-interview deny route (acceptance cases owed, malformed row id, resolver missing, python3 missing) is asserted as deny with exit 0

## AC-3 — Every survivor line is killed or justified
**Given** the 2026-10-02 survivor lines in template-autosync.sh, project-maintenance.sh, spec-interview-guard-hook.sh, guard-lib.sh, validate-scenario-traceability.sh and project-freshness.sh
**When** run-mutation-gate.sh --lines measures every site on them again
**Then** the score is at least 95%, no mutant is reported as a timeout, and any survivor left carries a mutant-equivalent reason on its line

## AC-4 — A hang is caught by the suite, not by the runner
**Given** a .secret-shapes-allow whose last line has no trailing newline
**When** project-freshness.sh reads it under the suite's own 20-second bound
**Then** the run finishes inside the bound with the allow entry applied, and a script that loops at EOF fails the case instead of timing out

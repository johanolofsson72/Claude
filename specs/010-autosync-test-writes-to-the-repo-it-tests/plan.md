# Plan — 010 autosync-test-writes-to-the-repo-it-tests

## Approach

Land consultpilot `95ba64a` (H7bm) onto this tree, hunk by hunk, re-measuring each hunk here instead
of trusting that it still applies. `git apply --check` against HEAD: 8 of 12 script hunks apply with an
offset. Two fail, both for known reasons:

- `template-autosync.sh` CORE_SCRIPTS: the list moved. Add the two new names by hand.
- `test-template-autosync-stranded.sh`: `9b0b5ad` already landed the `CLAUDE_PROJECT_DIR` half.
  Add only the sandbox half.

`run-gates.sh` does not exist in the template. Registration there belongs to row 014.

1. `template-autosync.sh`: env doc in the header, the fail-closed exception in the header, and the
   interlock block (`_phys`, `_within`, the empty / missing / `/` / outside refusals) between
   `PROJECT_ROOT` resolution and the `.claude/` check. Add both new scripts to CORE_SCRIPTS.
2. Drivers: add the declaration to all six. In `test-core-owed-tick-guard.sh`, `rc_of` becomes
   `run_sync`, which names the target, and the three bare `cd && bash "$SYNC"` sites go through it.
3. `core-owed-tick-guard-hook.sh`: `CLAUDE_PROJECT_DIR="$ROOT"` on both queries.
4. New: `validate-sync-sandbox-declarations.sh` and `test-validate-sync-sandbox-declarations.sh`,
   from `95ba64a`. Re-measure the EXCLUDED list against this tree and keep only the entries whose
   removal makes the gate report a false positive here.
5. Verify: the contained repro flips, all six drivers keep their counts, the six run with
   `CLAUDE_PROJECT_DIR` exported at a throwaway clone and the clone stays byte-identical, undeclared
   byte-identity against HEAD's script, the gate is clean, and the harness is green.
6. TLA+: port `SandboxInterlock.tla/.cfg`, run TLC with the `/` falsifying control.

## Risks

- Harness assumptions from consultpilot (paths, `run-gates.sh` references, SC ids) do not hold here.
  Read the whole harness before running it.
- consultpilot's local H7bo gate gets replaced on its next sync. Recorded as a finding for 011.
- Running any driver with an ambient `CLAUDE_PROJECT_DIR` pointed at the template itself is the
  incident. The ambient runs use a throwaway clone, never this checkout.

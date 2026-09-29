# Plan — 011 twenty-hand-written-sync-invocations

## Approach

Land consultpilot `5078ed1` (H7bo) onto this tree. The drivers are converted by hand, not copied,
because the template's copies moved on after consultpilot branched: spec 010's sandbox halves, the
unlisted AC-13 arm, and the tick-guard `[parity]` fix. consultpilot's own drivers were overwritten
by its next sync (F012), so `5078ed1` is the only source for the converted shapes.

1. `scripts/drive-sync.sh`: port as-is, then widen `drive_sync_readonly`'s proof from `--is-core` to
   the four query modes (R4). Strip the `Covers: SC-18xx` lines.
2. `scripts/validate-sync-sandbox-declarations.sh`: port the H7bo rule and scanner. Template changes:
   - the query-mode filter covers four modes;
   - the handle derivation matches values that end in `-autosync.sh` (R9);
   - EXCLUDED holds exactly 4 entries (R8);
   - the help-range `sed -n '2,76p'` becomes the self-delimiting form the 010 gate uses.
3. Six drivers: source the helper, route every sync call through `drive_sync` with
   `DRIVE_SYNC_SCRIPT`, and use `DRIVE_SYNC_CWD` / `DRIVE_SYNC_TIMEOUT` where the old call needed them.
   Keep 010's `[parity]` `CLAUDE_PROJECT_DIR` fix in the tick-guard test, since it drives the
   bash-write guard, not the sync. Keep the eol hook call hand-spelled (it drives the hook).
4. `scripts/test-drive-sync.sh`: port, and add read-only arms for the three extra query modes.
5. `scripts/test-validate-sync-sandbox-declarations.sh`: keep 010's interlock section (AC-13..AC-26,
   AC-31, AC-32) verbatim. Replace the gate arms with H7bo's (AC-01..AC-12, AC-27..AC-30). Keep
   010's AC-07b/AC-12b (query modes). Add H7bo's AC-31..AC-42 as AC-45..AC-56, the census (AC-37 →
   AC-57) and the per-driver arms (AC-36 → AC-58). Add F014 fixtures (AC-59), the exclusion-count pin
   and per-entry falsification (AC-60).
6. CORE_SCRIPTS gains `drive-sync.sh test-drive-sync.sh`.
7. Verify: both harnesses green, all arms red when sabotaged, six drivers at baseline counts, an
   ambient `CLAUDE_PROJECT_DIR` run against a throwaway clone leaves it identical, and the gate's time
   measured interleaved against the old gate.
8. TLA+: port OneWayIn with the query-mode proof and a contains-repo boolean. Two controls: the
   empty sentinel (from consultpilot), and a helper without the contains-repo check.
9. Hardened: threat model (in the spec), security-scanner in adversarial mode, and `/security-review`.

## Risks

- A driver whose sync call depends on `cd` for a relative path (stranded's `bash scripts/…`).
  `DRIVE_SYNC_SCRIPT` must be absolute. Otherwise the helper's default cwd (the project) is what
  resolves it, and a later cwd change would break it silently.
- The contains-repo refusal compares against the helper's own repo. A driver whose sandbox sits
  under the repository (none today, all use mktemp) would be refused. That is correct, and the
  message says why.
- Running any driver with an ambient `CLAUDE_PROJECT_DIR` pointing at this checkout would repeat
  the incident. Ambient runs use a throwaway clone.

# Plan — 084 autosync sandbox and harness environment

Bash 3.2-safe shell and the gate's existing awk lexer. No new dependencies. Each change removes
one way a run picks up its target or a side effect from the environment instead of from its caller.

## Changes by file

| File | Requirement | Change |
|---|---|---|
| `scripts/template-autosync.sh` | R1 R2 R3 | relative start made absolute + fixed-point stop (resolve line kept verbatim, the gate test greps it); `_origin_inside_sandbox` and the push decision; `refresh_local_template` skipped with a note for a clone outside a declared sandbox; `test-self-test-prologue.sh` and `test-root-walk-terminates.sh` into `CORE_SCRIPTS` |
| `scripts/template-autosync-hook.sh`, `lane-orientation-hook.sh`, `template-sync-verify-hook.sh`, `template-sync-verify.sh`, `stack-marker-canary-hook.sh`, `harness-state-gc.sh`, `spec-register-orientation-hook.sh`, `scenario-map-orientation-hook.sh`, `sync-feature-json-hook.sh`, `repeat-failure-guard-hook.sh`, `spec-run-log-hook.sh` | R1 | the same two lines in each walk |
| `scripts/drive-sync.sh` | R5 | `drive_hook <project> <sandbox> [args…]` on `DRIVE_HOOK_SCRIPT`, sharing the checks and the subshell runner |
| `scripts/validate-sync-sandbox-declarations.sh` | R5 R6 | hook targets and `-autosync-hook.sh` handles; `drive_hook` in the definition census; twelve wrappers with per-wrapper value counts; `watch`, `su -c` as code; header residuals updated |
| `scripts/test-*.sh` (all) | R4 | the one-line prologue, inserted after the shebang/comment header and before the first statement |
| `scripts/test-template-autosync-eol.sh`, `scripts/test-pipeline-hooks.sh` | R5 | hook runs through `drive_hook` |
| `.claude/docs/template-autosync.md` | R8 | what a declared sandbox guarantees now, residuals |

## Tests (names cite `084-AC-<n>` and `R<n>`; each file carries a sabotage arm)

- `scripts/test-root-walk-terminates.sh` (new) — R1, 084-AC-1: the twelve walkers under `timeout 5` with `a/b` outside any repo, `a/b` inside one (same root as absolute), `.`, `..`, a space in the name; sabotage: a copy with the old loop must time out.
- `scripts/test-template-autosync-sandbox-writes.sh` (new) — R2 R3, 084-AC-2, 084-AC-3: outside bare origin (refs unchanged, message), inside bare origin (pushed), `file://` inside, `https://` (not pushed), missing path, symlink inside → outside; behind clone outside the sandbox untouched + note, inside refreshed, undeclared still refreshes. Sabotage: a copy with R2 removed must push out.
- `scripts/test-self-test-prologue.sh` (new) — R4, 084-AC-4: every `scripts/test-*.sh` has the line, all seven names, before the first path-resolving line; fixture files missing/late are caught; decoy CDPATH + CLAUDE_PROJECT_DIR over three fast suites, decoy byte-identical.
- `scripts/test-validate-sync-sandbox-declarations.sh` (extend) — R5 R6, 084-AC-5: direct hook run reported, `drive_hook` passes, a second `drive_hook` definition is caught, `chronic`/`flock f`/`taskset 0x1`/`unbuffer`/`watch`/`su -c` reported, census of hand-spelled declarations is zero.
- `scripts/test-drive-sync.sh` (extend) — R5: `drive_hook` refuses `/`, a containing sandbox, a relative or missing `DRIVE_HOOK_SCRIPT`, and leaks nothing.

## Order

Tests first per area, then code, then the prologue sweep, then docs, the full suite, the
adversarial review and `/tla` on the push/refresh decision.

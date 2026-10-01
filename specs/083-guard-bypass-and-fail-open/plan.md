# Plan — 083 guard bypass and fail-open

Bash 3.2-safe shell plus Python 3 standard library, no new dependencies. Every change moves a guard
toward a stated verdict: deny where it is fail-closed, a spoken allow where it is fail-open, never a
silent allow.

## Changes by file

| File | Requirement | Change |
|---|---|---|
| `scripts/guard-lib.sh` (new, CORE) | R1 | `guard_parser_state`, `guard_field`, `guard_json_str`, `guard_deny`, `guard_context`, `guard_canon`, `guard_root_exempt` |
| `scripts/spec-register-guard-hook.sh`, `pipeline-state-guard-hook.sh`, `spec-interview-guard-hook.sh` | R2 R4 R5 | source the lib; canonical FILE; parse failure on a source path denies; resolver rc outside the defined set denies; directory exemptions anchored to the git root and the register root; name exemptions on the basename; every deny through `guard_deny` |
| `scripts/core-machinery-guard-hook.sh` | R3 R4 | lib; canonical FILE; parse failure on a scripts/rules path announces; deny through `guard_deny` |
| `scripts/core-owed-tick-guard-hook.sh` | R3 R4 R6 | lib; canonical FILE; tick by row-id diff in python (apply Edit/MultiEdit/Write to the current file), fallback `\[x\]` in written strings |
| `scripts/bash-write-guard-hook.sh`, `scripts/bash_write_targets.py` | R3 R7 | jq-fail and extractor-fail announce; extractor emits `@@ copy` src→dst pairs for single-file cp; the CORE delegate gets `content` from the source |
| `scripts/destructive-command-guard-hook.sh` + `destructive_command.py` (new, CORE) | R9 | bash precheck on trigger words, python shlex tokeniser, deny reason without the command text |
| `scripts/sensitive-file-guard-hook.sh` + `sensitive_paths.py` (new, CORE) | R10 | bash precheck on sensitive names, python classifier over path fields and shell tokens |
| `.claude/settings.json` | R9 R10 | two script hooks; the inline sensitive hook removed |
| `scripts/sync-core-hooks.py` | R10 | `_TEMPLATE_INLINE_RETIRED`: the inline hook's two exact past texts are dropped when `scripts/sensitive-file-guard-hook.sh` exists |
| `scripts/spec-register-orientation-hook.sh` | R11 | parser notice before any early exit |
| `scripts/template-autosync.sh` | — | the four new scripts and three new tests into `CORE_SCRIPTS` |
| `.claude/docs/security.md` | R12 | deny list is a prefix match; the two floor guards and their bounds |

## Tests (names cite `083-AC-<n>` and `R<n>`; each file carries sabotage arms)

- `scripts/test-guard-lib.sh` — R1: field read with jq, python3-only and no-parser PATHs; JSON escaping round-trip (quotes, backslash, newline, control bytes, non-ASCII); canon matrix (`..`, `//`, `.`, relative, symlinked dir, non-existent tail)
- `scripts/test-guard-fail-closed.sh` — R2 R3 R4 R5 R6 R7, 083-AC-1..4, fixture projects in mktemp, PATH shims hiding jq/python3
- `scripts/test-guard-exit-codes.sh` — R8: every PreToolUse script hook in settings.json, deny and allow fixtures, rc 0 + JSON with hookEventName whenever stdout is non-empty; sabotage arm (a copy that exits 1) must fail
- `scripts/test-destructive-command-guard.sh` — R9, 083-AC-5: deny matrix and allow matrix
- `scripts/test-sensitive-file-guard.sh` — R10, 083-AC-5: tools × paths matrix, O1 exceptions, oversized payload, unparseable payload, sync-core-hooks retire
- `scripts/test-spec-register-orientation.sh` or an arm in the closest existing test — R11

## Order

Tests first per area, then code, then settings and sync, then docs, then the full suite and the
adversarial review.

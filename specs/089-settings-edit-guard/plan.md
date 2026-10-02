# Plan — 089 settings edit guard

## Shape

Two new CORE files and one test, the sensitive-file-guard pattern (bash hook, python verdict):

- `scripts/settings_guard.py`: the verdict. `guarded_paths(env, cwd)`, `is_guarded(path)`,
  `edit_verdict(tool_input)` (R1–R3), `bash_verdict(command, cwd)` (R4). Prints one verdict word.
  Reads the payload from stdin, never the environment (088, adversarial #8).
- `scripts/settings-edit-guard-hook.sh`: the pre-check (R6), the python call, the repair path, the
  deny texts (R7). Exit 0 always; never echoes the command.
- `scripts/test-settings-edit-guard.sh`: 089-AC-1 … AC-5, the TB1/TB2 spellings, sabotage arms
  (the verdict replaced by one that always allows must turn the suite red).

Edits:

- `bash-write-guard-hook.sh`: the seventh delegate in `BASENAME_GUARDS`, its own lead line (R5).
- `template-autosync.sh`: `CORE_SCRIPTS` gains the three files (R8).
- `run-mutation-gate.sh`: a default-table line for the hook and its test (R8).
- `.claude/settings.json`: the PreToolUse entry. Written last, before the guard can see it.
- Docs: `.claude/docs/security.md`, `.claude/docs/workflows.md`.

## Order

Tests first (red), the module, the hook, the bash-write-guard delegate, CORE registration, the
template suite, then the settings wiring, then docs, adversarial review, /tla.

## Risks

- Self-lockout: the wiring is the last settings edit this repository's agent can make. Every other
  hook change after this spec is the developer's.
- False denies on everyday reads: the read list in R4 and `git add`/`git commit` are pinned by tests.
- The precheck's cost on Bash: one python start for a command holding a glob or `sett`/`.cla`.

## Mutation

`run-mutation-gate.sh --module scripts/settings-edit-guard-hook.sh` mutates the bash half only; the
python verdict is covered by the sabotage arms and the case table (the runner has no python
operators, spec 085).

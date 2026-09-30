# Plan — 049

1. `scripts/spec_active.py`: extract the `<id>-*` glob from `resolve()` into
   `dir_for_id(root, ident)`. Add `row_status(root, ident)` and a `--id <token>` CLI mode (FR-01).
   Exit 0 found, 4 no directory, 2 malformed.
2. `scripts/spec-run-log-hook.sh`: compute ROOT once for both branches. `--spec X`: an existing
   directory is used as-is; otherwise ask the resolver `--id X` and map 2→2, 4→4 with a message that
   names the id (FR-02..04). Implicit failure paths gain the hint, and the held ids come from a grep
   of `- [!]` rows (FR-05). Update the usage strings and header (FR-07).
3. `.claude/rules/spec-register.md` "Failure memory": one sentence on `--spec <id>` for held and
   ticked rows (FR-07).
4. Tests red first: `test-pipeline-hooks.sh` run-log block, `test-active-spec-resolution.sh` `--id`
   arms.
5. Verify: both suites plus the rest of the resolver consumers' suites, and a Git Bash-safe syntax
   check (bash 3.2: no `${x,,}`, no associative arrays).

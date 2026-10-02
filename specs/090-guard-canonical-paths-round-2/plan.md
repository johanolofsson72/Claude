# Plan — 090 guard canonical paths, round 2

Bash 3.2-safe shell, python3 where the guards already use it, no new dependencies. One new sourced
file (`guard-precheck.sh`), so the five prechecks share one symlink test without loading the
library (which forks) on the exit path.

## Changes by file

| File | Requirement | Change |
|---|---|---|
| `scripts/guard-lib.sh` | R1 R3 R6 R7 | `_guard_pwd` (`/bin/pwd -P` where the system folds), the stored final name in `_guard_canon_walk`, `_guard_realdir` through `_guard_pwd`; `guard_ext_of` (strips `.`, ` `, `::$DATA`); `guard_git_boundary` sets `GUARD_BOUNDARY_KIND` (`root`, `worktree`) and judges a `.git` at the anchor by R6; on msys/cygwin/win the walk drops trailing dots and spaces from each component; header paragraphs |
| `scripts/guard-precheck.sh` (new) | R2(b) | `guard_precheck_link <raw>`: the payload's `file_path`/`notebook_path`, against its `cwd`, is or runs through a symlink, or is escaped |
| `scripts/spec-register-guard-hook.sh`, `pipeline-state-guard-hook.sh`, `spec-interview-guard-hook.sh` | R2 R3 R4 R7 | precheck regex admits `[. ]` and `::$DATA` after the extension, plus the link test; `SOURCE_EXTS` += 12; `notebook_path` fallback; `guard_ext_of`; the walk inherits register and marker past a linked worktree, exemptions stay at the worktree |
| `scripts/core-machinery-guard-hook.sh`, `core-owed-tick-guard-hook.sh` | R2 | precheck folds case and runs the link test |
| `scripts/destructive_command.py`, `destructive-command-guard-hook.sh` | R5 | `git-push-delete`, `git-push-mirror`; the reason text; header |
| `scripts/sensitive_paths.py` | R8(a) | sed script words are not path candidates |
| `scripts/trust-anchor-guard-hook.sh` | R8(b) | `is_acceptance` judges a glob by its brace-and-case-folded expansion on disk |
| `.claude/settings.json` | R4 | matcher of the five-guard block `Edit\|Write\|MultiEdit\|NotebookEdit` (applied by the developer, O4) |
| `scripts/template-autosync.sh` | R9 | CORE_SCRIPTS: `guard-precheck.sh`, `test-guard-canonical-paths.sh` |
| `.claude/docs/security.md` | R9 | the new push forms, the stored-name rule |

## Tests (names cite `090-AC-<n>` and `R<n>`; each requirement carries a sabotage arm)

- `scripts/test-guard-canonical-paths.sh` (new) — R1 R2 R3 R4 R6 R7, 090-AC-1/2/3. A fixture
  project per arm. Case arms skip on a case-sensitive volume, with a skip line. Sabotage: a copy of
  the scripts with `_guard_pwd` reduced to the builtin, the link test returning 1, `guard_ext_of`
  without stripping, the R6 check removed, and the R7 inheritance removed must each flip its arm to
  allow.
- `scripts/test-destructive-command-guard.sh` (extend) — R5, 090-AC-4, plus the allowed controls;
  sabotage: the classifier without the delete branch.
- `scripts/test-sensitive-file-guard.sh` (extend) — R8(a), 090-AC-5: `s/.env//` allowed, `.env`
  operand and `-f .env` denied, `-e` handling; sabotage: sed scripts kept as candidates.
- `scripts/test-trust-anchor-guard.sh` (extend) — R8(b), 090-AC-5: `{/*` in a delegated target
  allowed; `specs/*/acceptance.md`, `{acceptance,x}.md`, `ACCEPT*.MD` still denied.
- `scripts/test-spec-dir-absent.sh` — parity of `SOURCE_EXTS` (unchanged test, new list).

## Order

Tests first per area, then code, then docs, the full suite, the threat-model residuals, the
adversarial review (security-scanner, `/security-review`), `run-mutation-gate.sh` on the changed
modules, and `/tla` on the walk (R6/R7 is the only state that moves).

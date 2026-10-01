# Plan — 088 guard trust anchors

Bash 3.2-safe shell, python3 for the two JSON-reading pieces (as 080 and 083 already do), no new
dependencies. Each change moves one decision off state the agent can write.

## Changes by file

| File | Requirement | Change |
|---|---|---|
| `scripts/guard-lib.sh` | R1 | `guard_anchor_for <file>` (physical `CLAUDE_PROJECT_DIR`, set only when the file is inside it) and `guard_git_boundary <dir>`; header paragraph on the anchor |
| `scripts/spec-register-guard-hook.sh`, `pipeline-state-guard-hook.sh`, `spec-interview-guard-hook.sh`, `core-machinery-guard-hook.sh`, `core-owed-tick-guard-hook.sh` | R1 | `guard_anchor_for "$FILE"` before the walk; `[ -e "$DIR/.git" ]` → `guard_git_boundary "$DIR"` |
| `scripts/project-maintenance.sh` | R2 | `--yes` refused under `CLAUDECODE`; the prompt input opened on fd 3 and required to be a terminal; header lines 42–47 rewritten |
| `scripts/trust-anchor-guard-hook.sh` (new) | R3 | bash precheck on trigger words; python verdict for the store basenames, acceptance.md Confirmed lines, the Bash text rules, and pre-filled AskUserQuestion answers; fail closed |
| `scripts/bash-write-guard-hook.sh` | R3 | sixth delegate in `BASENAME_GUARDS`, its own provenance arm in `emit_and_exit` |
| `scripts/developer-answers-hook.sh` (new) | R4 | PostToolUse AskUserQuestion → `<git-common-dir>/claude-developer-words`, hashes and digests, 500-line cap |
| `scripts/acceptance_cases.py` | R5 R6 | `_confirm` checks the binding (exit 3); `HOW_TO_CONFIRM` step 2 names the digest; `_grandfathered` by ancestry, `GRANDFATHER_BEFORE` removed |
| `scripts/acceptance-cases.sh` | R5 | usage text: `--confirm` needs the answer recorded |
| `.claude/settings.json` | R7 | trust-anchor guard on PreToolUse (`Edit\|Write\|MultiEdit\|NotebookEdit\|Bash\|AskUserQuestion`), developer-words hook on PostToolUse (`AskUserQuestion`) |
| `scripts/template-autosync.sh` | R7 | CORE_SCRIPTS: the two hooks and their tests |
| `.claude/rules/spec-interview.md`, `.claude/docs/spec-interview-rationale.md` | R8 | the digest goes in the question; the binding and its residuals |

## Tests (names cite `088-AC-<n>` and `R<n>`; each file carries a sabotage arm)

- `scripts/test-guard-root-anchor.sh` (new) — R1, 088-AC-1: fixture project (register, marker, active spec without interview); planted `src/app/.git` (empty file, `git init`), `scripts/.git`, `specs/.git`; each of the five guards gives the same verdict as without the plant when `CLAUDE_PROJECT_DIR` is the project; without the anchor the old behaviour is kept; a file outside the anchor walks as before. Sabotage: a guard copy with the old test must allow.
- `scripts/test-maintenance-trust.sh` (extend) — R2, 088-AC-2: `CLAUDECODE=1 --trust --yes` exits 2, no store; a regular file holding `yes` as `MAINTENANCE_TTY` exits 2, no store; `/dev/null` refused; the existing `--yes` arms run with `CLAUDECODE` cleared.
- `scripts/test-trust-anchor-guard.sh` (new) — R3, 088-AC-3: every deny shape (Write/Edit store, Bash append/cat/`--trust`/`--tr""ust`/`MAINTENANCE_TTY`, Edit adding/changing/removing Confirmed, Write with changed Confirmed, delegated acceptance.md, pre-filled answers) and every allow control (Write acceptance.md without Confirmed, Edit of a case body, `acceptance-cases.sh --confirm`, ordinary Bash, an honest AskUserQuestion, an unrelated file); no command text in any reason; unparseable payload with a trigger word denied; bash-write-guard routes `> .git/claude-trusted-commands` and `sed -i … acceptance.md` to it. Sabotage: the guard with its Confirmed rule removed must allow.
- `scripts/test-developer-answers.sh` (new) — R4 R5, 088-AC-4: hook records hash + digests, no plaintext; cap; garbage payload records nothing and exits 0; `--confirm` refuses with no store, wrong quote, right quote whose question lacked the digest (exit 3, file unchanged); writes after a matching record. Sabotage: `_confirm` without the binding check must write.
- `scripts/test-acceptance-cases.sh` (extend) — R6, 088-AC-5: interview committed after the arrival with `GIT_COMMITTER_DATE=2026-09-01` owes cases; committed before the arrival is exempt; no arrival commit owes cases.

## Order

Tests first per area, then code, then wiring and docs, the full suite, the adversarial review, the
mutation sabotage arms (the template has no mutation runner, row 085), and `/tla` on the confirm and
trust decisions.

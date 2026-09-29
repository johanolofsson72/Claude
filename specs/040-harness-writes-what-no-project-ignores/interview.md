# Spec interview — 040-harness-writes-what-no-project-ignores

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. No overflow: no auth/PII/upload/new external surface, no state machine, no new entity. The ≥6-files trigger is borderline (four scripts, two docs, one config) and is judged not to fire. The one real risk, an unattended write into a project-owned file, is covered by the threat-model section in spec.md.

## Q1 — Scope boundary
**Q:** What is in and what is out?
**A (auto):** In: a CORE helper that owns one managed block in `.gitignore`, the sync calling it, a report of already-tracked machine-local files, and the markers test reading the helper's list. Out: untracking anything automatically, and project-only markers (those stay in `.claude/.runtime-markers`).

## Q2 — Primary actor
**Q:** Who is hurt today?
**A (auto):** Every project that autosyncs without a hand-run `/project-update` section 3a. hetznerradar is the measured case: 109 tracked attempt counters and a marker churning in `git status`.

## Q3 — Happy path
**Q:** What does done look like in a project?
**A (auto):** After one sync, `.gitignore` ends with the managed block, the sync commit includes it, `git status` stays clean through a session, and any already-tracked machine-local file is named with the command to untrack it.

## Q4 — Single source
**Q:** Where does the list live?
**A (auto):** In `scripts/harness-gitignore.sh` as `pattern%reason` lines, printed by `--list`. It is a CORE script, so it reaches every project, and SKILL.md 3a, sync-prompt.md and the markers test all read or point at it instead of keeping copies.

## Q5 — Block markers
**Q:** What delimits the managed block?
**A (auto):** Two exact full lines: `# >>> claude-code harness (managed by scripts/harness-gitignore.sh) >>>` and `# <<< claude-code harness <<<`. Matched as whole lines with an optional trailing `\r`, never as substrings.

## Q6 — Placement
**Q:** Where is the block inserted the first time?
**A (auto):** At the end of the file, after a blank line. Later rewrites stay wherever the block is. At the end, no earlier project line can negate it.

## Q7 — Bytes outside the block
**Q:** What happens to the project's own lines?
**A (auto):** Nothing. Every byte before and after the block survives exactly, duplicates included. A project line that repeats a managed pattern is harmless and it is not the sync's to delete.

## Q8 — Malformed block
**Q:** Start without end, end without start, two blocks?
**A (auto):** Refuse to write, print which of the three it is, and exit 3. The sync surfaces it as `[gitignore]`. Guessing where a broken block ends is how a project's own lines get eaten.

## Q9 — Line endings
**Q:** CRLF `.gitignore`?
**A (auto):** Detect from the first line ending. A CRLF file gets a CRLF block, so a Windows checkout does not end up with mixed endings. The comparison for "current" is made in the file's own endings.

## Q10 — No `.gitignore`
**Q:** The project has none?
**A (auto):** Create it with the block alone and print `added`, so the sync records it with `record_add`.

## Q11 — Idempotence
**Q:** What does a second run do?
**A (auto):** Nothing: no output, no write, mtime unchanged. The sync then records no write and the stamp does not move.

## Q12 — Check modes
**Q:** `--check`, `--dry-run`, deferral?
**A (auto):** The helper's `--check` answers without writing. The sync calls it in check mode, so `--dry-run` lists `.gitignore` as `add`/`update` and nothing is written.

## Q13 — Tracked files
**Q:** What about files already committed under the managed patterns?
**A (auto):** Report them, never untrack them. Found with `git ls-files -ci --exclude-from=<block>`, collapsed to the topmost directory a directory pattern matched, printed with one `git rm -r --cached --` line. Up to 10 paths in the session-start text, and the total count.

## Q14 — Report placement
**Q:** Which sync exits render `[tracked]`?
**A (auto):** The same three the other standing reports use: the `[ok]` early exit, the check block, and the end of a full sync. It is a standing condition, so it has to show on the `[ok]` path where most sessions land. It is silent when empty.

## Q15 — Error semantics
**Q:** Helper missing or failing inside the sync?
**A (auto):** A template without the helper (an older clone) is skipped silently, which is the offline posture the sync takes everywhere. A helper that exits non-zero is reported as `[gitignore]` with its message. The sync never aborts over it.

## Q16 — Markers test
**Q:** How does `test-runtime-markers-ignored.sh` change?
**A (auto):** D stops reading SKILL.md 3a and reads `scripts/harness-gitignore.sh --list`. Its matcher learns unanchored patterns (`__pycache__/` covers `scripts/__pycache__/`). MACHINE_LOCAL gains `.claude/settings.local.json`, `.claude/projects/`, `.claude/worktrees/`, `.specify/feature.json` and `scripts/__pycache__/`. The self-test fixtures ship a stub helper instead of a SKILL.md.

## Q17 — Portability
**Q:** Platform constraints?
**A (auto):** bash 3.2, POSIX awk, git. No `sed -i`, no GNU-only flags. Must pass `validate-portability.sh` and run under Git Bash.

## Q18 — Acceptance criteria
**Q:** Measurable definition of done?
**A (auto):** `test-harness-gitignore.sh` covers SC-040-01..16 and is red on HEAD (the helper does not exist). The markers test and its self-test pass. The autosync suites (owed, stranded, eol, unlisted, count-honesty) still pass, and so does the sync-prompt core parity test.

## Q19 — Reversibility
**Q:** Undo story?
**A (auto):** Revert the commit. Projects keep a block that is only ignore lines, and deleting the block by hand is safe. Nothing is untracked, so there is nothing to restore.

## Q20 — Non-goals
**Q:** What is explicitly not done?
**A (auto):** No automatic `git rm --cached`, no rewriting of project lines outside the block, and no classification of project-only markers.

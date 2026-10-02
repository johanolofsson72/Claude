# Spec interview — 090-guard-canonical-paths-round-2

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO (base auto-answered with recommended; genuinely-ambiguous escalated; overflow human-answered if flagged).
Flag: hardened (the path layer under every Edit-path gate, tagged row, ≥ 6 files), so the policy
questions go to the developer as overflow (O1–O4), each on a threat surface: input tampering (a
planted .git at the anchor, a trailing dot), authorization (who wires NotebookEdit, whether a remote
branch may be deleted).

## Q1 — Scope boundary
**Q:** Which findings does 090 close?
**A (auto):** The eight the row names (F082 F083 F084 F085 F096 F105 F106 F112), plus F122 from H4, which is the same worktree code path as F106 and smaller to fix here than to record again.

## Q2 — Scope boundary: hard links
**Q:** Does 090 detect a hard link that already exists under an innocent name?
**A (auto):** No. It needs a `stat` per Edit to read the link count, and making one through the shell is already judged as its target (083). Named residual in the spec.

## Q3 — Primary actor
**Q:** Who is the adversary?
**A (auto):** The gated agent, using Edit/Write/MultiEdit/NotebookEdit/Bash as the developer's OS user, careless or prompt-injected. The aim is that the path an agent spells cannot make a guard judge a different file than the one written.

## Q4 — Happy path
**Q:** What changes for an ordinary session?
**A (auto):** Nothing visible. Edits spelled in the stored case, through no symlink, behave exactly as before. Only a payload whose spelling differed from the stored file now gets the verdict the stored file gets.

## Q5 — Data model
**Q:** Does 090 add persisted state?
**A (auto):** None. Every change is in how a path is resolved or a command is read.

## Q6 — Validation: what is "the stored name"?
**Q:** Which spelling wins when the file system holds one name and the payload another?
**A (auto):** The one the file system returns: getcwd for directories, a case-insensitive match in the directory listing for the final component. On a case-sensitive volume where both `scripts` and `SCRIPTS` exist, the exact spelling wins, because it names a distinct directory.

## Q7 — Validation: names that do not exist
**Q:** How is a component that does not exist yet spelled?
**A (auto):** As typed. There is nothing stored to look up. A new file in an existing directory still gets the directory's stored spelling.

## Q8 — The four observable states
**Q:** What does the agent see in each state?
**A (auto):** Success: no output, the call proceeds. Error: the deny the guard already gives for the stored file, naming that file's canonical path. Empty: a payload with no path, or a precheck miss with no symlink, exits with no output. Loading: none; a PreToolUse hook is synchronous. The added cost is one `/bin/pwd` per canonicalised path on macOS and Windows, and builtin `[ -L ]` tests in the precheck.

## Q9 — Error semantics
**Q:** What if `/bin/pwd` is missing or fails?
**A (auto):** Fall back to the builtin `pwd -P`, which is today's behaviour. The canonical path is never empty because of the lookup.

## Q10 — Authorization
**Q:** Is there an override for any of the new denials?
**A (auto):** No new variable. The CORE and tick guards keep their existing overrides (`ALLOW_CORE_MACHINERY_EDIT`, `ALLOW_TICK_WITH_CORE_OWED`); the destructive list has none (the developer runs the command with `!`).

## Q11 — Concurrency
**Q:** Can the path change between the check and the write?
**A (auto):** Yes, a symlink can be swapped between PreToolUse and the tool's open. That race exists for every PreToolUse guard and needs a second tool call, which is itself judged. Not addressed.

## Q12 — Integration: bash-write-guard
**Q:** Does a shell write get the same resolution?
**A (auto):** Yes. bash-write-guard hands each target to the same guards as a `file_path`, and they canonicalise it with the same function.

## Q13 — Integration: projects
**Q:** How does a project get the changes?
**A (auto):** Every changed script is in `CORE_SCRIPTS`; the SessionStart autosync copies them. The NotebookEdit matcher reaches a project through `sync-core-hooks.py`, which replaces a core hook block by its script set and takes the template's matcher.

## Q14 — Edge cases: symlink loops and long chains
**Q:** What if the symlink chain loops?
**A (auto):** `guard_canon` already stops after 8 hops and judges the last name reached. The precheck only asks "is any component a link", so a loop costs one `[ -L ]` per component.

## Q15 — Edge cases: relative paths in the precheck
**Q:** A relative `file_path` in the precheck?
**A (auto):** Taken against the payload's `cwd`, read by a bash regex on the raw JSON. No `cwd` in the payload: the process's working directory, as `guard_canon` does.

## Q16 — Edge cases: the sed operand rule
**Q:** `sed -n 's/x/y/p' .env` and `sed -i.bak -e 's/.env//' a`?
**A (auto):** The first still names `.env` as a file operand and is denied. The second treats only the `-e` argument as a script, so `a` is the only path and it is allowed. `sed -f .env x` reads `.env` and is denied.

## Q17 — Edge cases: push forms
**Q:** Which push spellings are not deletion?
**A (auto):** `git push origin :` (push matching branches), `git push origin main:main`, `git push -u origin x`, `--dry-run`. A refspec beginning with `+` is already the force form.

## Q18 — Non-functional limits
**Q:** What is the cost budget?
**A (auto):** The precheck exit path stays builtin-only. A guard that passes its precheck pays at most one extra process (`/bin/pwd`), on case-folding systems only.

## Q19 — Acceptance criteria
**Q:** What proves it?
**A (auto):** One new test file (`scripts/test-guard-canonical-paths.sh`) naming 090-AC-1…AC-5, arms added to the destructive, sensitive and trust-anchor tests, a sabotage arm per requirement, the full template suite green, and `run-mutation-gate.sh` at or above 80 % on `guard-lib.sh` and the changed guards.

## Q20 — Reversibility
**Q:** How is it rolled back?
**A (auto):** `git revert` of the spec's commits. No state migrates, so a revert restores the old verdicts exactly; the developer reverts the matcher by hand.

## O1 — A planted .git at the anchor (overflow, developer; F105 second half)
**Q:** A session started in proj/src has CLAUDE_PROJECT_DIR=proj/src, and a .git planted at proj/src ends the walk. How is a .git at the anchor judged when a parent also holds one?
**A:** Validity check. It counts as a root only when it is a real git dir with at least one commit (`git rev-parse --verify HEAD`); an empty file, an empty dir or a fresh `git init` does not, and the walk continues to the outer project. A genuine nested repo the developer started in still counts.

## O2 — Trailing dots and spaces (overflow, developer; F096)
**Q:** Strip trailing dots/spaces and `::$DATA` before reading the extension on every platform, or only on Windows?
**A:** Every platform. WSL on an NTFS mount reports linux; a real Linux file named 'App.cs.' getting a deny is the accepted cost.

## O3 — Push deletion (overflow, developer; F084)
**Q:** Deny `git push --delete/-d/:ref/--prune/--mirror` with no override?
**A:** Deny all, no override. Remote branch deletion is rare in a solo direct-push workflow and worth a `!`.

## O4 — NotebookEdit wiring (overflow, developer; F084, R4)
**Q:** The five-guard block's matcher is `Edit|Write|MultiEdit`, and the agent cannot change wiring (089). When is it applied?
**A:** Now, by the developer: `! sed -i '' '88s/"Edit|Write|MultiEdit"/"Edit|Write|MultiEdit|NotebookEdit"/' .claude/settings.json`.

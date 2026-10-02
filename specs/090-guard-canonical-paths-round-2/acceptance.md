# Acceptance cases — 090-guard-canonical-paths-round-2

**Confirmed:** 2026-10-02 · 24d846272737 — "Confirmed as written"

Drafted by Claude, confirmed by the developer through AskUserQuestion. Tests name a case as
`090-AC-<n>`.

## AC-1 — A path spelled in another case or Unicode form is judged as the stored file
**Given** a project on macOS with a register, a CORE `scripts/guarded.sh` and `CLAUDE_PROJECT_DIR` set, and a copy of it under a directory whose name holds an accented letter, with an empty `src/.git` planted
**When** core-machinery-guard is asked about `SCRIPTS/guarded.sh` and `scripts/GUARDED.SH`, core-owed-tick-guard about a tick written through `specs/index.md`, and spec-interview-guard about `src/main.py` while `CLAUDE_PROJECT_DIR` spells the accented directory in NFD and the file path spells it in NFC
**Then** each denies, exactly as it does for the stored spelling

## AC-2 — Symlinks, NTFS names, new extensions and NotebookEdit reach the parser
**Given** a project with an active spec that has no interview, `docs/notes.txt` a symlink to `../src/App.cs`, and `docs/tools` a symlink to `../scripts`
**When** spec-interview-guard is asked about an Edit of `docs/notes.txt`, `src/App.cs.` and `src/q.sql` and a NotebookEdit of `src/n.ipynb`, and core-machinery-guard about `docs/tools/guarded.sh`
**Then** each denies, and the template wiring sends NotebookEdit to the five Edit-path guards

## AC-3 — An empty worktree or a planted .git at the anchor does not drop the register
**Given** a project with a register and `CLAUDE_PROJECT_DIR` set, a `git worktree add --no-checkout .claude/worktrees/nc`, and separately a session anchored at `proj/src` with an empty `proj/src/.git`
**When** spec-interview-guard is asked about `.claude/worktrees/nc/src/main.py`, and about `proj/src/main.py` under the `proj/src` anchor
**Then** both deny on the project's register, while a nested repository at the anchor that has a commit is still its own root

## AC-4 — Deleting or mirroring a remote is on the destructive list
**Given** destructive-command-guard on Bash
**When** it is asked about `git push --mirror origin`, `git push origin --delete main`, `git push -d origin main`, `git push origin :main` and `git push --prune origin`
**Then** each is denied without echoing the command, while `git push origin :` and `git push origin main` are allowed

## AC-5 — The two false positives are gone and their real cases still deny
**Given** sensitive-file-guard and bash-write-guard with trust-anchor-guard as a delegate
**When** a Bash command runs `sed 's/.env//' f.txt`, `sed 's/a/b/' .env`, a heredoc that writes a JSON fixture holding `{/* c */}`, and `sed -i 's/x/y/' specs/*/acceptance.md`
**Then** the first and third are allowed, and the second and fourth are denied

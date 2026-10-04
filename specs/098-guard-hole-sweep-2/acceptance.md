# Acceptance cases — 098-guard-hole-sweep-2

**Confirmed:** 2026-10-04 · 231c3c8c113a — "Confirm"

Drafted by Claude, confirmed by the developer through AskUserQuestion. Tests name a case as
`098-AC-<n>`.

## AC-1 — A write through a symlinked directory into the git dir is refused
**Given** a project whose tree already holds `gd`, a symlink to its `.git` directory
**When** trust-anchor-guard is asked about a Write to `gd/info/exclude` and to `gd/description`
**Then** both are denied as writes inside a git directory, while a Write to `docs/notes.md` in the same project is allowed with no output

## AC-2 — A pushed Confirmed line no longer unlocks code on its own
**Given** a hardened spec whose acceptance.md carries a Confirmed line with the right digest, committed and present on the upstream remote-tracking ref, and no recorded developer answer for it in this clone
**When** the spec-interview guard is asked about an Edit to production source
**Then** it is denied with a reason that says to ask the confirm question in this clone, and after the answer is recorded the same Edit (with a test naming every case) is allowed

## AC-3 — Removing the sync script no longer turns the CORE guards off
**Given** a synced project (`.claude/.template-sync` present) whose `scripts/template-autosync.sh` has been deleted
**When** core-machinery-guard is asked about an Edit to a file under `scripts/`, and core-owed-tick-guard about a tick in `specs/INDEX.md`
**Then** both are denied naming the missing file and the `git checkout` route, while the same edits in the template repository are allowed with no output, and so is the `scripts/` Edit in a repository with a `.claude/` directory but no stamp and no register

## AC-4 — A root walk that cannot ask git is never silent, and its notice cannot be pre-silenced
**Given** a project opened in a linked worktree, and a PATH on which git is missing
**When** the pipeline-state guard and core-machinery-guard are asked about an Edit there, with a stamp for that notice already created under `$TMPDIR/claude-hook-notices/<session>/`
**Then** the pipeline-state guard denies naming git as the cause, and core-machinery-guard allows with an announcement naming git that the pre-created stamp does not suppress

## AC-5 — A harmless read next to a script run is allowed, a read fed to a runner is not
**Given** the settings guard on PreToolUse for Bash
**When** it is asked about `grep hooks <settings> ; bash scripts/test-x.sh`, and about `cat <settings> | sh`, `cat <settings> > f; sh f` and `{ cat <settings>; } | bash`
**Then** the first is allowed with no output and the other three are denied

# Acceptance cases — 105-guard-bypasses

**Confirmed:** 2026-11-17 · 07c7dba9fb71 — "Confirm"

Drafted by Claude, confirmed by the developer through AskUserQuestion. Tests name a case as
`105-AC-<n>`.

## AC-1 — The git dir cannot be removed or pre-stamped from the shell
**Given** a guarded project with a `.git` directory
**When** trust-anchor-guard is asked about `rm -r .git`, `rmdir .git/refs/x`, `touch .git/claude-hook-notices/s/x`, `mkdir -p "$(git rev-parse --git-dir)/claude-hook-notices/s"` and `cat .git/HEAD`
**Then** the first four are denied naming the git dir, and `cat .git/HEAD` is allowed with no output

## AC-2 — With .git gone, the guards still judge
**Given** a project with `specs/INDEX.md` and `.claude/.template-sync` but no `.git`, as `CLAUDE_PROJECT_DIR`
**When** spec-register-guard is asked about an Edit to `src/app.py`, and core-machinery-guard about an Edit to a CORE script under `scripts/`
**Then** spec-register-guard denies naming the missing `.git`, and core-machinery-guard denies the CORE edit and announces that the root has no `.git`

## AC-3 — The guards' own tools and scripts stay working
**Given** a directory on PATH outside the project, and `scripts/x-guard-hook.sh` that passes `bash -n`
**When** trust-anchor-guard is asked about a Write of `<dir>/git`, `ln -s /tmp/x <dir>/git`, an Edit of the guard script that adds an unclosed `$(`, and an Edit of it that keeps it parseable
**Then** the first two are denied as a write into a PATH directory, the third is denied naming the parse error, and the last is allowed with no output

## AC-4 — Settings reads handed on are writes, harmless lines are not
**Given** the settings guard on PreToolUse for Bash
**When** it is asked about `</dev/null bash f <settings>`, `cat <settings>; sed -i x "$_"`, `cat <settings> > f; python3.12 f` and `grep hooks <settings> ; bash scripts/test-x.sh "$(pwd)"`
**Then** the first three are denied and the last is allowed with no output

## AC-5 — Copied cases do not confirm a new spec
**Given** spec A confirmed with an answer recorded for its question, and spec B whose acceptance.md is a verbatim copy of A's cases
**When** `acceptance-cases.sh --confirm <B> --quote "Confirm"` runs with no answer recorded for B's question
**Then** it refuses, and after a Confirm answer to B's own question it records the line

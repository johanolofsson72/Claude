# Acceptance cases — 083-guard-bypass-and-fail-open

**Confirmed:** 2026-10-01 · 337dd1d01503 — "Confirmed as written"

Drafted by Claude, confirmed by the developer through AskUserQuestion. Tests name a case as
`083-AC-<n>`.

## AC-1 — No jq is not a free pass
**Given** a code project whose active spec has no plan.md, on a PATH with no jq
**When** Claude edits src/App.cs
**Then** pipeline-state-guard still denies (python3 fallback), and with neither jq nor python3 it denies with a reason naming the missing tool, exit 0 in both cases

## AC-2 — A crooked path reaches the same verdict
**Given** a project with a CORE script scripts/template-autosync.sh and a template clone whose copy differs from the proposed bytes
**When** the Edit's file_path is <root>/x/../scripts/template-autosync.sh, <root>//scripts/template-autosync.sh, or the relative scripts/template-autosync.sh
**Then** core-machinery-guard denies each one, exactly as it denies <root>/scripts/template-autosync.sh

## AC-3 — Only the root scripts/ is exempt
**Given** a web project with a register whose active spec has no plan.md
**When** Claude edits src/scripts/app.js, and separately <root>/scripts/tool.sh
**Then** the first is denied by pipeline-state-guard and the second is allowed

## AC-4 — A split tick is still a tick
**Given** a project that owes the template CORE work and a register row `- [ ] 005 — x — light track — goal`
**When** an Edit replaces `[ ] 005` with `[x] 005` (the `- ` outside both strings)
**Then** core-owed-tick-guard denies, and an Edit that only rewords an already-ticked row is allowed

## AC-5 — Spelling does not get past the floor
**Given** the destructive-command and sensitive-file guards wired on Bash
**When** Claude runs `rm -r -f build`, `/bin/rm -rf build`, `git push -f origin main`, `git clean -fd`, or `cat ~/.ssh/id_rsa`
**Then** each is denied with exit 0, while `git commit -m "drop rm -rf from docs"` and `rm -r build` are allowed

# Acceptance cases — 088-guard-trust-anchors

**Confirmed:** 2026-10-01 · 994b2d3b99de — "Confirmed as written"

Drafted by Claude, confirmed by the developer through AskUserQuestion. Tests name a case as
`088-AC-<n>`.

## AC-1 — A planted .git does not move the project root
**Given** a project with a register whose active spec has no interview, a language marker, and an empty file `src/app/.git`, with `CLAUDE_PROJECT_DIR` set to the project
**When** spec-interview-guard and pipeline-state-guard are asked about an Edit of `src/app/main.py`, and core-machinery-guard about `scripts/<core>.sh` with an empty `scripts/.git`
**Then** each denies, exactly as it does without the planted `.git`

## AC-2 — Claude cannot grant nightly trust
**Given** a project with a declared suite command and `CLAUDECODE=1` in the environment
**When** `project-maintenance.sh --trust --yes` runs, or `--trust` runs with `MAINTENANCE_TTY` pointing at a regular file that holds `yes`
**Then** both exit 2, name the developer's own terminal as the route, and `.git/claude-trusted-commands` is not created

## AC-3 — The trust and answer stores are out of the agent's tools
**Given** the trust-anchor guard on PreToolUse
**When** a Write targets `.git/claude-trusted-commands`, a Bash command appends to `.git/claude-developer-words`, a Bash command runs `project-maintenance.sh --trust`, or an Edit adds a `**Confirmed:**` line to a spec's acceptance.md
**Then** each is denied with a reason that names the store or line and does not echo the command

## AC-4 — A confirm needs the developer's matching answer
**Given** acceptance cases with digest D and a developer-words store
**When** `--confirm` runs with a quote that no recorded answer matches, or that matches an answer whose question did not show D
**Then** it exits 3 and writes nothing; after an AskUserQuestion whose question shows D is answered with that quote, the same `--confirm` writes the Confirmed line

## AC-5 — A forged committer date no longer grandfathers
**Given** a full-track spec with a ticked task and no acceptance.md, whose interview.md was committed after `scripts/acceptance_cases.py` arrived but with `GIT_COMMITTER_DATE` set to 2026-09-01
**When** the spec-interview guard is asked about a source edit
**Then** it denies for missing acceptance cases, while a spec whose interview.md was committed before the arrival commit is still exempt

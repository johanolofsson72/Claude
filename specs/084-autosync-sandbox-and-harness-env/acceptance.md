# Acceptance cases — 084-autosync-sandbox-and-harness-env

**Confirmed:** 2026-10-01 · 9f614d7c074e — "Confirmed as written"

Drafted by Claude, confirmed by the developer through AskUserQuestion. Tests name a case as
`084-AC-<n>`.

## AC-1 — A relative project dir does not hang a session
**Given** a directory `a/b` with no `.git` anywhere above it, and separately `a/b` inside a git project
**When** the sync, the autosync hook and the five other walking scripts run with `CLAUDE_PROJECT_DIR=a/b`
**Then** each returns within 5 seconds: the first with "not inside a git repository", the second acting on the same root as the absolute spelling

## AC-2 — A sandboxed sync keeps its commits at home
**Given** a sandboxed fixture project whose branch tracks an `origin` bare repo outside the declared sandbox
**When** a sync that changes files runs through drive_sync
**Then** it commits locally, says "not pushed — origin is outside the declared sandbox", and the outside bare repo's refs are unchanged, while the same fixture with an in-sandbox bare origin is pushed

## AC-3 — A sandboxed sync leaves the developer's template clone alone
**Given** a template clone outside the declared sandbox that is behind its origin, found through the candidate list
**When** a sandboxed sync uses it
**Then** the clone's HEAD and refs are unchanged and the run prints one note saying it was used as-is, while an undeclared run still fast-forwards it

## AC-4 — A self-test cannot be aimed at another tree
**Given** CDPATH pointing at a decoy clone and CLAUDE_PROJECT_DIR set to that decoy
**When** a sample of self-tests runs from the real repository
**Then** they stay green and the decoy is byte-identical afterwards, and the prologue check fails any scripts/test-*.sh missing the unset line or placing it after its first cd

## AC-5 — Running the hook outside drive_hook is a violation
**Given** a script under scripts/ that runs template-autosync-hook.sh directly, or runs the sync behind `chronic` or `flock <file>`
**When** validate-sync-sandbox-declarations.sh runs
**Then** it exits 1 and names the file and line, and the same call through drive_hook (or drive_sync) passes

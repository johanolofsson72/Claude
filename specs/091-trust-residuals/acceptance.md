# Acceptance cases — 091-trust-residuals

**Confirmed:** 2026-10-02 · 98f0250cc42d — "Confirm"

Drafted by Claude, confirmed by the developer through AskUserQuestion. Tests name a case as
`091-AC-<n>`.

## AC-1 — A project that points origin at the template is still a project
**Given** a project with a register and a CORE script whose origin is `https://github.com/johanolofsson72/Claude.git` but whose history does not start at the template's root commit
**When** core-machinery-guard is asked about an edit of the CORE script, core-owed-tick-guard about a tick, autosync runs, and the agent runs `git remote set-url origin …`
**Then** both guards decide as for any project, autosync writes nothing and warns that the history is not the template's, the set-url is denied, and in a clone with the template's history the same calls still exempt it

## AC-2 — A pin off the template's main is never synced
**Given** a project with `CLAUDE_TEMPLATE_PIN` set to a commit that GitHub's compare API reports as diverged from main (a fork-network commit)
**When** autosync runs
**Then** nothing is downloaded or written and the run says it cannot show the pin is on the template's main, while a pin the API reports as behind main syncs as before

## AC-3 — update-template's model cannot write outside the repository
**Given** update-template.sh and a `claude` whose help lists `--restricted`
**When** a live run starts and the model adds a `hooks:` key to a skill's frontmatter
**Then** claude was started with `--restricted`, `--permission-mode dontAsk` and `--tools` naming only the allowed tools, `.mcp.json` edits are denied, the skill is named `[REVIEW]` and the script exits 4; a `claude` without `--restricted` makes the script refuse before the model starts

## AC-4 — An edited test un-trusts the nightly suite, and a cloud stamp marks no local job done
**Given** a trusted `.suite-command` that loops over `scripts/test-*.sh`, and a `claude/maintenance-results` file carrying a `secrets` stamp and a `mutation` stamp while mutation is placed local
**When** one test file's body changes and `cloud-maintenance.sh --pull` runs
**Then** the suite reads as changed and does not run unattended, and the pull imports neither stamp and names both as skipped

## AC-5 — Only Confirm, to a question that showed the cases, confirms them
**Given** a spec's acceptance.md whose digest is on disk
**When** the developer answers "No" to a question that shows the digest, or "Confirm" to one that leaves out a case, and separately a Confirmed line is committed locally but not pushed with no answer recorded
**Then** `--confirm` refuses both answers, the gate denies production source for the unpushed line, and "Confirm" to the `--question` text confirms

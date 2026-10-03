# Spec interview — 095-guard-fail-open-sweep

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO with human overflow. The row is `[hardened]` (security domain, new input surfaces), so the
three decisions that change what a guard lets through went to the developer (O1–O3). They cover
tampering, authorization of a new key and resource exhaustion. The base questions had defensible
recommendations.

## Q1 — Scope boundary
**Q:** What is in, what is out?
**A (auto):** In: F114, F115, F116, F118, F120, F121, F135 and F145's false positives, as R1–R13. Out:
`git pull` (bound, O3), runtime-assembled names (089 bound), MCP read tools, `.mcp.json`, the
developer's own git aliases, F144 (row 096).

## Q2 — Primary actor and trigger
**Q:** Who triggers the code this changes?
**A (auto):** The agent, through a PreToolUse call: Bash, Edit/Write, or an `mcp__*` tool. The
developer triggers R11 by running `update-template.sh`.

## Q3 — Happy-path outcome
**Q:** What does success look like?
**A (auto):** Every bypass in the spec's Problem table is denied with a reason that names the cause and
the developer's route. Every false positive in it is allowed with no output. Nothing else changes.

## Q4 — Data model
**Q:** What new state exists?
**A (auto):** None persisted. R2 replaces a tuple of guarded keys with a safe list; R10 adds a key
pattern list. The guards read git objects (R1) but write nothing.

## Q5 — Validation: what counts as a tree write (R1)
**Q:** How does the guard tell a tree-writing git call from a read?
**A (auto):** By subcommand and flags after the global options (`-C`, `-c`, `--git-dir`, …), as
`destructive_command.py` already parses them. A verb not on the R1 list is not a tree write.

## Q6 — Validation: which content the verb would write
**Q:** How is "the content the verb would leave" computed for each verb?
**A (auto):** checkout/switch/reset/read-tree with a revision: that revision's blob. checkout/restore
without a source: the index. stash pop/apply/branch: the stash commit (untracked files from its third
parent). stash push/save/bare: HEAD for tracked files, removal for untracked ones under `-u`/`-a`.
clean: removal of untracked (and with `-x`/`-X` ignored) files. History verbs: the change from base to
target. A path missing in the source is removal, compared as `{}`.

## Q7 — Success state
**Q:** What does an allowed call look like?
**A (auto):** Exit 0, no stdout. The same as every guard's allow today.

## Q8 — Error state
**Q:** What does a deny look like?
**A (auto):** One PreToolUse deny naming the guard, the spec (095), the cause in one line, and the
developer's routes (edit by hand, or `!`). The command text is never echoed.

## Q9 — Empty state
**Q:** What happens to a call with nothing to judge (no git verb, no guarded file in scope)?
**A (auto):** The pre-check exits 0 before Python starts, as today. A git tree verb whose repository has
no guarded file inside it is `none`.

## Q10 — Loading / undecidable state
**Q:** What happens when a guard cannot decide?
**A (auto):** R1 fails closed (a git error or timeout denies). R5 splits per O2. R6 treats a missing
`template-identity.sh` as `project`. The 089 crash rule stays: a crash denies, except an edit of the
guard's own files.

## Q11 — Authorization
**Q:** Who may make the changes these guards refuse?
**A (auto):** The developer, by hand or with `!`. There is no override variable, as in 089 O3 and 091.

## Q12 — Concurrency and ordering
**Q:** Can the guard's view of the repository be stale?
**A (auto):** Yes, by design. A PreToolUse guard judges the state at check time. A tree write allowed
because the revision matches the current file stays correct unless the developer edits the file
between the check and the call. That is the same window 089's /tla GAP-1 closed for Write. For git it
only matters if the developer's edit adds a hook the revision lacks, and then git refuses to overwrite
an uncommitted change on checkout/merge/stash pop. `restore`, `checkout -- path` and `reset --hard` do
not refuse; recorded as a bound in the header.

## Q13 — Integration points
**Q:** Which other parts does this touch?
**A (auto):** `bash-write-guard` delegates shell writes to both guards (unchanged contract).
`sync-core-hooks.py` carries the R4 matchers into projects. `template-identity.sh` is reused by R6.
`guard_announce` is reused by R5.

## Q14 — Edge cases: repositories
**Q:** Which repositories does R1 judge?
**A (auto):** The one git resolves for the command's directory (`-C` applied). Only the guarded files
inside its top level count. The config-dir `settings.json` is judged when it lives in that repository.

## Q15 — Edge cases: false positives
**Q:** Which harmless shapes must stay allowed?
**A (auto):** `git checkout HEAD -- .` with a clean settings file; `git stash pop` of a stash that does
not touch it; `git switch -c new`; `git restore --staged x`; `sed -n 1,5p` on a settings file;
`git diff -- scripts <settings-dir> | tail`; grep's `'[a-z]*'` pattern behind `xargs`; `--trust` in
`finding.sh` prose; `sed -i` on a scratch file whose script mentions `.git/config`; `git -c
core.fsmonitor=false status`.

## Q16 — Non-functional limits
**Q:** What does R1 cost?
**A (auto):** It runs only on a git tree verb. One `rev-parse --show-toplevel`, then one blob read
per guarded file per revision, each with the scan timeout (`CLAUDE_GUARD_SCAN_TIMEOUT`, default 5 s). A
plain `git status` never reaches it.

## Q17 — Information disclosure
**Q:** Can a deny leak something?
**A (auto):** The reason names the derived target path and the guarded keys that would change, never the
command text or a key's value. An `env` value can be a secret.

## Q18 — Reversibility
**Q:** How is this rolled back?
**A (auto):** `git revert` of the spec's commits. The R4 matcher edit is the developer's and reverts by
hand. No migration.

## Q19 — Acceptance criteria
**Q:** What is the measurable definition of done?
**A (auto):** SC-1 to SC-4 in spec.md, the five acceptance cases, the full template suite green, the
mutation gate at the hardened bar on the changed modules.

## Q20 — Non-goals and assumptions
**Q:** What is assumed?
**A (auto):** The agent runs as the developer's OS user. The developer's git config, aliases and origin
are trusted. Claude Code's PreToolUse matcher is a regular expression over the tool name, so
`mcp__.*` matches every MCP and plugin tool.

## O1 — Which keys does the settings guard protect? (overflow — F115, tampering/authorization)
**Q:** Keep hooks/disableAllHooks/env, extend the denylist, or invert to a safe list?
**A:** Invert: safe-list. Every top-level key is guarded except $schema, outputStyle, language, model,
attribution, includeCoAuthoredBy, cleanupPeriodDays, and permissions.allow/ask/additionalDirectories.
permissions.deny and defaultMode become guarded.

## O2 — What does a git timeout do in the acceptance gate? (overflow — F118, resource exhaustion)
**Q:** Keep 080 O6's fail-open everywhere, split by check, or fail closed on both?
**A:** Split by check. The Confirmed-line backing check fails closed on a timeout. The coverage scan
keeps O6's fail-open and announces it. `_git` drops the repository-redirect variables either way.

## O3 — How strict is the git tree-write check? (overflow — F114, tampering)
**Q:** Judge by content, judge by content and deny pull, or deny the verbs outright?
**A:** Judge by content. Deny only when the guarded keys would change or git cannot answer. `git pull`
stays allowed as a recorded bound.

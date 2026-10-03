# Spec interview — 095a-mod-loading-guard

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO with human overflow. The row is `[hardened]` (security domain, a new guarded surface), so
the decisions that change what the guard lets through went to the developer (Q3, Q8, Q13, plus the
threat-surface pair Q20–Q21). The base questions had defensible recommendations.

## Q1 — Scope boundary
**Q:** What is in, what is out?
**A (auto):** In: agent writes that create or change a loadable mod, through Edit/Write/MultiEdit/
NotebookEdit, Bash, git and MCP, plus the probe that measures where mods load. Out: shell startup
files exporting `CLAUDE_CODE_PLUGIN_DIRS` (F080's area), scripts the agent writes and runs, skill and
agent frontmatter command hooks (deny wins over allow), `.mcp.json`, managed settings.

## Q2 — Primary actor and trigger
**Q:** Who triggers the code this changes?
**A (auto):** The agent, through a PreToolUse call. The developer is the only actor who may create or
change a mod, by hand or with a `!` command.

## Q3 — Where the guard applies (overflow, M1)
**Q:** Load locations only, or any plugin folder anywhere?
**A:** Anywhere. Any `.claude-plugin/` path, any `hooks/hooks.json`, everything inside an existing
plugin folder, plus the load roots (skills roots and their children, `~/.claude/plugins`,
`~/.claude/dev-mods`, `CLAUDE_CODE_PLUGIN_DIRS`). Catches `--plugin-dir` folders wherever they live.

## Q4 — Happy-path outcome
**Q:** What does success look like?
**A (auto):** An agent write that would create or change a mod is denied with a reason naming the path
and the developer's route; every other call behaves exactly as before 095a.

## Q5 — Data model
**Q:** What new data does the guard keep?
**A (auto):** None persisted. Per call: the set of load roots (from env and `<config>/settings.json`
`env`), and a per-call cache of the ancestor walk. The verdict line gains three words: `mod-file`,
`mod-bash`, `mod-git`.

## Q6 — Which files make a plugin folder
**Q:** Is `.claude-plugin/plugin.json` required for a folder to load as a mod?
**A (auto):** No. Measured: `--plugin-dir` loads a folder with only `hooks/hooks.json` and the module.
So either marker makes a plugin folder, and both are guarded by name.

## Q7 — Module paths outside the folder
**Q:** Can `hooks.json` name a module outside its plugin folder, so that editing an outside file reloads it?
**A (auto):** No. Measured: `Path escapes plugin directory: ../../shared-register.ts`. The plugin
folder's own contents are the unit.

## Q8 — How 096 ships its mod (overflow, M2)
**Q:** dev-mods stays agent-writable, or staged source plus a developer-run install?
**A:** Staged source plus `!` install. `~/.claude/dev-mods` stays guarded. The agent writes the mod
under a name that does not load; a script the developer runs assembles it. 096 owns the script.

## Q9 — The four observable states
**Q:** What are success, error, empty and loading for a guard?
**A (auto):** Success: allow, no output. Error: deny with a reason naming the mod path, why, and the
route. Empty: a call naming nothing guarded exits 0 at the pre-check. Loading: n/a; a verdict that
crashes denies (fail closed), except an edit of the guard's own files.

## Q10 — Error semantics and wording
**Q:** What does the deny say?
**A (auto):** That a loaded mod can allow any tool call past every hook and run its own code; that
the developer creates or changes mods by hand, with `!`, or through 096's staged install; that there
is no override; that reads stay open. The command text is never echoed.

## Q11 — Authorization
**Q:** Is there an override variable?
**A (auto):** No, as in 089 O3. An override the agent could set is a bypass. The developer's routes
run outside the agent's tools.

## Q12 — Reads
**Q:** Are reads of plugin folders affected?
**A (auto):** No. Read tool, `cat`, `grep`, `ls`, `git diff/log/show` on a mod path pass. Writing is
the threat, not reading.

## Q13 — Git (overflow, M3)
**Q:** How is a tree-writing git verb inside or onto a plugin folder judged?
**A:** Like 095: by what git would write; denied when a mod path would be added, changed or removed.
A pull from a configured remote is allowed.

## Q14 — Concurrency and ordering
**Q:** Can a write land between the check and its run?
**A (auto):** The same assumption as 089 GAP-1. For Edit/Write the tool refuses a file changed since it
was read. A plugin folder created by the developer between check and run makes a previously
ordinary path a mod path; the guard judged the disk as it was, and the developer's own action is not
an attack. Recorded in the threat model.

## Q15 — Integration points
**Q:** Which guards and files change?
**A (auto):** `scripts/settings_guard.py` (mod path, verdict words, git candidates),
`scripts/settings-edit-guard-hook.sh` (pre-check, deny text), `scripts/test-settings-edit-guard.sh`,
docs. The matcher already covers Edit/Write/MultiEdit/NotebookEdit/Bash/`mcp__.*` (095 R4).
bash-write-guard and trust-anchor-guard are unchanged.

## Q16 — Edge: an existing skill folder
**Q:** Does the template's own `.claude/skills/<name>/SKILL.md` stay editable?
**A (auto):** Yes. A file in a skill folder is a mod path only under `hooks/`, under `.claude-plugin/`,
or when the folder is already a plugin folder. The skill folder itself is guarded against shell
writes that replace it whole (`mv`, `cp -r`, `ln -s`), not against Edit of a file in it.

## Q17 — Edge: symlinks and case
**Q:** What about a symlink into a plugin folder, or `.Claude-Plugin` on macOS?
**A (auto):** Paths are compared after realpath and NFC, case folded on a case-folding file system,
in both the resolved and the unresolved spelling. Creating a symlink inside a zone is itself a write.

## Q18 — Edge: the template's own test fixtures
**Q:** The self-test needs plugin folders as fixtures. How does it create them?
**A (auto):** Inside the test script, which the agent runs with `bash scripts/test-…sh`. The command
names the script, not the fixture paths, so the guard does not see the writes: the declared bound,
and it is how every guard's fixtures are made.

## Q19 — Non-functional limits
**Q:** What does the guard cost per call?
**A (auto):** The pre-check stays in bash; the ancestor walk is at most 64 `test -e` pairs and runs only
for Edit/Write `file_path` and the payload `cwd`. The Python verdict caches the walk per path. The git
route adds one `ls-files` and one `ls-tree -r --name-only` per named revision.

## Q20 — Threat surface: resource exhaustion (overflow)
**Q:** A huge repository or deep tree makes the git route's candidate listing slow. What then?
**A:** Deny on timeout, as 095: any git call that fails or times out (GUARD_GIT_TIMEOUT) denies the
tree write with a cause. The ls-tree output is filtered line by line, so the Python side stays linear.
No cap that fails open.

## Q21 — Threat surface: information disclosure (overflow)
**Q:** The deny names the mod path it refused. Is that acceptable?
**A:** Yes, name the path. It is what the agent itself asked to write, and it tells the developer what
was attempted. The command text stays unechoed, as in 089.

## Q22 — Acceptance criteria
**Q:** What is the measurable definition of done?
**A (auto):** SC-A to SC-D in spec.md, the acceptance cases in acceptance.md, the full suite green and
the hardened mutation gate met on the changed lines.

## Q23 — Non-goals and assumptions
**Q:** What is assumed?
**A (auto):** That Claude Code loads mods only from a folder holding `.claude-plugin/` or
`hooks/hooks.json`, and only from the measured locations plus the documented project skills folder.
The probe (R8) rechecks this after an update.

## Q24 — Reversibility
**Q:** How is this undone?
**A (auto):** Revert the commit. No data migration. A developer who needs the agent to work on a plugin
repository opens that work in a session the developer controls, or moves the markers aside with `!`.

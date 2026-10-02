# Spec interview — 089-settings-edit-guard

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO (base auto-answered with recommended; genuinely-ambiguous escalated; overflow human-answered if flagged).
Flag: hardened (authorization layer under every hook, tagged row, new hook + module ≥ 6 files), so the four policy questions went to the developer as overflow (O1–O4), all of them threat-surface: which files, which keys, who may override, whether the template is exempt.

## Q1 — Scope boundary
**Q:** Which findings does 089 close?
**A (auto):** F081 and F103, the two the row names. Both are the same hole seen from two specs: no guard on the files that wire the guards.

## Q2 — Scope boundary: hook scripts themselves
**Q:** Does 089 also stop the agent from editing a hook script into `exit 0`?
**A (auto):** No. In a project `core-machinery-guard` already covers the CORE scripts; in the template that is the residual every guard here shares. 089 is about the wiring file, not the wired code.

## Q3 — Primary actor
**Q:** Who is the adversary?
**A (auto):** The agent being gated: Claude in a session, using Edit/Write/MultiEdit/NotebookEdit/Bash as the developer's own OS user. A same-user process can always write a same-user file. The goal is that switching a gate off needs a conspicuous act a guard refuses, not that it becomes impossible.

## Q4 — Happy path
**Q:** What changes for an ordinary session?
**A (auto):** Nothing visible. Reading settings (Read tool, `cat`, `jq`, `grep`, `python3 -m json.tool <file>`) and committing them (`git add`, `git commit`) still work. An Edit of `permissions` or `outputStyle` still works. Only a change to `hooks`, `disableAllHooks` or `env`, or a shell write to one of the three files, is refused.

## Q5 — Data model
**Q:** Does 089 add persisted state?
**A (auto):** None. The verdict compares the current file with the simulated result in memory. No store, no stamp, no log.

## Q6 — Validation: what is "the same value"?
**Q:** How are the before and after values compared?
**A (auto):** Parsed JSON, deep equality per key, with "absent" as its own value. Re-indenting, reordering keys inside `hooks`, or adding a trailing newline is not a change. Reordering entries of a hooks array is a change, because the order is the order they run in.

## Q7 — Validation: invalid JSON
**Q:** What happens to a write that leaves the file unparseable?
**A (auto):** Denied (`settings-invalid`). Claude Code ignores a settings file it cannot parse, so a broken file unwires every hook in it. A current file that is already broken is denied too (`settings-unreadable`): there is nothing to compare with, and the developer fixes it.

## Q8 — The four observable states
**Q:** What does the agent see in each state?
**A (auto):** Success: no output, the call proceeds. Error: a deny with a reason that names the file, the guarded key or the shell route, and the developer's two routes. Empty: a call that names no guarded file exits in the bash pre-check with no output. Loading: none; a PreToolUse hook is synchronous, and the verdict is bounded by python3 start-up (tens of milliseconds) on the calls the pre-check passes on.

## Q9 — Error semantics
**Q:** Is a deny recoverable?
**A (auto):** Yes, by the developer: they edit the file by hand or run `! <command>`. The deny tells the agent to show the developer the exact JSON change it wanted. A crash is fatal for the call (deny) except on the guard's own files.

## Q10 — Authorization: unauthenticated actors
**Q:** Is there any actor the guard lets through?
**A (auto):** The developer, by construction: hand edits and `!` commands never pass through PreToolUse. The SessionStart autosync runs `sync-core-hooks.py` as a hook, not an agent tool, so project wiring still lands. There is no environment override (O3).

## Q11 — Concurrency
**Q:** Can two calls race the check?
**A (auto):** The verdict reads the current bytes when the call is judged. A Bash call running in the background that rewrites the file between the check and a later Edit is itself a Bash call the guard judged. Tool calls in one session run one at a time from the harness's side; parallel tool calls are each judged on the bytes they see, and an Edit whose `old_string` no longer matches fails in the tool.

## Q12 — Integration: bash-write-guard
**Q:** How does it relate to bash-write-guard?
**A (auto):** It joins `BASENAME_GUARDS` as the seventh delegate, with its own lead line. A delegated payload has a path and no bytes, so it lands in `settings-shell`. The guard is also wired on Bash directly, because `rm`, `ln`, `touch`, `git checkout --` and `cp` into a directory are not shapes the extractor claims.

## Q13 — Integration: projects
**Q:** How does a project get it?
**A (auto):** `CORE_SCRIPTS` ships the hook, the module and the test; the template `settings.json` carries the wiring, and `sync-core-hooks.py` adds it at the next SessionStart sync because the script is present on disk.

## Q14 — Edge cases: settings.local.json absent
**Q:** Can the agent create `settings.local.json`?
**A (auto):** Yes, without guarded keys: a missing file reads as `{}`, so a Write with only `permissions` is allowed and one with `env` is denied.

## Q15 — Edge cases: links
**Q:** What about a symlink or hard link to a settings file?
**A (auto):** A symlink is judged where it lands (realpath). A hard link is judged by inode against the existing guarded files. Creating either with `ln` names a guarded file and is denied by R4.

## Q16 — Edge cases: case and Unicode
**Q:** `.CLAUDE/Settings.json` on macOS?
**A (auto):** Same file on a case-insensitive volume, so the comparison folds case on macOS and Windows, and normalises to NFC everywhere (macOS file names come back in NFD).

## Q17 — Non-functional limits
**Q:** What does it cost per call?
**A (auto):** The bash pre-check exits for a call naming neither `sett` nor `.cla` and holding no glob, `$'` or link. Others pay one python3 start. A Write payload is read from stdin, not the environment (the 088 128 KB lesson).

## Q18 — Acceptance criteria
**Q:** What proves it?
**A (auto):** `scripts/test-settings-edit-guard.sh`, naming 089-AC-1 … AC-5, with sabotage arms; the bash-write-guard route; the template suite green; `run-mutation-gate.sh --module scripts/settings-edit-guard-hook.sh` at or above 80 %.

## Q19 — Non-goals and assumptions
**Q:** What is assumed about Claude Code?
**A (auto):** That hooks come only from settings files and plugins, that `disableAllHooks` is the one key that switches all of them off, and that `CLAUDE_PROJECT_DIR` names the project root in a hook's environment. All three are the documented behaviour.

## Q20 — Reversibility
**Q:** How is it rolled back?
**A (auto):** The developer removes the hook entry from `settings.json` by hand. That is the point: the off switch belongs to the developer.

## O1 — Which files (overflow, developer)
**Q:** Which settings files should the guard cover?
**A:** Session's three: `<project>/.claude/settings.json`, `<project>/.claude/settings.local.json` and `~/.claude/settings.json`. Another project's settings stay writable.

## O2 — Which keys (overflow, developer)
**Q:** Which keys count as a guarded change?
**A:** `hooks`, `disableAllHooks`, `env`. Permissions, outputStyle, statusLine and the rest stay editable by the agent.

## O3 — Override (overflow, developer)
**Q:** Should there be an override for the agent?
**A:** None. The developer edits by hand or runs a command with the `!` prefix.

## O4 — Template repository (overflow, developer)
**Q:** Does the guard apply in the template repo itself?
**A:** Guarded here too. Future specs that wire a hook hand the developer the exact JSON or a `!` command.

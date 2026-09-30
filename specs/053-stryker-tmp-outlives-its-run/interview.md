# Spec interview — 053-stryker-tmp-outlives-its-run

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. Spec-only, no hardening trigger (no new surface, no entity, three files), so no overflow.

## Q1 — Scope boundary
**Q:** What is in, what is out?
**A (auto):** In: a sweep of abandoned StrykerJS temp directories at the start of a Stryker run, from the hook and from `--full`. Out: removing the existing exclusions, `npm run` scripts, automatic backup restore.

## Q2 — Primary actor
**Q:** Who is hurt today?
**A (auto):** A developer on a JS project whose killed or failed mutation run left a project copy in the tree; every walker (audits, linters, test runners) then sees duplicate `package.json` files (msroute F007).

## Q3 — Happy path
**Q:** What does done look like?
**A (auto):** Starting a Stryker run removes whatever the last abandoned run left, so at most the live run's sandbox exists at any time.

## Q4 — Sweep on entry vs relocate tempDirName
**Q:** Which of the two fixes the diagnosis names?
**A (auto):** Sweep on entry. StrykerJS docs advise keeping the temp dir in the repository, the sandbox resolves `node_modules` from there, and `tempDirName` is project-owned config.

## Q5 — Which directories
**Q:** Only `.stryker-tmp`, or a configured name too?
**A (auto):** Both. `.stryker-tmp` anywhere, plus a plain one-segment `tempDirName` read from `stryker.conf.*`/`stryker.config.*` (the Jest-on-Windows advice renames it to `stryker-tmp`). A name with a slash, `.` or `..` is ignored.

## Q6 — What proves a directory is Stryker's
**Q:** How does the sweep avoid deleting a user directory that happens to share the name?
**A (auto):** Every entry must be a `sandbox-*` directory (or the directory is empty). Anything else keeps it and the reason names the entry.

## Q7 — In-place backups
**Q:** What about `backup-*` from an interrupted `inPlace` run?
**A (auto):** Never deleted. It can hold the only copy of the original sources. The hook denies the next run and maintenance refuses it, both naming the path.

## Q8 — Live run
**Q:** How is a live run protected?
**A (auto):** No removal while any Stryker process (Stryker.NET, the runner, a node process running StrykerJS) has its working directory inside the root.

## Q9 — Blind process table
**Q:** Unreadable `ps` or cwd — sweep or keep?
**A (auto):** Keep. A wrong delete destroys a live run; a missed sweep only defers it to the next start.

## Q10 — cleanTempDir: false
**Q:** A project that set `cleanTempDir: false` wants the sandbox kept for debugging. Sweep it?
**A (auto):** No. Kept, with the reason printed.

## Q11 — Symlinks and tracked content
**Q:** A symlinked temp directory, or one with git-tracked files?
**A (auto):** Both kept. A symlink is never followed; tracked content means someone committed it on purpose or by mistake, and deleting tracked files is a change to the repo, not a cleanup.

## Q12 — Observable states
**Q:** Success / error / empty / loading for a script?
**A (auto):** Success: `removed` lines. Specific error: `kept`/`backup` lines with a reason. Empty: no output. Loading: N/A (synchronous).

## Q13 — Channel into the model
**Q:** How does the hook tell Claude what it swept?
**A (auto):** PreToolUse `additionalContext` with `hookEventName: "PreToolUse"` (bash-write-guard precedent); a `backup` is a deny.

## Q14 — Which commands trigger the hook sweep
**Q:** What counts as starting a StrykerJS run?
**A (auto):** A program resolving to `stryker` / `@stryker-mutator/core` whose first non-option argument is `run`, reached directly, via `node`, or via `npx`/`bunx`/`pnpx`, `pnpm`/`yarn`/`npm exec`. `stryker init` and text mentions do not.

## Q15 — Does JS detection change the run-alone deny?
**Q:** Will a live StrykerJS now deny `dotnet build`?
**A (auto):** No. The JS kind is used only by the sweep; the F069 deny keeps its .NET-only kinds.

## Q16 — Cost on every Bash call
**Q:** Does the hook get slower?
**A (auto):** Only for commands that start a Stryker run, and only when a temp directory exists does it read `ps`.

## Q17 — Acceptance
**Q:** Measurable done?
**A (auto):** AC1-AC12 in the spec as self-test arms in `test-stryker-guard.sh` and `test-project-maintenance.sh`, red before the change.

## Q18 — Reversibility
**Q:** Undo?
**A (auto):** The deleted directories are regenerated sandboxes. `STRYKER_GUARD=off` disables the hook half; reverting the commit removes the rest.

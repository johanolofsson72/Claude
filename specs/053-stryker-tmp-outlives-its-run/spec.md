# 053 — stryker-tmp-outlives-its-run

Track: spec-only. No entity, no state machine. Three scripts plus their tests: `scripts/stryker_guard.py`,
`scripts/stryker-guard-hook.sh`, `scripts/project-maintenance.sh`. No hardening trigger fires (no new
surface; the only new side effect is deleting directories StrykerJS created, under the rules below).

Evidence: msroute F007, 2026-09-08, and msroute row `007cm`. Diagnosis in `specs/INDEX.pending.md`.

## The defect

StrykerJS writes its sandboxes to `<tempDirName>/sandbox-*` (default `.stryker-tmp`) and removes the
directory only after a *successful* run (`cleanTempDir: true`, the default). A run that is killed, times
out or fails its `break` threshold leaves the whole tree behind: a copy of the project, `package.json`
files included. Every tool that walks the tree then trips over it — msroute had to teach
project-freshness, project-maintenance, vitest and eslint to exclude it, one at a time. The next
consumer will have to learn it too.

Moving `tempDirName` outside the tree is not the fix: StrykerJS resolves `node_modules` from the sandbox,
its docs advise keeping the directory inside the repository, and the setting is project-owned config the
template does not write.

## Requirements

- **FR-01** `python3 scripts/stryker_guard.py sweep <root>` finds every StrykerJS temp directory under
  `<root>`: any directory named `.stryker-tmp`, plus `<config dir>/<tempDirName>` for each
  `stryker.conf.*` / `stryker.config.*` that declares a plain relative `tempDirName` (one path segment,
  not `.` or `..`). The walk prunes `node_modules`, `.git`, `bin`, `obj`, `StrykerOutput` and does not
  descend into a temp directory.
- **FR-02** A temp directory is removed only when it is **abandoned and plainly Stryker's**: every entry
  is a directory named `sandbox-*`, it is not a symlink, git tracks nothing inside it, and the config
  beside it does not set `cleanTempDir: false`. An empty temp directory is removed too.
- **FR-03** An entry named `backup-*` means an in-place run was interrupted and the backup may hold the
  only copy of the original sources. That directory is **never** removed; it is reported as `backup`.
- **FR-04** Nothing is removed while a Stryker run (Stryker.NET, the project runner, or a StrykerJS node
  process) is live in `<root>`, or while the process table or a candidate's working directory cannot be
  read. Deleting is the destructive direction, so blindness keeps.
- **FR-05** Output is TSV, one line per temp directory: `removed<TAB>path<TAB>detail` or
  `kept<TAB>path<TAB>reason` or `backup<TAB>path<TAB>sentence`. No candidates → no output and no `ps`.
  Exit 0.
- **FR-06** The PreToolUse hook sweeps when a command starts a Stryker run — `dotnet stryker`, the
  project runner, or a StrykerJS run (`stryker run` via a bare bin, `npx`, `bunx`, `pnpm`/`yarn`/`npm exec`,
  `node …/stryker`) — and the command is not otherwise denied. A `backup` result **denies** the command,
  naming the path and how to recover. Removed/kept results reach the model as `additionalContext`.
- **FR-07** `project-maintenance.sh --full` sweeps immediately before it starts the mutation command. A
  `backup` result is a `[MUTATION] NOT RUN` finding (not stamped). Removed/kept are notes.
- **FR-08** The existing `.stryker-tmp` exclusions stay: a *live* run's sandbox still exists while it
  runs, and a consumer walking the tree then must still skip it.

## Acceptance

- AC1 an abandoned `.stryker-tmp/sandbox-a` → removed, reported `removed`.
- AC2 same, nested at `client/.stryker-tmp` → removed.
- AC3 a `backup-x` entry → kept, reported `backup`; hook denies `npx stryker run`; maintenance NOT RUN.
- AC4 an unexpected entry (a file, or a `notes/` dir) → kept, reason names it.
- AC5 `cleanTempDir: false` in the config beside it → kept.
- AC6 a live StrykerJS node process in the project → kept; one in another project → removed.
- AC7 a symlinked `.stryker-tmp` → kept, target untouched.
- AC8 git-tracked content inside → kept.
- AC9 `tempDirName: "stryker-tmp"` in `stryker.conf.json` → that directory is swept; a `tempDirName`
  of `../x` or `.` is ignored.
- AC10 hook: `npx stryker run`, `pnpm exec stryker run`, `node node_modules/.bin/stryker run`,
  `dotnet stryker` sweep; `npx stryker init`, `echo stryker run`, `grep stryker` do not.
- AC11 hook: the sweep result arrives as PreToolUse `additionalContext` with `hookEventName`.
- AC12 no temp directory → no output, no process-table read; existing G1-G46 stay green.

## Out of scope

`npm run <script>` that happens to call Stryker (the script body is not read; the project runner and
`--full` cover the declared route). Sweeping on a plain maintenance pass (the sweep belongs to the next
run's start; deleting on a report-only pass would surprise). Removing the four consumer exclusions
(FR-08). Restoring an in-place backup automatically.

## Clarifications

### Session 2026-09-30

- Q: Sweep on entry, or move `tempDirName` out of the tree? → A: Sweep on entry. Moving the directory
  breaks module resolution from the sandbox and means writing project-owned config.
- Q: What if the leftover is from an in-place run? → A: Never delete; deny the next run and say how to
  recover. The backup can be the only copy of the unmutated source.
- Q: Unreadable process table — sweep or keep? → A: Keep. The hook's run-alone check fails open because
  a false deny costs hours; here a false delete costs a live run, so the asymmetry flips.

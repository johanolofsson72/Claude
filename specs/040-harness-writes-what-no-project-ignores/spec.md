# 040 — harness writes what no project ignores

Track: spec-only. No entity, no state machine, no new external surface. Not hardened, and the call
was close enough to state: four scripts change (one new helper, its test, the sync, the markers
test) plus two docs and the template's own `.gitignore`. The ≥6-files trigger counts risk-bearing
files, and three of the seven are prose or config. What does carry risk is a new unattended write
into a file every project owns, so the spec gets a threat-model section anyway (below).

Evidence: hetznerradar T0, 2026-09-07 (finding F005). Diagnosis in `specs/INDEX.pending.md`.

## The defect

`.gitignore` is deliberately outside the synced set; a project's ignore file is its own. The
harness still writes files it knows are machine-local, and the only thing that carries that
knowledge into a project is prose: section 3a of `.claude/skills/sync-template/SKILL.md`, applied by
hand during `/project-update`. A project that only autosyncs, or that was bootstrapped any other
way, learns none of it. hetznerradar committed 109 `.claude/state/attempts/` files and had a
`.bash-write-marker` deletion in `git status` at session start. A committed
`.claude/settings.local.json` is worse: it holds `SPEC_OWNER` and `CLAUDE_TEMPLATE_AUTOSYNC`, so
two lanes fight over one machine's identity.

## Decision

1. **One list.** `scripts/harness-gitignore.sh` (CORE) holds the machine-local patterns, each with
   a reason. `--list` prints the patterns. Nothing else carries its own copy: SKILL.md 3a and
   sync-prompt.md point at the helper, and `test-runtime-markers-ignored.sh` assertion D reads the
   helper instead of SKILL.md.
2. **A managed block.** `--apply <root>` owns the lines between
   `# >>> claude-code harness (managed by scripts/harness-gitignore.sh) >>>` and
   `# <<< claude-code harness <<<` in `<root>/.gitignore`. It appends the block once at the end of
   the file and afterwards rewrites it in place. Every byte outside the markers is left exactly as
   it was. Prints `added` (no `.gitignore` existed), `updated` (the file changed) or nothing.
   `--check <root>` answers the same without writing.
3. **Autosync runs it** after the copy loop, from the template's copy of the helper, and records
   `.gitignore` via `record_add` / `record_write`, so it is committed with the sync and listed by
   `--dry-run`. `--check`, `--dry-run` and a deferred run write nothing.
4. **Tracked files are reported, not untracked.** `--tracked <root>` lists what the index already
   holds under the managed patterns, collapsed to the directory that matched, with the
   `git rm -r --cached` line to run. The sync renders it as `[tracked]` at every exit that reports
   (the `[ok]` early exit, the check block, the end of a full sync). It is silent when nothing
   matches. Ignoring a tracked file changes nothing, so an ignore without this report is a green
   light nobody earned.
5. **The template dogfoods it.** The template's own `.gitignore` carries the rendered block, and a
   test fails when `--check .` in the template says it would change.

## Managed set

`.claude/state/`, `.claude/validation/`, `.claude/.maintenance-state`, `.claude/.template-sync-check`,
`.claude/.bash-write-marker`, `.claude/.bash-write-blocked`, `.claude/.local-llm-*`,
`.claude/local-llm-*.log`, `.claude/local-llm-*.log.errors`, `.claude/graphify-*.log`,
`.claude/graphify-*.log.errors`, `.claude/settings.local.json`, `.claude/projects/`,
`.claude/worktrees/`, `.specify/feature.json`, `__pycache__/`, `CLAUDE.local.md`.

That is every entry in the diagnosis's eight, plus the paths CORE hooks write that the template
already ignores for itself: local-LLM and graphify logs, `.claude/validation/` (stop-validation),
`.claude/worktrees/` (agent isolation, pruned by `prune-agent-worktrees.sh`),
`.specify/feature.json` (`sync-feature-json-hook.sh`) and `CLAUDE.local.md`. `.playwright-mcp/` is a
plugin's scratch, not the harness's, and stays in the template's unmanaged section.

## Functional requirements

- **FR-01** `--list` prints one pattern per line, the patterns only.
- **FR-02** `--apply` on a project with no `.gitignore` creates it with the block and prints `added`.
- **FR-03** `--apply` on a `.gitignore` without the block appends it after the existing content,
  inserting a newline first if the file lacks a final one, and prints `updated`.
- **FR-04** `--apply` on a file whose block is current prints nothing and does not touch the file
  (mtime unchanged).
- **FR-05** `--apply` on a stale block (an old list, hand-edited lines inside) rewrites only the block;
  bytes before and after it are unchanged.
- **FR-06** CRLF files get a CRLF block. The markers are recognised with or without `\r`.
- **FR-07** A start marker with no end, an end with no start, or two blocks → nothing written, a
  message naming the problem, exit 3. The sync reports it as `[gitignore]`.
- **FR-08** `--check` prints what `--apply` would print and writes nothing.
- **FR-09** `--tracked` prints the paths the index holds under the managed patterns, collapsed to the
  topmost directory any pattern matches, glob patterns included; empty when none. Outside a git repo it prints nothing and exits 0.
- **FR-10** The sync commits `.gitignore` with its other writes, lists it under `--dry-run`, and writes
  nothing under `--check` / `--dry-run` / deferral.
- **FR-11** The sync reports `[tracked]` with the count, up to 10 paths, and one `git rm -r --cached`
  line, at the `[ok]` exit, in the check block and after a full sync. Silent when empty.
- **FR-12** `test-runtime-markers-ignored.sh` D reads the helper's list; every MACHINE_LOCAL path must be
  covered by it. `.claude/settings.local.json`, `.claude/projects/`, `.claude/worktrees/`,
  `.specify/feature.json` and `scripts/__pycache__/` join MACHINE_LOCAL.
- **FR-13** The template's `.gitignore` carries the current block (`--check .` prints nothing).

## Scenarios

- SC-040-01 no `.gitignore` → created with the block, `added`.
- SC-040-02 project `.gitignore` without the block → block appended, every original byte kept.
- SC-040-03 no final newline → newline inserted before the block, original bytes otherwise kept.
- SC-040-04 second `--apply` → silent, file untouched.
- SC-040-05 stale block (an entry missing, a hand-added line inside) → block rewritten, bytes outside identical.
- SC-040-06 CRLF file → block written with CRLF, second apply silent.
- SC-040-07 start marker without end → exit 3, file unchanged.
- SC-040-08 two blocks → exit 3, file unchanged.
- SC-040-09 `--check` on a file needing the block → prints `updated`, file unchanged.
- SC-040-10 `--tracked` with 3 files under `.claude/state/attempts/` and one `scripts/__pycache__/x.pyc`
  → prints `.claude/state` and `scripts/__pycache__`.
- SC-040-11 `--tracked` on a clean project → prints nothing.
- SC-040-12 the sync against a project with no block → `.gitignore` in the sync commit, `add`/`update`
  listed under `--dry-run`, the working tree clean afterwards.
- SC-040-13 the sync with tracked machine-local files → `[tracked]` with the `git rm` line, at the full
  sync and at the next `[ok]` exit.
- SC-040-14 `--check` sync → `.gitignore` untouched.
- SC-040-15 a line outside the block that un-ignores (`!.claude/state/`) placed before the block is
  overridden, because the block is appended last. A negation after the block is the project's call and is
  left alone.
- SC-040-16 markers test D fails when the helper's list drops `.claude/state/`.

## Threat model

The new surface is one unattended write into a project-owned file, running at every session start.

- **Tampering / hiding work.** An over-broad pattern hides a file the project means to commit. The
  set is enumerated, every entry is anchored under `.claude/` or `.specify/` or names a cache or local
  file, and `test-runtime-markers-ignored.sh` B still fails when any tracked-by-design record
  (`.claude/.template-sync`, `.sync-stack`, `.sync-local`, `.template-sync-verify`, `.runtime-markers`)
  becomes ignored.
- **Destroying project lines.** A marker bug could eat the project's own ignores. The rewrite touches
  only the span between two exact marker lines, refuses on any malformed pairing, and is written to a
  temp file and moved into place.
- **Removing tracked files.** Never done by the sync. `git rm --cached` is printed for a human to run.
- **Information disclosure.** None new. The report names paths already in the index.

## Out of scope

- Untracking files automatically.
- Classifying markers written by project-only hooks (that stays `.claude/.runtime-markers`).
- Rewriting the template's own `.gitignore` comments beyond moving the managed lines into the block.

## Clarifications

### Session 2026-09-29

- Q: Append the block at the end or the top? → A: The end. Git applies the last matching rule, so a
  block at the end cannot be undone by an earlier project line. A project that really wants to track
  one of these writes a negation after the block, which the sync leaves alone.
- Q: Should the sync untrack what is already committed? → A: No. It reports, with the command.
  `git rm --cached` rewrites what the next commit records, and doing that unattended at a session
  start, possibly under another developer's lane, is not the sync's call.
- Q: Where does the list live, given `.txt` files are not synced? → A: Inside a CORE script
  (`harness-gitignore.sh`). CORE scripts are always synced, and `--list` is how the other readers ask.

# 049 — a-held-row-cannot-be-written-to

Track: spec-only. No entity, no state machine, four files touched (resolver, hook, rule, test). No
hardening trigger fires.

Evidence: ighweld-2026 F139 (spec 145, a held row) and F195 (spec 160, a ticked row). Both notes
were appended to `run-log.md` by hand. Diagnosis in `specs/INDEX.pending.md`.

## The defect

`spec-run-log-hook.sh --note` has two ways to find its spec directory: `--spec <dir>`, or the
register's active row through `spec_active.py`. The resolver skips `- [!]` and `- [x]` rows, which
is correct for its question ("which row should I work?"). The note's question is "which row is this
note about?", and it gets the same answer.

So the moment a row is held (`.claude/rules/spec-register.md`, register rewrite step 1) or ticked,
the implicit call no longer finds it. What happens next depends on the row below:

- the next row has no directory yet (the usual case) → exit 4, "resolver named no directory";
- every row is ticked → exit 3, "no active spec row";
- the next row already has a directory → the note is filed on the **wrong spec**, exit 0.

`--spec <dir>` still works, but it wants a path, and neither error message says so. Both ighweld
sessions reached for the file by hand instead.

## Decision

1. **`--spec` takes a register id as well as a directory.** `--spec 049`, `--spec H1`,
   `--spec 007m`. The id is looked up by the same `<id>-*` glob the resolver uses, through a new
   `spec_active.py --id <id>` mode, so there is still one implementation of "where does this id's
   directory live". The row's status plays no part: pending, in progress, held and ticked rows all
   resolve. This is the fix F195 proposed.
2. **A directory still wins.** An argument that names an existing directory is used as-is, exactly as
   today. Only an argument that is not a directory is read as an id.
3. **The implicit path does not change which row it picks.** It still answers "which row should I
   work?". Making it prefer held rows would send every note on this register to 020 or 075, which
   have been held for weeks.
4. **Every "note NOT recorded" from the implicit path points at the way out.** When resolution fails
   (exit 3 or no directory), stderr also says that a held or ticked row is named with
   `--spec <id>` and lists the held rows by id. Nobody should need to read the source to find the
   flag.

## Functional requirements

- **FR-01** `spec_active.py --id <token> [--root DIR]`: a well-formed id with a directory → exit 0,
  JSON `{"id","dir","found":true,"status"}`, where `status` is the row's marker or `null` when no
  row carries the id. No directory → exit 4 with `"found": false`. A malformed token → exit 2. The
  glob is shared with `resolve()`, not copied.
- **FR-02** `spec-run-log-hook.sh --note T --spec <id>` records the note in that id's directory
  whatever the row's status (`[ ]`, `[/]`, `[!]`, `[x]`). Exit 0, silent.
- **FR-03** `--spec <id>` naming no directory → exit 4, stderr names the id. A malformed id → exit 2
  (the caller's fault, fixable).
- **FR-04** `--spec <existing dir>` behaves exactly as before, including when a same-named id exists.
- **FR-05** Implicit `--note` failure paths (exit 3, and exit 4 for no directory) add the hint
  `--spec <id>` and name the register's held rows.
- **FR-06** The implicit happy path is unchanged: same row, silent, exit 0.
- **FR-07** Usage strings, the header comment and `.claude/rules/spec-register.md` "Failure memory"
  name `--spec <id|dir>`.

## Non-goals

- Changing which row the implicit path resolves (Decision 3).
- Detecting a note filed on the next row after a hold when that row already has a directory. The
  hook cannot tell a note meant for row N+1 from one meant for held row N. The hint and the rule text
  are the mitigation.
- Showing a held row's run-log tail at SessionStart. That is the orientation hook's contract, not
  this one; recorded as a finding if it turns out to matter.
- Owner-lane filtering for `--spec <id>`. Naming an id is explicit, so the other lane's row is
  writable. The lane rule governs ticking and starting, not logging.

## Clarifications

### Session 2026-09-30

- Q: Should the implicit path fall back to a held row when no pending row has a directory? → A: No.
  The fallback would pick among held rows by position, and on a register with old holds that is a
  guess. Fail with the hint instead.
- Q: An id that has a directory but no register row, is that allowed? → A: Yes, with
  `"status": null`. The directory is what the note needs. An archived or renumbered row still owns
  its directory.
- Q: Accept the bare directory name (`049-a-held-row-…`) as an id? → A: It already works today when
  the cwd is the project root, because it is an existing directory. Otherwise it is not a
  well-formed id and exits 2. No new path for it.
- Q: Exit code for a malformed id: 2 or 4? → A: 2. It is a usage error the caller can fix, the same
  class as an unknown flag.

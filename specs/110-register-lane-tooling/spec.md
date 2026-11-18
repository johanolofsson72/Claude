# 110 — register lane tooling

Track: spec-only. No new entity, state machine or external surface. Every change corrects how an
existing script reads a file it already reads, or adds an opt-in input to an allocator. Not
hardened: no risk domain, no new trust boundary, fewer than six production files per concern.
Findings: F197, F198, F199, F210, F213, F214, F215, F217, F218, F219, F237, verbatim in
`specs/FINDINGS.md`.

## Problem

| Finding | What is wrong today |
|---|---|
| F198, F213 (allocator) | `finding.sh` and `next-scenario-id.sh` take one past the highest id in the working tree and every ref. Ids the other lane has minted and not pushed are invisible, so two parallel specs draw the same F-ids and SC blocks (agentcrm F595/F596, F621–F624; SC 123/126). |
| F213 (gate) | Reported as missing. It is not: `validate-scenario-traceability.sh` already exits 6 and names every id on two rows, split layout included (agentcrm today: 143). No test pins the cross-file case, so it can regress silently. |
| F217, F218, F219 | `checkpoint-cadence.sh` takes the last ticked checkpoint in FILE order. A milestone-ordered register (rocky: H16 at line 106, H13 at 274) reads "8 since H13, due" when 3 specs were ticked since H16. |
| F210 | Three readers find a lane owner tag only at the end of a row (`lane_status.py`, `spec_active.py`, `spec-register-orientation-hook.sh`). A row ending `@johan approved F612` reads as unclaimed, so both lanes can start it. |
| F214 | `lane_status.py` counts every row in PHASE-DEBT's `## Open` table. Rows the Cleared column marks `☑` are counted as open; the project's banner already skips them, so one session start shows 218 and 113. |
| F197 | `archive-completed-rows.sh` decides membership by the row's whole text. A row shortened to a pointer after archiving is appended again. On a register whose rows were all shortened that is one duplicate per row on the first run (agentcrm: 91). |
| F199 | `scenario-map-reminder-hook.sh` takes the slug from the edited file's parent directory, so `specs/093-x/checklists/requirements.md` yields `checklists` and a false scenario gap. |
| F215 | `context-budget.sh`, in a synced project, treats every rule as template-owned and sends the whole overage upstream. Local non-CORE rules are the project's to trim (agentcrm: 25 922 of 49 471 rule bytes). |
| F237 | `validate-scenario-traceability.sh` reads the underscore form only when followed by `_`. `Foo_SC040()` is not read, so a covered row is reported uncovered. |

## Requirements

- **R1 — Lane-striped allocation (F198, F213).** `max-id-in-refs.sh --next <count> [--block <B>]`
  prints the first id of a run of `count` free ids above the highest it can see. With
  `SPEC_LANE_SLOT=<k>/<n>` set (1 ≤ k ≤ n), the id space is cut into blocks of `B` ids
  (block 0 = ids 1..B) and a lane only takes ids from blocks whose index ≡ k−1 (mod n); a run never
  crosses a block edge. Two lanes with different slots can never draw the same id, pushed or not.
  Unset → today's behaviour exactly (max + 1). Malformed slot, k > n, or count > B under a slot →
  exit 2 naming the problem. `finding.sh --add` uses `--block 1`; `next-scenario-id.sh` uses
  `--block 100` (overridable with its own `--block`). The digits keep the width they have today.
- **R2 — Pin the duplicate gate (F213).** A traceability test case: split layout, one id defined
  in two feature files → exit 6 and the id named.
- **R3 — Checkpoint by H number and tick date (F217–F219).** `since` is the ticked checkpoint row
  with the highest H number (letters after the digits break ties in order). Count feature rows
  ticked after it: by the commit that first wrote the row as `- [x]` in `specs/INDEX.md`, compared
  with the checkpoint's own tick commit. When git cannot answer (no repository, a row with no tick
  in history), fall back to file order below that checkpoint row. Output and exit codes unchanged.
- **R4 — Owner tag anywhere (F210).** All three readers take the LAST `@name` token in the row
  that follows whitespace or an em dash and is followed by whitespace or end of line. An email
  (`a@b.se`) is not a tag. Lowercased as today.
- **R5 — Cleared phase debt (F214).** `lane_status.py`'s phase-debt count skips a row carrying
  `☑`, the same reading `project-phase-banner.sh` uses.
- **R6 — Archive by id (F197).** A ticked row is already archived when the completed archive holds
  a `- [x] <id> —` line for the same id whose text is at least as long as the current row. A
  longer current row (new content added after archiving) is still appended. A pre-tick or hand
  summary heading still does not count (row 099's case).
- **R7 — Spec slug from the specs level (F199).** The slug is the path component directly under
  `specs/`. A file not under a `specs/<dir>/` keeps the old parent-directory reading.
- **R8 — Budget split by ownership (F215).** In a synced project, `context-budget.sh` asks
  `template-autosync.sh --list-core-rules` which rules are CORE. The split line shows CORE and
  local rule bytes. Over the cap, the advice says how many bytes the project owns (local rules +
  CLAUDE.md and imports), names its largest local rules, and sends only the part the project cannot
  reach upstream. No list available → today's wording.
- **R9 — Underscore id before a paren (F237).** The underscore form also ends at `(`:
  `Foo_SC040(` and `SC1_SC2(` are read; `SC2086(`-like tokens with no leading separator are not.
- **R10 — Tests.** Each of R1–R9 has a case in the script's existing suite, plus a sabotage arm
  where the suite has a sabotage mode.

### As built

- **F213's gate was already there.** `validate-scenario-traceability.sh` exits 6 on agentcrm today
  and names all 143 duplicate ids. case17b pins the cross-file shape, and the allocator half is R1.
- **The allocator now fails loudly when it is missing.** A copied `finding.sh` without
  `max-id-in-refs.sh` used to number from F001 again without a word. It now exits 2.
  `test-finding.sh`'s fixture copies the sibling.
- **`git log --format='@@commit'` is not a format.** git reads it as a named pretty format and
  refuses it, and the empty result fell back to file order without a trace. It is now `tformat:`,
  and AC10 runs in a real repository so the fallback cannot pass for the git path.
- **The 099-R4 substring control conflicted with R6.** Its longer `- [x] 004 …` archive line is
  exactly the archived long form that R6 recognises. The control's line is now quoted, which keeps
  its point (a line that contains the row is not a copy).
- **Read-only re-runs:** rocky `since=H13 count=8 due=1` → `since=H19 count=1 due=0`. agentcrm's
  budget advice went from "file the excess upstream" to "all 2250 are reachable here", naming
  project-phase.md, living-docs.md and on-top.md.
- **Found on the way:** the settings guards treat regex text `.*` in a Bash command as a glob that
  matches `.claude` (F298, recorded).

## Clarifications

### Session 2026-11-18 (auto-picked, recommended option)

- Q: Prefix ids per lane (F598j) instead of striping numbers? → A: No. Eleven readers match
  `F[0-9]+` / `SC-[0-9]+`; a numeric stripe changes none of them.
- Q: Where is the slot configured? → A: `SPEC_LANE_SLOT` in `.claude/settings.local.json` env,
  next to `SPEC_OWNER`. Per machine, gitignored.
- Q: Tick time from author or committer date? → A: Order in `git log` (topological), not a clock.
  A rebase rewrites dates; the log order is what the register's history means.
- Q: Should the duplicate gate move into `validate-register-ids.sh`? → A: No. It exists and
  runs; R2 pins it.

## Non-goals

Renumbering existing collisions in any project. Register row ids (`next-register-id.sh`). A lane
claim protocol over the network.

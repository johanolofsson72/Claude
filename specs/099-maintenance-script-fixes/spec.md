# 099 — maintenance-script-fixes

Track: light. No entity, no state machine, no concurrency, no new external surface, no UI. Four
maintenance-script defects ighweld spec 219 found (F166–F169), each making a report say something
false or something that can never be cleared. Not hardened: no trigger fires. The context-budget
part touches six always-loaded rule files, but it moves text to docs that already exist and changes
no rule's contract.

## Problem

| Finding | Where | What goes wrong today |
|---|---|---|
| F166 | `project-maintenance.sh` §6e | Every `scripts/check-*.sh` runs with no arguments. ighweld's `check-service-digest.sh` is a deploy-time tool that needs a service name and digest (exit 3, usage); `check-catalogue-integrity.sh` needs the API on :5175 (exit 2). Both print `[RATCHET] … failed` on every pass. The only opt-out is a permanent skip, which also drops the run on the days the precondition holds |
| F167 | `carve_audit.py` | A carve excess the developer already decided (ighweld 064 and 097, three carves each, before carving was measured, all shipped) prints `[CARVE BUDGET]` forever. There is no way to record the decision |
| F168 | `context-budget.sh`, `.claude/rules/*.md` | The template ships 30.9 KB of always-loaded rules against a 40 KB cap. ighweld's own CLAUDE.md is 16.8 KB, so the total is 47,978 bytes, and the advice "move rationale to .claude/docs/" is futile there: the rules are CORE and every sync overwrites them |
| F169 | `archive-completed-rows.sh` | A ticked row counts as archived when `INDEX.completed.md` has a `## <id>` heading, whatever is under it. ighweld had 22 rows whose heading held a pre-tick `[/]` form or a hand summary. The script said "all archived" while no verbatim copy of those rows existed, so shortening them would have lost text |

## Requirements

- **R1 (F166).** A ratchet that exits **77** says "my precondition is absent here" (the automake/TAP
  SKIP code). The pass lists it under the skipped ratchets, with its last output line as the
  reason, and it is not a finding. Any other non-zero exit is still a failure, and the failure text
  now names both ways out: exit 77 when the precondition is absent, or `# maintenance: skip <why>`
  when it can never run here.
- **R2 (F167).** The developer records a decided excess with a header line in `specs/INDEX.md`:
  `Carve accepted: <id>=<n>[, <id>=<n>…] · <YYYY-MM-DD> · <why>`. A parent whose carve count is at
  most its accepted `n` is reported as one `accepted` line and does not make the audit fail. A
  parent that carves past its accepted count fails again and the report shows both numbers. A line
  that starts `Carve accepted` but does not parse fails the audit and is named. Acceptance covers
  the budget only, not depth.
- **R3 (F168).** The template's always-loaded rules total at most **23,552 bytes** (23 KB), so a
  project keeps ~17 KB for its own CLAUDE.md. The long form moves verbatim into the existing
  `.claude/docs/<rule>-rationale.md` files, and the rules keep every BLOCKING contract line. The
  template self-test pins the cap. `context-budget.sh` prints the split (rules vs. CLAUDE.md
  files). In a synced project (`.claude/.template-sync` present), an over-budget run says which
  bytes the template owns and what is left for the project's CLAUDE.md, instead of "move rationale
  to docs".
- **R4 (F169).** "Archived" means that the row's current text is in `INDEX.completed.md` verbatim. A
  ticked row whose exact text is not there is appended under a new `## <id> — <slug>` entry, even
  when a heading for the id already exists. The report gives the count of each kind (new id, text
  changed since its entry), and it says "all archived" only when every ticked row's text is
  present. "Shortenable" for a ticked row requires the same thing; an open row keeps the heading
  check, because its pending entry is written by hand.
- **R5 (in passing).** TLC's `tla/states/` run directories are git-ignored. 098 committed five of them.

## Non-goals

- `# maintenance: args …` or a probe command declared in a ratchet's header. Exit 77 lets the
  ratchet decide for itself, and maintenance never evaluates marker text as a command.
- Accepting a depth-3 chain. Section 3 has no exception.
- Lowering the 40 KB cap, or trimming any project's own CLAUDE.md.
- Editing ighweld's two ratchets. That is the project's work after this syncs (exit 77 in the
  catalogue check, a skip marker on the deploy-time digest check).
- Rewriting rows. The archiver still only preserves and reports.

## Success criteria

- SC-1: a ratchet exiting 77 shows as skipped with its reason, and the pass has no `[RATCHET]` finding for it.
- SC-2: a register with `Carve accepted: 097=3 · …` and 097 carving 3 exits 0 with an accepted line. At 4 carves it exits 1.
- SC-3: the template's rules total ≤ 23,552 bytes, and a synced fixture over the cap gets the template-owned message.
- SC-4: on ighweld's pre-219 register, the archiver reports the rows with no verbatim copy, and a live run makes every ticked row verbatim-present.

## Clarifications

### Session 2026-10-04

- Q: Does a ratchet's exit 77 count toward a pass's failures under `--unattended`? → A: No. It is
  a skip in both modes. Trust decides whether it runs; 77 is read only from a run that happened.
- Q: Which id grammar does `Carve accepted` take? → A: The audit's own attribution id grammar
  (`[A-Za-z]?[0-9][0-9A-Za-z.]*`), so any id the audit can name as a parent can be accepted.
- Q: Does an acceptance for a parent that is not over budget print anything? → A: No. It is inert
  until needed, and a stale acceptance is not an error.
- Q: Is the 23,552-byte rules cap configurable? → A: No. It is a template self-test constant. The
  baseline file already ratchets the total downward, and the cap is the ceiling above it.
- Q: Does the archiver's text check ignore trailing whitespace? → A: No. Verbatim means byte-equal
  on the line, and a row is compared as one whole line of the archive, never as a substring of one.

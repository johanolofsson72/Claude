# Carve budget rule (the register has to converge)

Every other rule in this directory pushes in one direction: **create a row.** `validation-followup.md`
says surface every finding and offers "Defer (track in spec)". `spec-hardening.md` runs a checkpoint
every five specs whose whole job is to find things. `spec-register.md` says scope creep becomes a new
row rather than silent inclusion. `lane-handoff.md` says work no row covers becomes a new row.
`CLAUDE.md`'s Definition of Done adds a mutation gate, a destructive suite and visual baselines, and
each of those is a finding generator.

Not one of them says when to stop. This rule is the missing half.

## What went wrong without it (measured 2026-09-03)

A register is a branching process. Working one row produces some number of new rows; call it the
**carve ratio**. Below 1.0 the backlog drains. Above 1.0 it grows without bound no matter how fast
you work, because the work is what produces the rows. Measured across five projects:

| Project | Window | Rows added | Rows ticked | Carve ratio | Open rows |
|---|---|---|---|---|---|
| rocky | 08-09 → 09-03 | +96 | +40 | **2.40** | 24 → 80 |
| agentcrm | 08-18 → 09-02 | +44 | +30 | **1.47** | 17 → 31 |
| consultpilot | 08-13 → 09-02 | +92 | +65 | **1.42** | 12 → 39 |
| consultpilot | 07-17 → 08-04 | +34 | +47 | 0.72 | 27 → 14 |
| msroute | 08-14 → 09-02 | +95 | +86 | 1.10 | 11 → 20 |
| film-i-vast-demo | 08-31 → 09-03 | +38 | +38 | 1.00 | 2 → 2 |

consultpilot is the control: the same project, the same people, the same tooling, ratio 0.72 in July
and 1.42 in August. Nothing about the developer changed. What changed is that the gates got good
enough to find things faster than the pipeline could close them.

The shape it takes is visible in the ids. consultpilot's checkpoint `H7` produced `H7a`…`H7z`, then
`H7aa`…`H7bn` — **122 descendant rows from one checkpoint**, 44 of them at the second suffix level.
90 rows carry the words "carved by". `H7u` alone carved five. Every one of those was a real finding
honestly recorded, which is exactly why nobody stopped it.

## The contract (BLOCKING)

### 1. A finding is not automatically a row

`validation-followup.md` requires every finding be **surfaced**. It does not require every finding
become a **row**, and reading it that way is what produced the table above. Every finding gets one of
three dispositions, and the default is the first:

- **Fix it inside the current spec.** If the fix is smaller than the ceremony of a row — and a row
  costs a spec directory, an interview, a plan, tasks, a test matrix and a status summary — then
  fixing it now is cheaper than recording it. This is the default disposition. Reach for it first.
- **Carve a row**, against the budget below.
- **Decline it, in writing.** One line in `<spec-dir>/run-log.md`: what it was and why it does not
  earn a row. A declined finding is a decision with an audit trail, not a thing that was missed.

"Defer (track in spec)" in the `validation-followup.md` option set means *the third one* when the
budget is spent. It has been read as "always make a row". It is not.

### 1b. Before carving, ask whether the row already exists

The opening question of the review that produced this rule was not about speed — it was *"vi
sitter och skriver om redan befintlig funktionalitet"*. Nothing measured that. A carve budget stops
the register growing; it does nothing about the same row being written twice, in two projects,
months apart, by someone who could not have held 334 open rows in their head.

`bash scripts/register-similarity.sh --text "<the row you are about to write>"` answers it in
seconds. It embeds every register row across every project on the machine and reports the closest
existing ones. Local embedding model, no network, no credentials.

It is a **report, never a gate**. Two rows can be close in wording and different in intent; the
point is that until 2026-09-03 nobody was looking at all. Run it before carving a row, and as part
of the periodic maintenance pass.

Its first full pass, across 28 projects and 334 open rows, found `ighweld-2026` rows **119 and 138**
— both `scenario-map-split`, the same job planned twice nineteen rows apart, one measuring the file
at 131 KB and the other at 169 KB.

What it does **not** do is group rows by subject. The template's own 007, 013 and 016 were three
different defects in one script; their descriptions are genuinely dissimilar and the tool correctly
said so. That grouping is a `grep` for the filename, not an embedding.

### 2. Two carves per spec, then the budget is spent

A spec may carve **at most 2 rows**. When a third finding wants a row, the spec does one of:

- fold every remaining finding into **one** consolidated row ("the six things S11 found"), or
- write them to `specs/INDEX.pending.md` under a single new row that points at them.

Two is not arbitrary. At 2 carves per spec the ratio only stays under 1.0 if most specs carve
nothing, which is the intended shape: a routine spec finishes and produces no rows at all. The budget
is a ceiling on the exceptional spec, not an allowance every spec is meant to spend.

`SPEC_CARVE_BUDGET=N` overrides it per project. Raising it is a deliberate, recorded choice — put the
reason in a Register history line — not a reflex when a spec finds three things.

### 3. Carve depth stops at 2

A row carved by an original spec is **depth 1**. A row carved by a depth-1 row is **depth 2**. There
is no depth 3.

When a depth-2 row wants to carve, the pipeline has stopped working on the product and started
chasing itself. Stop and report it to the developer as a **convergence stop** (below). `H7bn` was
depth 3 and above; nothing in the ruleset noticed.

Record depth on the row: `— carved by H7u (d2)`. A row with no marker is depth 0.

### 4. Harness defects belong to the template, not to the product register

agentcrm's rows `S1`–`S20` are, with one exception, defects in **our own tooling**: a scenario-id
collision in the gate, a heredoc blind spot in the bash write guard, build output tripping that same
guard, the row archiver refusing the project's row ids, `test-pipeline-hooks.sh` red with 21
failures, a missing `frontend-design` skill that four CORE files call as BLOCKING. Twenty rows on a
property CRM's register, none of which ship anything to a broker.

That work is real and has to happen. It does not belong on the product's register, where it competes
with the product for the register's one-row-at-a-time throughput and for the developer's attention.

- A defect in `.claude/**`, `scripts/**`, a hook, a guard or a skill goes to the **template repo**
  (`/Users/jool/repos/Claude`) as a row on *its* register, and reaches the project through the
  ordinary sync.
- The product register gets **one** standing row per project — `T0 — harness-defects` — that points
  at the template rows currently blocking this project. It is ticked when nothing blocks; it is never
  carved from.
- The exception is a harness defect that **blocks the current spec right now**. Fix it in place, and
  file the template row in the same commit. Fixing it locally and not filing it is how five projects
  end up with five divergent copies of the same guard.

### 5. The register reports its own convergence

`scripts/register-convergence.sh` computes the carve ratio over a trailing window and prints it. It
runs inside `project-maintenance.sh` and at SessionStart when the register has moved. Three verdicts:

- **ratio < 1.0** — converging. One line, no noise.
- **1.0 ≤ ratio < 1.3** — flat. Reported, not blocking. A project can sit here honestly for a while.
- **ratio ≥ 1.3 over a window of 10+ ticked rows** — diverging. This is a **convergence stop**.

### 6. The convergence stop

A convergence stop is a legitimate stop under `continuous-execution.md` — the same class as a
register-rewrite proposal, and for the same reason: the register itself is the thing that is wrong.
Finish the current spec, then stop and report:

```
**Convergence stop — the register is growing faster than it closes**

- Carve ratio: <N> over the last <W> ticked rows (threshold 1.3)
- Open rows: <before> → <now>
- The <K> heaviest carvers: <row ids and what each produced>
- Deepest carve chain: <root> → … → <leaf> (depth <D>)

Three ways out, pick one:
1. Freeze carving — no new rows until open rows fall below <target>. Findings go to the run log.
2. Batch — fold the <M> open spec-only rows into one consolidated row.
3. Cut — the rows that no longer matter get deleted, not deferred. Name them.
```

The developer decides. Claude proposes, and does not silently keep carving.

### 7. Deleting a row is allowed

There is no rule anywhere that lets a row die. A row can be ticked, held, or carried forever, and so
registers only ever grow. A row may be **deleted** when it no longer describes work anybody wants,
with a one-line Register history entry naming it and why. That is not losing the audit trail: the git
history holds every version of the register, and `INDEX.pending.md` holds the diagnosis if it had
one.

## What this rule forbids

- Turning every `validation-followup.md` finding into a register row. Surface all of them; row the
  ones that earn it.
- Carving a third row from one spec without folding the rest into one.
- Carving at depth 3. That is a convergence stop, not a row.
- Putting a harness/tooling defect on a product register as anything but the standing `T0` row.
- Continuing past a diverging carve ratio without telling the developer.
- Treating "the finding was real" as sufficient reason for a row. Every one of the 122 rows under
  `H7` was real.

## How this interacts with the other rules

- `validation-followup.md` — still governs *surfacing*. This rule governs *rowing*. A finding that
  gets declined in the run log is surfaced, decided, and recorded; that satisfies both.
- `spec-hardening.md` — the every-5 checkpoint is bounded by the same 2-carve budget as any spec. A
  checkpoint that finds nine things files one consolidated row, not nine.
- `spec-register.md` — the row budget there caps a row's *bytes*; this caps the register's *rows*.
- `continuous-execution.md` — the convergence stop is a legitimate stop, added to its list.
- `lane-handoff.md` — "work no row covers becomes a new row" still holds, against this budget.

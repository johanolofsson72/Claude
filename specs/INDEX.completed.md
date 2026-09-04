# Completed-spec retrospectives (archive)

Rows verbatim as they read at tick time. Never pipeline input.

## 028 — traceability-roots-declaration

Ticked 2026-09-04. Row as it read at tick time, plus the diagnosis.

- [x] 028 — traceability-roots-declaration — spec-only — the gate discovered top-level test dirs only, so a project with suites under `src/` was under-reported. Projects may now declare roots in `specs/traceability-roots`. Verbatim in `INDEX.completed.md`.

**Where it came from.** ighweld-2026 register row 173 (`e2e-suite-integrity`), which batched twelve
rows about checks that report success without checking. Two of them (132, 149) were this defect seen
from inside one project; this is the fleet-wide half.

**The defect.** `validate-scenario-traceability.sh` discovers its reference roots from a candidate
list of top-level directories — `tests test e2e __tests__ cypress playwright` — and deliberately
excludes `src/`, on the correct ground that a source comment naming an id is not a test. A project
whose test trees are neither top-level nor reachable by widening that list therefore could not be
served at all. ighweld keeps ~3,500 xUnit tests under `src/welding/Welding.Api.Tests/` and ~1,345
vitest suites under `src/welding/client/src/**/__tests__/`.

**Measured on ighweld, 2026-09-04, both directions:**

| | discovered roots | real roots |
|---|--:|--:|
| coverage | 443 of 814 | 518 of 814 |
| dangling | 4 | 11 |

The second row is the finding worth keeping. ighweld's own row 149 stated in writing that the blind
spot was one-way — *"an id named by an unscanned test simply is not seen at all, so nothing is being
falsely reported as covered; the error is one-way"* — and that is wrong. Seven dangling ids
(`SC-011`…`SC-019`) were concealed by the narrow roots, i.e. seven broken references that the gate
could not report because it could not see the tests that made them. A gate under-reporting its
coverage trains readers to discount the number; a gate hiding broken references is worse, and it was
doing both.

**The fix.** An optional per-project declaration at `specs/traceability-roots` — one root per line,
`#` comments and blanks ignored. Precedence, most specific first:

1. `--roots` — the caller's promise, for one invocation.
2. the declaration — the project's promise, for every invocation.
3. discovery — the fleet default, unchanged.

Two properties carried over from the existing design rather than invented:

- **A declared root that does not exist refuses** (exit 4), through the untouched `root-guard`. That
  guard already drew the distinction: discovery *skips* an absent candidate because a candidate is a
  guess, while `--roots` refuses because it is a promise. A declaration is a promise, so it refuses.
- **An empty declaration refuses rather than falling through to discovery.** A file of nothing but
  comments must not become a route to the "0 of 0, all clear" report this script is named after.
  That is the sabotage direction that mattered most, and it has its own case.

The report line now says where the roots came from — `(--roots)`, `(declared in
specs/traceability-roots)`, `(discovered)` — because a reader looking at a low coverage figure needs
to know whether they are seeing a project's declaration or the default having guessed.

**Additive by construction.** A project without the file behaves exactly as before; `case39` asserts
that rather than assuming it. Same property that let the two-lane logic ship enabled.

**Tests.** Five cases (35–39) and a sabotage arm (`m`, `roots-declaration`) that neutralises the
region and confirms cases 35 and 38 go red. 40 passed, 0 failed. The sabotage arm matters here for
the reason the `roots-discovery` one does: on any project whose tests live in `tests/`, this whole
feature is invisible, so nothing else in the suite would notice if it stopped working.

## 001 — carve-budget

- [x] 001 — carve-budget — full track — the register has to converge: a finding is fixed in place, carved (max 2/spec, depth 2), or declined in writing. Detalj: specs/INDEX.completed.md

## 002 — dotted-sub-spec-ids

- [x] 002 — dotted-sub-spec-ids — spec-only — `spec_active.py`'s numeric grammar did not know `501.1`/`450.7`, so 22 of rocky's 123 rows were unclassifiable and both PreToolUse guards failed closed on them. Detalj: specs/INDEX.completed.md

## 003 — archiver-refuses-real-registers

- [x] 003 — archiver-refuses-real-registers — spec-only — `archive-completed-rows.sh` demanded a `## Specs` heading rocky never had, and its id shapes claimed to match `spec_active.py` while rejecting any letter-led id. Inert on two projects. Detalj: specs/INDEX.completed.md

## 004 — nightly-has-no-body

- [x] 004 — nightly-has-no-body — spec-only — three documents said the mutation gate runs nightly and nothing scheduled it, so it ran never. `install-nightly-maintenance.sh` is the crontab entry.

## 005 — lane-merge-cost-is-in-the-lists

- [x] 005 — lane-merge-cost-is-in-the-lists — spec-only — two lanes append to four markdown files and git calls every append a conflict; `union` on the append-only lists, `validate-register-ids.sh` as the backstop.

## 007 — traceability-gate-is-three-defects-in-one-script

- [x] 007 — traceability-gate-is-three-defects-in-one-script — full track — the two SC- namespaces split by digit WIDTH, not magnitude (a floor is useless on a map starting at SC-001); duplicates get exit 6. msroute 13 dangling → 0. Detalj: specs/INDEX.completed.md

## 009 — held-rows-have-no-archive

- [x] 009 — held-rows-have-no-archive — spec-only — the archiver told you to write a pending entry by hand and nobody did, so rocky ran 47 over-budget open rows. `--write-pending` makes the advice executable; rocky 131→39 KB. Detalj: specs/INDEX.completed.md

## 015 — sigpipe-validator-scans-only-self-tests

- [x] 015 — sigpipe-validator-scans-only-self-tests — spec-only — `--all` scans every script, `--strict` fails on them; the default population and its meta-test are unchanged. The gate was already RED here on 7 of its own self-tests, now fixed. Detalj: specs/INDEX.completed.md

## 018 — core-owed-tick-gate-goes-silent

- [x] 018 — core-owed-tick-gate-goes-silent — full track — the gate was never broken: the TEST used GNU `sed -i` on a BSD sed, so the tick never happened and the detector correctly said nothing. Portable `inplace()` helper; 89/89. Detalj: specs/INDEX.completed.md

## 019 — are-we-writing-this-row-twice

- [x] 019 — are-we-writing-this-row-twice — full track — nothing measured the question that opened the review: are we rebuilding what we already have. Local embedding pass over every register; found ighweld-2026 119/138, one job planned twice. Detalj: specs/INDEX.completed.md

## 025 — speckit-check-fired-on-the-template

- [x] 025 — speckit-check-fired-on-the-template — spec-only — the pass told this config repo to install spec-kit once it grew a register; now gated on a language marker, the predicate every other guard uses. Third not-applicable case today.

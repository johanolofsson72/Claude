# Spec register — the template itself

The template is a project too, and its defects are the ones that reach every other
project. This register is where a defect in `.claude/**`, `scripts/**`, a hook, a
guard or a skill goes, per `.claude/rules/carve-budget.md`. A product register
carries a standing `T0 — harness-defects` row that points here; it never carries
the fix.

Order of execution. Tick when done. Append new rows to the end.

## Specs

- [x] 001 — carve-budget — full track — the register has to converge: a finding is fixed in place, carved (max 2/spec, depth 2), or declined in writing. Detalj: specs/INDEX.completed.md
- [x] 002 — dotted-sub-spec-ids — spec-only — `spec_active.py`'s numeric grammar did not know `501.1`/`450.7`, so 22 of rocky's 123 rows were unclassifiable and both PreToolUse guards failed closed on them. Detalj: specs/INDEX.completed.md
- [x] 003 — archiver-refuses-real-registers — spec-only — `archive-completed-rows.sh` demanded a `## Specs` heading rocky never had, and its id shapes claimed to match `spec_active.py` while rejecting any letter-led id. Inert on two projects. Detalj: specs/INDEX.completed.md
- [x] 004 — nightly-has-no-body — spec-only — three documents said the mutation gate runs nightly and nothing scheduled it, so it ran never. `install-nightly-maintenance.sh` is the crontab entry.
- [x] 005 — lane-merge-cost-is-in-the-lists — spec-only — two lanes append to four markdown files and git calls every append a conflict; `union` on the append-only lists, `validate-register-ids.sh` as the backstop.
- [ ] 006 — frontend-design-is-a-plugin-not-a-skill — spec-only — four CORE files call `frontend-design` as BLOCKING by bare name; it ships in the plugin cache, not `.claude/skills/`. Without that plugin the gate cannot fire and says nothing. Found by @david as agentcrm S20.
- [ ] 007 — traceability-gate-is-three-defects-in-one-script — full track — collisions and the coverage backlog share one `exit 1`; the out-of-range floor is useless on a map starting at SC-001; letter ids are invisible. Folds 013, 016. Diagnos: `specs/INDEX.pending.md`.
- [ ] 008 — scenarios-map-canary-unheeded — spec-only — `SCENARIOS.md` is 242 KB on rocky and 254 KB on agentcrm against a 25 KB canary, read every spec by every lane. The split layout exists in the rule and has never been run.
- [ ] 009 — held-rows-have-no-archive — spec-only — `archive-completed-rows.sh` archives `[x]` to completed and `[ ]` to pending, and does nothing for `[!]`. rocky now holds 21 held rows carrying full diagnoses inline, which is why its INDEX.md is still 127 KB after archiving.

- [ ] 010 — autosync-test-writes-to-the-repo-it-tests — full track [hardened] — `test-template-autosync-*.sh` writes into the working repo instead of a fixture, so a failing run can leave the tree dirty. Found by @johan as consultpilot H7bm.
- [ ] 011 — twenty-hand-written-sync-invocations — full track — the sync path is invoked twenty different ways by hand across the scripts, which forces each gate to be cleverer than it should need to be. Found as consultpilot H7bo.
- [ ] 012 — core-file-comments-hold-real-scenario-ids — spec-only — a CORE file's comments cite real SC-ids as examples, so the traceability gate counts them as references and a deleted row looks covered. Found as consultpilot H7bp.
- [ ] 014 — autosync-adds-gates-no-runner-registers — spec-only — a sync that ships new `test-*.sh` scripts leaves every project's `run-gates.sh` reporting DRIFT until someone adds them to GATES by hand. Found as consultpilot H7av.
- [ ] 015 — sigpipe-validator-scans-only-self-tests — spec-only — `validate-no-sigpipe-assertions.sh` globs `scripts/test-*.sh`, so 143 non-test scripts go unscanned; `template-autosync.sh:227` broke a unit test under load and the gate could not see it. Found as msroute 007cn.
- [ ] 017 — canary-and-row-budget-do-not-compose — spec-only — every row can sit inside the 300-byte budget and the register still exceed the 25 KB canary: on msroute 90 archived-verbatim completed rows are 74% of the file. A compliant register with no next move. Found as msroute 007ck.
- [x] 018 — core-owed-tick-gate-goes-silent — full track — the gate was never broken: the TEST used GNU `sed -i` on a BSD sed, so the tick never happened and the detector correctly said nothing. Portable `inplace()` helper; 89/89. Detalj: specs/INDEX.completed.md
- [ ] H1 — integration-hardening — checkpoint — full-system regression + security sweep after the five rows closed 2026-09-03; the template ships to six projects, so its seams are theirs.

## Register history (newest first)

- 2026-09-03 — register created; harness defects move here off the product registers, per the carve budget.

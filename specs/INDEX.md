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
- [ ] 007 — traceability-gate-conflates-two-failures — spec-only — `validate-scenario-traceability.sh` reports collisions and the coverage backlog through one `exit 1`, so a real collision is invisible behind a permanently-red backlog. Found by @david as agentcrm S3.
- [ ] 008 — scenarios-map-canary-unheeded — spec-only — `SCENARIOS.md` is 242 KB on rocky and 254 KB on agentcrm against a 25 KB canary, read every spec by every lane. The split layout exists in the rule and has never been run.
- [ ] 009 — held-rows-have-no-archive — spec-only — `archive-completed-rows.sh` archives `[x]` to completed and `[ ]` to pending, and does nothing for `[!]`. rocky now holds 21 held rows carrying full diagnoses inline, which is why its INDEX.md is still 127 KB after archiving.

- [ ] 010 — autosync-test-writes-to-the-repo-it-tests — full track [hardened] — `test-template-autosync-*.sh` writes into the working repo instead of a fixture, so a failing run can leave the tree dirty. Found by @johan as consultpilot H7bm.
- [ ] 011 — twenty-hand-written-sync-invocations — full track — the sync path is invoked twenty different ways by hand across the scripts, which forces each gate to be cleverer than it should need to be. Found as consultpilot H7bo.
- [ ] 012 — core-file-comments-hold-real-scenario-ids — spec-only — a CORE file's comments cite real SC-ids as examples, so the traceability gate counts them as references and a deleted row looks covered. Found as consultpilot H7bp.
- [ ] 013 — traceability-self-test-straddles-its-timeout — spec-only — `validate-scenario-traceability.sh`'s own self-test runs 77s against its timeout, so it passes or fails by machine speed. Found as consultpilot H7bq.
- [ ] 014 — autosync-adds-gates-no-runner-registers — spec-only — a sync that ships new `test-*.sh` scripts leaves every project's `run-gates.sh` reporting DRIFT until someone adds them to GATES by hand. Found as consultpilot H7av.
- [ ] H1 — integration-hardening — checkpoint — full-system regression + security sweep after the five rows closed 2026-09-03; the template ships to six projects, so its seams are theirs.

## Register history (newest first)

- 2026-09-03 — register created; harness defects move here off the product registers, per the carve budget.

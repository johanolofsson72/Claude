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
- [x] 007 — traceability-gate-is-three-defects-in-one-script — full track — the two SC- namespaces split by digit WIDTH, not magnitude (a floor is useless on a map starting at SC-001); duplicates get exit 6. msroute 13 dangling → 0. Detalj: specs/INDEX.completed.md
- [ ] 008 — scenarios-map-canary-unheeded — spec-only — four maps still over the 25 KB canary: consultpilot 682 KB (27x), agentcrm 252, rocky 242 (already split), fundit 30. film-i-vast split 2026-09-03: 140→9 KB. Diagnos: `specs/INDEX.pending.md`
- [x] 009 — held-rows-have-no-archive — spec-only — the archiver told you to write a pending entry by hand and nobody did, so rocky ran 47 over-budget open rows. `--write-pending` makes the advice executable; rocky 131→39 KB. Detalj: specs/INDEX.completed.md

- [ ] 010 — autosync-test-writes-to-the-repo-it-tests — full track [hardened] — `test-template-autosync-*.sh` writes into the working repo instead of a fixture, so a failing run can leave the tree dirty. Found by @johan as consultpilot H7bm.
- [ ] 011 — twenty-hand-written-sync-invocations — full track — the sync path is invoked twenty different ways by hand across the scripts, which forces each gate to be cleverer than it should need to be. Found as consultpilot H7bo.
- [ ] 012 — core-file-comments-hold-real-scenario-ids — spec-only — a CORE file's comments cite real SC-ids as examples, so the traceability gate counts them as references and a deleted row looks covered. Found as consultpilot H7bp.
- [ ] 014 — autosync-adds-gates-no-runner-registers — spec-only — a sync that ships new `test-*.sh` scripts leaves every project's `run-gates.sh` reporting DRIFT until someone adds them to GATES by hand. Found as consultpilot H7av.
- [ ] 015 — sigpipe-validator-scans-only-self-tests — spec-only — `validate-no-sigpipe-assertions.sh` globs `scripts/test-*.sh`, so 143 non-test scripts go unscanned; `template-autosync.sh:227` broke a unit test under load and the gate could not see it. Found as msroute 007cn.
- [ ] 017 — canary-and-row-budget-do-not-compose — spec-only — every row can sit inside the 300-byte budget and the register still exceed the 25 KB canary: on msroute 90 archived-verbatim completed rows are 74% of the file. A compliant register with no next move. Found as msroute 007ck.
- [x] 018 — core-owed-tick-gate-goes-silent — full track — the gate was never broken: the TEST used GNU `sed -i` on a BSD sed, so the tick never happened and the detector correctly said nothing. Portable `inplace()` helper; 89/89. Detalj: specs/INDEX.completed.md
- [x] 019 — are-we-writing-this-row-twice — full track — nothing measured the question that opened the review: are we rebuilding what we already have. Local embedding pass over every register; found ighweld-2026 119/138, one job planned twice. Detalj: specs/INDEX.completed.md
- [ ] 020 — quality-gate-hooks-unwired-for-latency-we-no-longer-pay — full track — 15 local-LLM hooks (test-realism, test-assertion, test-gap, secret-scan…) are unwired because they cost in-session latency. The nightly pass makes that free. Re-measure them at 02:30.
- [ ] 021 — core-set-excludes-docs-and-skills — spec-only — `core_divergence` walks only CORE_SCRIPTS+CORE_RULES, so project-authored work under `.claude/docs/` or `.claude/skills/` is absent from `--owed` and a tick passes. Third gap after 018. Diagnos: `specs/INDEX.pending.md`.
- [ ] 022 — sync-version-marker-abandoned — spec-only — only `sync-prompt.md` and `project-wizard` write `.claude/.sync-version`; autosync maintains `.claude/.template-sync`. Step 0 reads the stale one and reports "sync needed" on a current project. Diagnos: `specs/INDEX.pending.md`.
- [ ] 021 — secret-scan-misses-signing-material — full track [hardened] — two repos commit an ASP.NET Data Protection key and `project-freshness.sh` reports "no verified secrets" on both. trufflehog matches verifiable credentials; a signing key is none. Needs a file-shape arm.
- [ ] H1 — integration-hardening — checkpoint — full-system regression + security sweep after the five rows closed 2026-09-03; the template ships to six projects, so its seams are theirs.

## Register history (newest first)

- 2026-09-03 — 021 + 022 filed from an msroute `/project-update`; the two orphaned CORE-adjacent improvements landed here in the same pass.
- 2026-09-03 — register created; harness defects move here off the product registers, per the carve budget.

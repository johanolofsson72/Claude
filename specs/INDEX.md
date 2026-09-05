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
- [ ] 006 — nothing-checks-the-design-gate-exists — spec-only — the bare name RESOLVES to the plugin cache, so the naming half is refuted. What stands: nothing verifies the plugin is installed, so a BLOCKING gate fails silent without it. Diagnos: `specs/INDEX.pending.md`.
- [x] 007 — traceability-gate-is-three-defects-in-one-script — full track — the two SC- namespaces split by digit WIDTH, not magnitude (a floor is useless on a map starting at SC-001); duplicates get exit 6. msroute 13 dangling → 0. Detalj: specs/INDEX.completed.md
- [ ] 008 — scenarios-map-canary-unheeded — spec-only — four maps still over the 25 KB canary: consultpilot 682 KB (27x), agentcrm 252, rocky 242 (already split), fundit 30. film-i-vast split 2026-09-03: 140→9 KB. Diagnos: `specs/INDEX.pending.md`
- [x] 009 — held-rows-have-no-archive — spec-only — the archiver told you to write a pending entry by hand and nobody did, so rocky ran 47 over-budget open rows. `--write-pending` makes the advice executable; rocky 131→39 KB. Detalj: specs/INDEX.completed.md

- [ ] 010 — autosync-test-writes-to-the-repo-it-tests — full track [hardened] — `test-template-autosync-*.sh` writes into the working repo instead of a fixture, so a failing run can leave the tree dirty. Found by @johan as consultpilot H7bm.
- [ ] 011 — twenty-hand-written-sync-invocations — full track — the sync path is invoked twenty different ways by hand across the scripts, which forces each gate to be cleverer than it should need to be. Found as consultpilot H7bo.
- [ ] 012 — core-file-comments-hold-real-scenario-ids — spec-only — a CORE file's comments cite real SC-ids as examples, so the traceability gate counts them as references and a deleted row looks covered. Found as consultpilot H7bp.
- [ ] 014 — autosync-adds-gates-no-runner-registers — spec-only — a sync that ships new `test-*.sh` scripts leaves every project's `run-gates.sh` reporting DRIFT until someone adds them to GATES by hand. Found as consultpilot H7av.
- [x] 015 — sigpipe-validator-scans-only-self-tests — spec-only — `--all` scans every script, `--strict` fails on them; the default population and its meta-test are unchanged. The gate was already RED here on 7 of its own self-tests, now fixed. Detalj: specs/INDEX.completed.md
- [ ] 017 — canary-and-row-budget-do-not-compose — spec-only — every row can sit inside the 300-byte budget and the register still exceed the 25 KB canary: on msroute 90 archived-verbatim completed rows are 74% of the file. A compliant register with no next move. Found as msroute 007ck.
- [x] 018 — core-owed-tick-gate-goes-silent — full track — the gate was never broken: the TEST used GNU `sed -i` on a BSD sed, so the tick never happened and the detector correctly said nothing. Portable `inplace()` helper; 89/89. Detalj: specs/INDEX.completed.md
- [x] 019 — are-we-writing-this-row-twice — full track — nothing measured the question that opened the review: are we rebuilding what we already have. Local embedding pass over every register; found ighweld-2026 119/138, one job planned twice. Detalj: specs/INDEX.completed.md
- [ ] 020 — quality-gate-hooks-unwired-for-latency-we-no-longer-pay — full track — 15 local-LLM hooks (test-realism, test-assertion, test-gap, secret-scan…) are unwired because they cost in-session latency. The nightly pass makes that free. Re-measure them at 02:30.
- [ ] 021 — core-set-excludes-docs-and-skills — spec-only — `core_divergence` walks only CORE_SCRIPTS+CORE_RULES, so project-authored work under `.claude/docs/` or `.claude/skills/` is absent from `--owed` and a tick passes. Third gap after 018. Diagnos: `specs/INDEX.pending.md`.
- [ ] 022 — sync-version-marker-abandoned — spec-only — only `sync-prompt.md` and `project-wizard` write `.claude/.sync-version`; autosync maintains `.claude/.template-sync`. Step 0 reads the stale one and reports "sync needed" on a current project. Diagnos: `specs/INDEX.pending.md`.
- [ ] 023 — secret-scan-misses-signing-material — full track [hardened] — two repos commit an ASP.NET Data Protection key and `project-freshness.sh` reports "no verified secrets" on both. trufflehog matches verifiable credentials; a signing key is none. Needs a file-shape arm.
- [ ] 024 — sigpipe-backlog-in-production-scripts — spec-only — `validate-no-sigpipe-assertions.sh --all` reports 54 pipelines outside the self-tests. Mostly diagnostics where 141 costs nothing. One at a time: a bulk pass turned msroute's suite red (M2).
- [x] 025 — speckit-check-fired-on-the-template — spec-only — the pass told this config repo to install spec-kit once it grew a register; now gated on a language marker, the predicate every other guard uses. Third not-applicable case today.
- [ ] 026 — port-drive-sync-and-its-gate-upstream — full track — consultpilot authored H7bo (a `drive_sync` helper + `validate-sync-sandbox-declarations.sh`) after the 2026-08-30 incident; neither exists here, so its gate is red downstream on 17 CORE call sites it cannot fix. Diagnos: `specs/INDEX.pending.md`
- [ ] 027 — zero-attributions-reports-clean — spec-only — `carve_audit.py` prints "clean" and exits 0 when `len(parent)` is 0, so a register that never attributed a carve reads like a flat one. §4b says that count *is* the finding. Diagnos: `specs/INDEX.pending.md`
- [x] 028 — traceability-roots-declaration — spec-only — the gate discovered top-level test dirs only, so a project with suites under `src/` was under-reported. Projects may now declare roots in `specs/traceability-roots`. Verbatim in `INDEX.completed.md`.
- [ ] 029 — pretooluse-deny-is-inert-under-bypass-permissions — full track [hardened] — five guards deny correctly when asked and the identical live `Edit` passes; the PostToolUse shell detector still bites, so the teeth are on the path the rules do not name. Diagnos: `specs/INDEX.pending.md`
- [ ] 030 — unlisted-fires-forever-on-an-optional-callee — spec-only — a CORE file calling a project script behind `[ -f ]` is a use, not a dependency; three reported forever here, tick guard permanently red. Diagnos: `specs/INDEX.pending.md`
- [ ] 031 — dotnet-test-prints-passed-over-an-aborted-run — spec-only — a crashed test host reported `Passed!` with 45% of the suite unrun; no wrapper reads the abort line. Diagnos: `specs/INDEX.pending.md`
- [ ] 032 — spec-dir-absent-leaves-both-guards-inert — spec-only — a row worked without a spec directory resolves to found:false in spec_active.py, so pipeline-state-guard and spec-interview-guard both pass everything; fundit's 016a shipped that way. Reported by fundit F001.
- [ ] 033 — portability-check-fails-open-and-says-nothing — spec-only — project-maintenance.sh guards the portability audit behind `[ -f ]`, so a clone without scripts/portability_audit.py skips it silently. A check that fails open must say so. Reported by fundit F002.
- [ ] 034 — freshness-reports-seven-bogus-lockfile-skips — spec-only — project-freshness.sh prints `[SKIP] No lockfile` per npm workspace package; in a workspace only the root has one and it covers them, so seven noise lines sit where a real skip would hide. Reported by fundit F003.
- [ ] 035 — a11y-suite-runs-at-one-viewport-only — spec-only — the shared a11y/visual template asserts at the default 1280px, so a horizontal-overflow defect shipped in fundit spec 001 and survived until spec 004 measured 375px by hand. A viewport dimension belongs in the shared suite, not per spec. Reported by fundit F024.
- [ ] H1 — integration-hardening — checkpoint — full-system regression + security sweep after the five rows closed 2026-09-03; the template ships to six projects, so its seams are theirs.

## Register history (newest first)

- 2026-09-05 — 032-035 filed from fundit's findings review (carve-budget §4: a harness defect belongs here, not on a product register)

- 2026-09-04 — 028 ur ighweld 173: traceability-gaten läste bara toppnivå-testkataloger; projekt får nu deklarera sina roots.
- 2026-09-04 — 027 ur agentcrm: `--carves` kallade ett register clean vars djup-3-kedja just spårats för hand. Regeln säger att noll attributioner *är* fyndet; skriptet exitar 0 och `project-maintenance.sh` ser grönt.

- 2026-09-03 — 006 corrected on measurement: the bare skill name resolves to the plugin cache, so the rename half is refuted; what stands is that nothing checks the plugin is installed.
- 2026-09-03 — 021 + 022 filed from an msroute `/project-update`; the two orphaned CORE-adjacent improvements landed here in the same pass.
- 2026-09-03 — register created; harness defects move here off the product registers, per the carve budget.

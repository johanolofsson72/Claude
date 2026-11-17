# 102 — downstream core red

Track: spec-only, hardened. Hardened by the risk-domain trigger: R5 changes what the key-shape
scanner exempts (secrets). No entity, state machine or concurrency, so no `.allium` and no `/tla`.
Findings: F196 (4), F206, F239 (was F209), F211, F246 (was F216), verbatim in `specs/FINDINGS.md`.

## Problem

CORE self-tests and gates ship to every project and are green in the template. Downstream, several
are red, and the reds are the template's fault, not the project's. Measured 2026-11-16 on a local
clone of fundit re-synced to template 1ffab98 (`template-autosync.sh --no-commit --force` into a
scratch sandbox), all 93 CORE gates run with stdin closed and a 300 s bound: 6 red, plus one
freshness finding.

| Red | Cause |
|---|---|
| test-sync-prompt-core-parity | `--list-core-scripts` names `quality-gates.tsv` and `workload-placement.tsv`, but the copy loop globs `*.sh *.py speckit-version` only, so neither file reaches a project. The test is right. |
| test-local-llm-host (P1, P2, P4: 9 fails) | Reads `scripts/sync-prompt.md`, a template-only file. |
| test-sync-prompt-zsh | Extracts Step 5c from `scripts/sync-prompt.md`. Same. |
| validate-rule-citations, test-validate-rule-citations | 15 dangling citations: the web stack gate withholds `testing-mobile.md`, `spec-testing-checklist-mobile.md` and `deployment-mobile.md`, and CORE rules, docs, a skill and `template-autosync.sh` cite them. On a mobile project the first two are written under the canonical names, so citations by their own names dangle there too. |
| validate-fixture-map-ids (exit 3) | Builds its owned set from `specs/SCENARIOS.md` only. Under the split layout the index holds no rows, so it reports NOT RUN on every split project. |
| project-freshness `--secrets` | Flags `scripts/test-project-freshness.sh` as a PuTTY key (no passphrase). The template exempts it in its own `.secret-shapes-allow`, which is project-owned and never synced. |

Reds from the older reports that this sandbox no longer reproduces (context-budget baseline,
hook-channels, runtime-markers, self-test-prologue, stryker-guard, skill-reachable) were fixed by
specs 086–101 or depend on a bare tree with no stack. They stay out of scope.

## Requirements

- **R1 — Data files in CORE_SCRIPTS ship (F239 core-parity).** The scripts copy loop copies every
  CORE_SCRIPTS name that is not `*.sh` or `*.py` by name, instead of naming `speckit-version` alone.
  Adding a data file to CORE_SCRIPTS is then enough to ship it.
- **R2 — sync-prompt checks skip downstream (F211 local-llm-host, sync-prompt-zsh).** The checks
  that read `scripts/sync-prompt.md` skip with a stated reason downstream, using the same
  origin-then-sync-stamp predicate as test-sync-prompt-core-parity.sh and
  test-sync-prompt-bootstrap.sh. Upstream, and when neither signal answers, nothing is skipped.
- **R3 — Every stack receives every doc under its own name (F206).** The web gate stops withholding
  the three mobile docs. A mobile project additionally keeps the canonical-name overlays it gets
  today. No validator learns a stack list.
- **R4 — fixture-map-ids reads the split layout (F239).** Without `--map`, the owned set comes from
  `scenario_map_files` (index plus `specs/scenarios/*.md`). The NOT RUN exits stay for a missing
  index and for zero rows across all files.
- **R5 — The scanner exempts its own two files (F196 (4), F246).** `project-freshness.sh` carries a
  built-in exemption for exactly `scripts/project-freshness.sh` and `scripts/test-project-freshness.sh`,
  printed as `[ALLOWED]` with its reason like any other. Exact paths with no glob character; a
  project cannot extend the built-in list, only its own `.secret-shapes-allow`.
- **R6 — Tests.** Each behaviour gets a labelled `[102]` case in the suite that owns it, and the
  downstream sandbox run is repeated after the fix with zero reds.

## Threat model

New trust boundary: none. R5 moves an exemption the template already makes for itself into the
scanner, where downstream projects receive it.

| STRIDE | Threat | Mitigation |
|---|---|---|
| Spoofing | A real key committed at `scripts/test-project-freshness.sh` in a project is reported `[ALLOWED]`. | Both paths are CORE: core-machinery-guard refuses agent edits to them downstream, and the next sync overwrites them. The hit is still printed, with path and label, never hidden. |
| Tampering | A project widens the built-in list. | The list is two literals in the script with no glob character, so the `case` match is exact (K12c: a `.bak` neighbour and a copy in another directory still flag). Editing the script is a CORE edit. |
| Repudiation | The exemption is silent. | Every exempted hit prints `[ALLOWED] <path> — <label> — <where> — <reason>`. |
| Information disclosure | None new. The scanner still prints paths and metadata, never key bytes. | — |
| Denial of service | None. Two string comparisons per hit. | — |
| Elevation of privilege | None. The scanner runs no code from the scanned blobs. | — |

R1 widens what the sync copies by data files that CORE_SCRIPTS already names. The two `.tsv` files
are read by `workload-placement.sh` and `quality-gates`, never executed.

### As built

- R3 needed a second half. Docs are add-if-missing only through `RULE_DOCS`, so removing the web
  gate alone delivered nothing to an existing project. The three mobile docs joined `RULE_DOCS`, and
  so did `workload-placement.md`: R1 ships `workload-placement.tsv`, which cites it, and the first
  sandbox rerun showed exactly that one dangling citation.
- R2 put the predicate in one place: `self_test_subject` in `template-identity.sh`. The two existing
  copies (test-sync-prompt-core-parity.sh, test-sync-prompt-bootstrap.sh) use it too, and the URL
  match is now the anchored `template_url_matches`.
- New suite `test-template-autosync-ships.sh` (CORE, and in run-mutation-gate's autosync row).
- Sandbox rerun after the fix: 94 of 94 CORE gates green, `--secrets` reports the two files `[ALLOWED]`.

## Non-goals

Reds that need a project-side decision (a project's own register, its own scenario map). The awk
warning in core-gates.sh (F203). The unbounded mutation step (F204). The template-tree reds F205
lists, which belong to their own suites' rows. Restructuring the stack gate beyond R3.

## Clarifications

### Session 2026-11-16 (auto-picked, recommended option)

- Q: Ship the mobile docs to web projects, or teach validate-rule-citations which docs a stack
  withholds? → A: Ship them. 48 KB of markdown against a second list the validator would need to
  ask template-autosync for, and the mobile canonical-name overlay dangles too, which a withheld
  list would not fix.
- Q: R1: name the two .tsv files next to speckit-version, or derive the list from CORE_SCRIPTS? →
  A: Derive it. Naming them is the second list that core-parity exists to catch.
- Q: R2: skip the whole local-llm-host suite downstream, or only the sync-prompt checks? → A: Only
  those checks (P1–P4, P9). The H and R checks test `local-llm-host.sh`, which ships.
- Q: R5: exempt by path, or by path plus an unchanged manifest hash? → A: By path. History blobs at
  the path are older template bytes no manifest names, and they flag too.

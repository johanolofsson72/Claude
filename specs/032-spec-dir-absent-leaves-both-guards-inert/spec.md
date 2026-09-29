# 032 — spec dir absent leaves both guards inert

Track: spec-only. No entity, no state machine, no new surface. Not hardened: two lines of
extension grammar in three existing guards, plus tests.

Evidence: fundit finding F001 (2026-09-04, from spec 016a), `~/repos/fundit/specs/INDEX.completed.md`
§ 016a. Reported to this register as rows 032/033/034.

## Problem as filed

fundit row 016a (a static holding page) shipped with no spec directory: no `spec.md`, `plan.md`,
`tasks.md` or `interview.md`. The finding says `spec_active.py` resolved the active row to
`found: false` and "both PreToolUse guards had nothing to check".

## What was measured (2026-09-29)

**The filed mechanism is wrong.** Neither guard lets `found: false` through, and neither did in the
version fundit ran on 2026-09-02:

| Guard | `found: false`, source file | Why |
|---|---|---|
| `pipeline-state-guard-hook.sh` | **deny**, all phases missing | `spec_dir is None` → `missing = required[:]` |
| `spec-interview-guard-hook.sh` | **deny**, 0 / 15 answered | `interview = None` → `answered = 0` |

Reproduced at HEAD and against fundit's own copies from `d637ed2` (the guard version on disk when
016a was committed), with a fixture holding `- [/] 016a — holding-page — spec-only track` and no
`specs/016a-*` directory. Both versions return `permissionDecision: deny` for `site/fetch-fonts.mjs`.

**Why 016a still shipped: two separate holes, one closed, one open.**

1. *Closed by 046 (2026-09-12).* The 2026-09-02 guards printed their deny without
   `hookEventName`. Claude Code drops a PreToolUse payload without it, so every deny was inert.
   That covered `site/fetch-fonts.mjs`, the one 016a file with a guarded extension. Spec 029
   confirmed the same thing on rocky, and its tests now read a verdict the way the CLI does
   (`hook_verdict`).
2. *Still open at HEAD.* Every other file 016a produced is outside what the guards ever look at,
   so even a working deny would not have fired:

   | 016a file | Why no guard asks |
   |---|---|
   | `site/index.html` (the product) | `.html` is not in `SOURCE_EXTS` |
   | `site/favicon.svg` | not source |
   | `deploy/nginx-site.conf`, `deploy/security-headers.conf` | config, deliberately exempt |
   | `deploy/fundit-site-stack.yml` | config, deliberately exempt |
   | `site/Dockerfile` | `*/Dockerfile` path allowlist, deliberately exempt |
   | `scripts/deploy-site.sh` | `*/scripts/*` path allowlist, deliberately exempt |

   A spec whose deliverable is markup and stylesheets owes no artifacts as far as the guards know.
   `.cshtml`, `.razor`, `.vue`, `.svelte` and `.astro` are guarded, but plain `.html` and `.css`
   are not. The line is drawn around the wrong thing.

## Decision

- Keep `found: false` → deny. It is already right. Pin it with a test so it stays right, because
  no existing test has an active row with **no directory at all**: `test-pipeline-hooks.sh` always
  creates `specs/003-search`, and `test-active-spec-resolution.sh` creates `specs/007z-…` empty.
- Add `html|htm|css|scss|sass|less` to `SOURCE_EXTS` in all three path guards
  (`spec-register-guard`, `pipeline-state-guard`, `spec-interview-guard`). All three use the same
  list, so they cannot disagree about what counts as source.
- Config (`.yml`, `.conf`, `.json`), `Dockerfile`, `scripts/**` and images stay exempt. The rule
  keeps config editable on purpose, and `scripts/**` has to stay writable so the harness can be
  fixed while a guard is denying.

## Functional requirements

- **FR-01** With an active row whose spec directory does not exist, both
  `pipeline-state-guard-hook.sh` and `spec-interview-guard-hook.sh` deny a source edit. The deny
  reads as `deny` through `hook_verdict` (the CLI's reading, not a jq probe) and names the row id.
- **FR-02** `.html`, `.htm`, `.css`, `.scss`, `.sass` and `.less` are source extensions in all three
  path guards. The 016a fixture (`site/index.html`, `site/style.css`) is denied by both pipeline
  guards, and by `spec-register-guard` when no register exists.
- **FR-03** The three guards carry a byte-identical `SOURCE_EXTS`. A test fails when one drifts.
- **FR-04** The deliberate exemptions still hold: `.yml`, `.conf`, `.svg`, `Dockerfile` and
  `scripts/*.sh` are allowed under the same fixture.
- **FR-05** `.claude/docs/spec-register-rationale.md` lists the new extensions.

## Scenarios

- SC-032-01 active row, no spec dir, `src/app.ts` → both guards deny, both name `016a`.
- SC-032-02 same fixture, `site/index.html` and `site/style.css` → both guards deny.
- SC-032-03 same fixture, `deploy/stack.yml`, `deploy/nginx.conf`, `site/favicon.svg`,
  `site/Dockerfile`, `scripts/deploy.sh` → allowed.
- SC-032-04 no register, marker present, `site/index.html` → `spec-register-guard` denies.
- SC-032-05 `SOURCE_EXTS` is identical across the three guards.
- SC-032-06 artifacts complete (spec, clarifications, plan, tasks, 15 answers) → `site/index.html`
  is allowed. Guarding a new extension must not stop a spec that did its pipeline.

## Out of scope

- A SessionStart warning for "the active row has no spec directory". The guards now deny, so a
  banner would repeat what a deny already says. Recorded as a finding in case a real miss shows up.
- Rewriting fundit's F001 record. Cross-project findings are notify-only. The correction lives here
  and in this row's completed-archive entry.
- Rows 033 and 034, which are the other two items from the same fundit report.

## Clarifications

### Session 2026-09-29

- Q: Is `found: false` the defect? → A: No. Measured deny in both guards, at HEAD and at fundit's
  `d637ed2`. The row's title describes a mechanism that does not exist. The row stays, because the
  outcome it names (016a shipped with no artifacts) is real and still possible through `.html`.
- Q: Rename the row to match the real cause? → A: No. The register id and slug are the pointer
  fundit's F001 cites. The completed-archive entry records the correction.
- Q: Add `.svg`? → A: No. In practice it is an asset, not code, and fundit's `favicon.svg` is not
  what shipped without a spec.

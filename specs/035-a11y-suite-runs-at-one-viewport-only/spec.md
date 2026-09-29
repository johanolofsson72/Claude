# 035 — a11y suite runs at one viewport only

Track: spec-only. No entity, no state machine, no new surface. Not hardened: one doc section, one
checklist line, one new section of an existing script and its self-test.

Evidence: fundit finding F024 (2026-09-05, from spec 004), `~/repos/fundit/specs/FINDINGS.md`.

## Problem as filed

fundit's HealthStrip rendered an unbreakable 47-character name without `min-w-0`, so every surface
scrolled horizontally at 375px. It shipped in spec 001. The shared a11y/visual suite runs at
Playwright's default 1280px, so nothing saw it until spec 004 set 375px by hand in its own test.
F024 asks for the viewport dimension to live in the shared suite, not in each spec.

## What was measured (2026-09-29)

- The template ships no test code. What projects copy is the guidance in `.claude/docs/testing.md`,
  whose visual-regression example calls `SetViewportSizeAsync(375, 812)` inside one test. That is
  the per-spec pattern F024 describes, and nothing asks for an overflow assertion.
- Nothing in `scripts/` looks at viewports.
- fundit today: 10 tests across 7 files each set 375px by hand; `playwright.config.ts` declares no
  narrow project. agentcrm: all three projects in `playwright.config.ts` pin 1280×800. Both shared
  configs run at desktop width only.

## Decision

- `testing.md` gets a **Viewports** subsection under visual regression: the narrow width is a
  **project in the shared Playwright config** (TS) or a **parameter of the shared base fixture**
  (.NET), so every a11y/visual test runs at 375px and 1280px without a spec asking. Every screen
  asserts **no horizontal overflow** at every width (`scrollWidth <= clientWidth`), because a
  screenshot diff only catches overflow once a baseline exists, and a first baseline records it.
- `spec-testing-checklist.md` gets the matching line under cross-cutting checks.
- `project-maintenance.sh` gets section **6d**: a `[VIEWPORT]` finding when a Playwright suite has
  no narrow viewport in its shared configuration. This makes the rule enforced, not advisory.

## Functional requirements

- **FR-01** A tracked `playwright*.config.{ts,js,mjs,cjs}` that declares no viewport narrower than
  480px and no phone device (`devices['iPhone…' | 'Pixel…' | 'Galaxy…']`) → one `[VIEWPORT]` finding
  naming that config. Pass exits 1.
- **FR-02** Several configs: each is judged alone, and the finding names only the offending ones.
- **FR-03** A config that carries the marker `narrow-viewport: not-applicable` (a comment, with its
  reason) is exempt. The rule is "run narrow or say why not", never "run narrow or be red forever".
- **FR-04** A .NET-only suite (`Microsoft.Playwright` in a tracked `.csproj`, no Playwright config)
  → finding unless some tracked `.cs` file on a test path sets a narrow viewport or carries the
  marker. It is the weaker check, because .NET has no shared config file to read, and the message
  says so.
- **FR-05** No Playwright at all (the template repo itself, a pure API) → silent.
- **FR-06** Narrow widths in non-test code (a `width: 350` style in `src/`) do not satisfy the
  .NET check; the search is limited to test paths.
- **FR-07** The finding points at `.claude/docs/testing.md` (Viewports) and names F024's defect
  class (horizontal overflow at phone width).

## Scenarios

- SC-035-01 config with a narrow project (`width: 375`) → no `[VIEWPORT]`, rc 0.
- SC-035-02 config with `devices['iPhone 13']` → no `[VIEWPORT]`, rc 0.
- SC-035-03 config pinned at 1280 only (the agentcrm/fundit shape) → `[VIEWPORT]` naming it, rc 1.
- SC-035-04 two configs, one narrow and one not → only the second is named.
- SC-035-05 desktop-only config with the marker → no `[VIEWPORT]`.
- SC-035-06 .NET suite with `SetViewportSizeAsync(375, 812)` in a test file → no `[VIEWPORT]`.
- SC-035-07 .NET suite with no narrow viewport, and `width: 350` only under `src/` → `[VIEWPORT]`.
- SC-035-08 no Playwright → no `[VIEWPORT]`, rc 0.

## Out of scope

- Detecting whether the overflow assertion exists. It is written many ways, so a grep would be
  wrong often enough to be noise. Guidance only.
- Mobile (RN/Flutter) projects. They render on a device, and the device list in their E2E flows is
  already the viewport dimension.
- Changing fundit's or agentcrm's suites. They get the finding through sync and fix it in their own
  register.

## Clarifications

### Session 2026-09-29

- Q: Per config or per project? → A: Per config. fundit has three (app, demo, site). Each is a suite
  of its own, and a marketing site needs phone width more than an admin does.
- Q: Narrow cut-off? → A: Below 480px. Covers every phone class (320–430) and excludes tablets (768).
- Q: Finding or note? → A: Finding. A note keeps the verdict `clean`, the same defect as row 033.

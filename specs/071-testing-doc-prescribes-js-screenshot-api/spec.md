# 071 — testing-doc-prescribes-js-screenshot-api

Track: spec-only. A documentation fix to `.claude/docs/testing.md` plus a template-only guard test.
No entity, no state machine, no new external surface. No hardening trigger.

Evidence: teach F007 (spec 003, confirmed at teach H1–H3). Diagnosis in `specs/INDEX.pending.md`.

## The defect

`testing.md` § Visual regression shows a ```csharp block calling
`await Expect(Page).ToHaveScreenshotAsync("dashboard-default.png")` and says "Playwright does it
natively". That assertion exists only in the Node runner (`@playwright/test`, `toHaveScreenshot`).
`Microsoft.Playwright` has no screenshot comparison: `PageAssertions` has `ToMatchAriaSnapshotAsync`
and no `ToHaveScreenshotAsync` (checked against playwright.dev/dotnet, 2026-09-30). The follow-up
bullet's `--update-snapshots` is also a Node CLI flag. A .NET project that follows the doc cannot
compile the example. teach and rocky each wrote their own diff to meet the rule.

## Requirements

- **FR-01** The Node example stays, written in TS as `expect(page).toHaveScreenshot(...)` with
  `--update-snapshots`, and is labelled as the Node runner.
- **FR-02** The .NET example takes the picture with `Page.ScreenshotAsync` and diffs it against a
  committed PNG with a named pixel-diff library. The example must compile and behave as described.
- **FR-03** The .NET example stores baselines in the test project's source tree (not `bin/`), per OS,
  and a missing baseline fails with the fix in the message. `VRT_UPDATE=1` writes baselines.
- **FR-04** Screenshots disable animations. The doc says why.
- **FR-05** Alternatives are named: ImageSharpCompare (with its licence caveat), and an in-page
  canvas diff with no package.
- **FR-06** A template-only self-test fails when a C# fence in the template's docs calls a JS-only
  Playwright assertion. It allows real .NET names such as `ToMatchAriaSnapshotAsync`.

## Acceptance

- AC1 No ```csharp / ```cs / ```c# fence in `.claude/docs`, `.claude/rules`, skills or `CLAUDE.md`
  contains `ToHaveScreenshot` or `ToMatchSnapshot`.
- AC2 The .NET example, pasted into an NUnit + Microsoft.Playwright.NUnit 1.59 project with
  Codeuctivity.SkiaSharpCompare, builds with 0 warnings and: no baseline → red, naming `VRT_UPDATE=1`;
  `VRT_UPDATE=1` → baselines written under `<project>/Baselines/<os>/`; unchanged page → green;
  changed page → red with a pixel count.
- AC3 Sabotage: the pre-071 snippet fed to the guard is caught (exit 1).

## Clarifications

### Session 2026-09-30

- Q: Default library ImageSharpCompare (named in the diagnosis) or SkiaSharpCompare? → A:
  SkiaSharpCompare. Same author, same API, Apache-2.0 with SkiaSharp (MIT). ImageSharp's split
  licence charges above a revenue threshold. ImageSharpCompare is still named as an alternative.
- Q: Ship the guard to projects? → A: No. It checks the template's own docs; projects receive the
  fixed doc via sync. Listed in TEMPLATE_ONLY_SCRIPTS so `--unlisted` stays silent.
- Q: Fix the two SIGPIPE-prone sabotage asserts 070 left in `test-project-freshness.sh` (the
  validate-no-sigpipe gate is red at HEAD)? → A: Yes, in place. The fix is two lines, smaller than
  recording it, and the arms are negated, so a 141 would read as a pass.

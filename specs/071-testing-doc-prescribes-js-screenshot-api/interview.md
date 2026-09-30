# Spec interview — 071-testing-doc-prescribes-js-screenshot-api

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. Spec-only, no hardening trigger (one doc section and one template-only self-test), so no overflow.

## Q1 — Scope boundary
**Q:** What is in, what is out?
**A (auto):** In: the Visual regression section of testing.md, and a guard test. Out: testing-mobile.md (its RN/Flutter advice is correct), a shared VisualBaseline helper shipped to projects, and project-maintenance checks for VRT presence.

## Q2 — Primary actor
**Q:** Who is hurt today?
**A (auto):** A .NET project agent following testing.md to meet the VRT requirement. The example does not compile, so it either stalls or builds a bespoke diff (teach, rocky).

## Q3 — Happy path
**Q:** What does done look like?
**A (auto):** A .NET reader copies the C# block into a ScreenTest-derived fixture, adds one package, and gets a working baseline gate. A Node reader gets the built-in toHaveScreenshot.

## Q4 — Is the claim true?
**Q:** Is ToHaveScreenshotAsync really absent from Microsoft.Playwright?
**A (auto):** Yes. playwright.dev/dotnet PageAssertions lists ToMatchAriaSnapshotAsync and no screenshot assertion; the visual-comparisons page is Node-only.

## Q5 — Which diff library
**Q:** Which comparer does the example use?
**A (auto):** Codeuctivity.SkiaSharpCompare. Same API as ImageSharpCompare, permissive licence, and it ships its Linux native assets.

## Q6 — Keep the Node example?
**Q:** Drop Node entirely, since .NET is the house stack?
**A (auto):** No. React/Node projects exist in the fleet and the built-in API is the best option there. Label it and write it in TS.

## Q7 — Baseline location
**Q:** Where do baselines live?
**A (auto):** In the test project source tree, Baselines/<os>/, resolved from TestDirectory up three levels. A relative "Baselines" would land in bin/ and never be committed.

## Q8 — Per-OS baselines
**Q:** One baseline set or per OS?
**A (auto):** Per OS. Font rendering differs between macOS and Linux, and a loosened threshold stops catching real drift.

## Q9 — Missing baseline
**Q:** What happens when no baseline exists?
**A (auto):** The test fails and names VRT_UPDATE=1. Writing one silently lets a fresh clone pass with nothing compared (fail fast).

## Q10 — Update mode
**Q:** How are baselines written?
**A (auto):** VRT_UPDATE=1 writes the baseline and marks the test Inconclusive, so an update run cannot be read as a pass.

## Q11 — Threshold
**Q:** What tolerance?
**A (auto):** 0.1 % of pixels, the figure rocky measured as holding under load once animations are disabled.

## Q12 — Animations
**Q:** Disable animations at capture?
**A (auto):** Yes, ScreenshotAnimations.Disabled. rocky measured a transition mid-frame reddening a golden under load.

## Q13 — Error message
**Q:** What does a red diff say?
**A (auto):** The baseline path and the differing pixel count.

## Q14 — Width in the name
**Q:** How does the example know the viewport?
**A (auto):** A protected Width property on ScreenTest. Reading the primary-constructor parameter from a derived class raises CS9107.

## Q15 — Guard scope
**Q:** Which files does the guard scan?
**A (auto):** .claude/docs, .claude/rules, skill SKILL.md files, and CLAUDE.md — only inside C# fences.

## Q16 — Guard false positives
**Q:** Which names must not be flagged?
**A (auto):** ToMatchAriaSnapshotAsync (real in .NET) and anything in a ts/js fence or prose.

## Q17 — Does the guard ship?
**Q:** Is the guard a CORE script?
**A (auto):** No, template-only, and listed in TEMPLATE_ONLY_SCRIPTS so --unlisted does not report it forever.

## Q18 — Reversibility
**Q:** Rollback story?
**A (auto):** Doc and a standalone test; git revert is the whole story. Projects pick the doc up on their next sync.

## Q19 — Acceptance
**Q:** How is the example proven?
**A (auto):** Compile and run it in a scratch NUnit project: missing, update, unchanged, changed.

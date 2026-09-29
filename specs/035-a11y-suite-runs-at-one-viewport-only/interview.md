# Spec interview — 035-a11y-suite-runs-at-one-viewport-only

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. No overflow: no hardened trigger fires (no auth/PII/upload/new surface, no state machine, no new entity, 4 files).

## Q1 — Scope boundary
**Q:** Does the template ship a shared a11y test file that projects copy?
**A (auto):** No. It ships guidance (`testing.md`) and a maintenance pass. The fix goes into both: the doc says where the viewport lives, and the pass checks that it is there.

## Q2 — Primary actor
**Q:** Who is hurt?
**A (auto):** A developer whose Playwright suite runs only at 1280px. A layout that overflows at phone width passes every test and ships, as fundit's HealthStrip did.

## Q3 — Happy-path outcome
**Q:** What does done look like?
**A (auto):** `testing.md` puts the narrow width in the shared config, and a maintenance pass on a project whose shared config has no narrow viewport is red and names the config.

## Q4 — Where the check runs
**Q:** Hook, stop-validation, or maintenance pass?
**A (auto):** Maintenance pass (new section 6d). A suite's configuration changes rarely, so a per-edit hook would cost for no gain. The pass already runs every session through maintenance-due.

## Q5 — Finding or note
**Q:** Red or report-only?
**A (auto):** Red (`add`). A note leaves the verdict `clean`, which is the silence row 033 removed.

## Q6 — Unit of judgment
**Q:** Is the check per project or per config file?
**A (auto):** Per config. fundit runs three configs (app, demo, site), each its own suite. One narrow config must not excuse the other two.

## Q7 — Narrow threshold
**Q:** What counts as narrow?
**A (auto):** A width below 480px, or a phone device descriptor (iPhone, Pixel, Galaxy). 480 covers phones from 320 to 430 and excludes tablets.

## Q8 — Opt-out
**Q:** How does a desktop-only product avoid a permanent finding?
**A (auto):** A `narrow-viewport: not-applicable` comment in the config, with its reason. Running narrow or stating why not are both acceptable; saying nothing is not.

## Q9 — .NET suites
**Q:** .NET Playwright has no config file. What is checked there?
**A (auto):** Any tracked `.cs` file on a test path that sets a width below 480 (`SetViewportSizeAsync`, `ViewportSize`/`Width =`) or carries the marker. Weaker than the TS check, and the finding says so.

## Q10 — False satisfaction
**Q:** Can `width: 350` in production CSS-in-JS satisfy the check?
**A (auto):** Not for .NET. Its search is limited to paths containing test/e2e/playwright. For TS, only the config file is read.

## Q11 — File discovery
**Q:** Which files are candidates?
**A (auto):** `git ls-files --cached --others --exclude-standard`: tracked plus untracked-not-ignored, so node_modules and bin/obj never walk. A project that is not a git repo skips the section silently, like the other git-based sections.

## Q12 — Overflow assertion detection
**Q:** Does the check verify an overflow assertion exists?
**A (auto):** No. It is written too many ways to grep reliably. The doc asks for it; the check verifies only the narrow viewport.

## Q13 — Message
**Q:** What does the finding say?
**A (auto):** The config path, that it runs at desktop width only, the defect class (horizontal overflow at phone width, fundit F024), and the fix: a narrow project per `.claude/docs/testing.md` (Viewports) or the not-applicable marker.

## Q14 — Mobile projects
**Q:** Does this apply to RN/Flutter?
**A (auto):** No. They have no Playwright config and no `Microsoft.Playwright` reference, so the section stays silent. Their device list is their viewport dimension.

## Q15 — Existing projects
**Q:** What happens to fundit and agentcrm after sync?
**A (auto):** Both get a `[VIEWPORT]` finding on their next pass. That is the intended outcome: their shared configs run desktop-only. They fix it in their own register.

## Q16 — Portability
**Q:** Any platform traps in the new section?
**A (auto):** `grep -E` only (no -P), no GNU-only flags, bash 3.2-safe. `validate-portability.sh` runs on the changed script.

## Q17 — Reversibility
**Q:** Rollback story?
**A (auto):** Revert the commit. No state is written, and the pass only reads files.

## Q18 — Acceptance
**Q:** Measurable definition of done?
**A (auto):** SC-035-01..08 as C46-C53 in `test-project-maintenance.sh`, with the red arms shown failing on HEAD before the section exists. The full maintenance self-test stays green.

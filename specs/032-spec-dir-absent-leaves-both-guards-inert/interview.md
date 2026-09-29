# Spec interview — 032-spec-dir-absent-leaves-both-guards-inert

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. No overflow: no hardened trigger fires (no auth/PII/upload/new surface, no state machine, no new entity, 5 files).

## Q1 — Scope boundary
**Q:** Does this spec change how `spec_active.py` resolves a row with no directory?
**A (auto):** No. It returns `found: false`, and both guards already turn that into a deny. The resolver is correct, so the spec pins that behaviour with a test and leaves the code alone.

## Q2 — Primary actor
**Q:** Who is hurt?
**A (auto):** A developer on a project whose active spec produces markup or stylesheets. The spec ships with zero pipeline artifacts, nothing objects, and it only surfaces after the fact, the way fundit's 016a did.

## Q3 — Happy-path outcome
**Q:** What does done look like?
**A (auto):** The 016a fixture gets a deny for `site/index.html` from both pipeline guards, and a project that has finished its artifacts can still edit it.

## Q4 — Root cause
**Q:** Why did 016a ship if the guards deny `found: false`?
**A (auto):** The one guarded file (`fetch-fonts.mjs`) hit the pre-046 guards, whose deny had no `hookEventName` and was dropped. Everything else was `.html`, config, a Dockerfile or `scripts/**`, which no guard looks at.

## Q5 — Which extensions
**Q:** Which extensions join the source list?
**A (auto):** `html`, `htm`, `css`, `scss`, `sass`, `less`. Markup and stylesheets are product code in a static site and in the legacy HTML/CSS/jQuery stack that CLAUDE.md lists. Template dialects such as `.hbs`, `.njk` and `.ejs` stay out because no measured miss involves them (YAGNI).

## Q6 — Config stays exempt?
**Q:** Should `.yml` and `.conf` be guarded too, since 016a shipped three of them?
**A (auto):** No. The rule keeps config editable on purpose. A deploy manifest edited during a live incident must not wait for a spec interview.

## Q7 — scripts/** exemption
**Q:** `scripts/deploy-site.sh` passed on the path allowlist. Should that close?
**A (auto):** No. `scripts/**` has to stay writable so the harness can be fixed while a guard is denying. Closing it would lock a project out of its own repair route.

## Q8 — Which guards
**Q:** Only the two pipeline guards, or the register guard too?
**A (auto):** All three. They share one grammar of "what is source", and a split list is the drift the 007m resolver was written to end.

## Q9 — Drift protection
**Q:** How do the three lists stay equal?
**A (auto):** A test extracts `SOURCE_EXTS=` from each guard and fails when they differ. No shared sourced file: each guard is a single CORE script, and a new dependency would be one more thing a sync can drop.

## Q10 — Four observable states
**Q:** Error, empty, loading and success for a hook?
**A (auto):** Success is a silent allow. The error is a deny whose reason names the spec id and the missing phases (it already does). Empty (no active row) is an allow, unchanged. There is no loading state. No new message text is needed.

## Q11 — Verdict reading
**Q:** How does the test read the verdict?
**A (auto):** Through `hook_verdict` (spec 029), so a deny without `hookEventName` reads as `dropped`, not as `deny`. That is the exact failure that let 016a through.

## Q12 — Performance
**Q:** Does widening the list cost anything on the hot path?
**A (auto):** The raw-payload precheck matches the same alternation, just six terms longer. It is a bash regex over a payload of at most 4 KB, so the cost is well under a millisecond, and the list is still built once.

## Q13 — Blast radius
**Q:** Which synced projects start seeing new denies?
**A (auto):** Only a project whose active spec lacks artifacts and whose next edit is `.html`/`.css`. That edit should have been denied all along. A project with complete artifacts sees no change.

## Q14 — Edge cases
**Q:** Upper-case `INDEX.HTML`, `.min.css`, `.html` under `specs/`?
**A (auto):** The extension is lower-cased before the test, so upper case is guarded. `.min.css` has the extension `css`, so it is guarded. `specs/**` stays allowlisted, so a spec's own HTML mockups are editable.

## Q15 — Acceptance criteria
**Q:** What is measurable?
**A (auto):** SC-032-01..06 in spec.md as a self-test (`scripts/test-spec-dir-absent.sh`). The new arms fail on HEAD and pass after the change. The existing guard tests stay green.

## Q16 — Reversibility
**Q:** How is it undone?
**A (auto):** Remove the six terms from three lines. There is no data and no migration.

## Q17 — Non-goals
**Q:** SessionStart banner for a directory-less active row?
**A (auto):** Out of scope. Recorded as a finding. The deny now carries that message at the moment it matters.

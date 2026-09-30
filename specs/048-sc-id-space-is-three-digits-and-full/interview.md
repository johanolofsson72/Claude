# Spec interview — 048-sc-id-space-is-three-digits-and-full

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. Spec-only, no hardening trigger, so no overflow.

## Q1 — Scope boundary
**Q:** What is in, what is out?
**A (auto):** In: the SC-id wording, locate recipe and namespace paragraph in `scenarios.md`; the
3–4 digit caps in `validate-fixture-map-ids.sh`; a traceability case and two sabotage arms for the
width rule; two fixture-gate arms. Out: renumbering any project map, spec-kit's criteria template.

## Q2 — Primary actor
**Q:** Who is hurt today?
**A (auto):** A project past SC-999 (ighweld). Its rule text contradicts its map, its locate grep
misses most of the map, and the fixture gate would go blind once it passes 9999.

## Q3 — Happy path
**Q:** What does done look like?
**A (auto):** The rule says "three digits minimum, grows past 999". Every tool that reads ids reads
any width of three or more, and the width discriminator is pinned by a test that sabotage can break.

## Q4 — Padding policy
**Q:** Re-pad old ids when the map grows?
**A (auto):** No. Ids are permanent handles. Mixed width is the intended state of a grown map.

## Q5 — Gap reuse
**Q:** May a nearly full map reuse low gaps?
**A (auto):** No. The allocator appends past the highest id, and the rule says so. A low gap is the
id most likely to still be named by an old test.

## Q6 — Namespace discriminator
**Q:** Does growth to four digits break the criteria/scenario split?
**A (auto):** No, because the gate measures the narrowest id and a grown map still starts at three
digits. The risk is a future edit that measures the widest id. FR-05/06 pin it.

## Q7 — Map that starts wide
**Q:** What about a map whose first id is already four digits?
**A (auto):** Its narrowest width is four, so a three-digit reference is out-of-range, and its floor
agrees. No special case.

## Q8 — Fixture gate upper bound
**Q:** Keep any upper bound on digits in `validate-fixture-map-ids.sh`?
**A (auto):** No. The lower bound (3) and the hyphen keep out criteria and `SC2086`. An upper bound
only hides real ids.

## Q9 — Five-digit tokens vs owned four-digit ids
**Q:** Does removing the cap make a five-digit token collide with its first four digits?
**A (auto):** No. The gate compares whole numbers; C11 stays green and proves it.

## Q10 — Error semantics
**Q:** Does any exit code change?
**A (auto):** No. Same exits in both gates; only which tokens count as ids changes.

## Q11 — Four observable states
**Q:** Success / error / empty / loading?
**A (auto):** CLI tooling. Success is the existing clean output; error is the existing finding list;
empty (no map) stays NOT RUN (exit 3). No loading state.

## Q12 — Concurrency
**Q:** Any ordering or concurrency concern?
**A (auto):** None. Both gates are read-only scans.

## Q13 — Integration points
**Q:** What else reads SC ids?
**A (auto):** `scenario-map-rows.sh`, `scenario-probe-ids.sh` and `next-scenario-id.sh` already read
`[0-9]+`. `validate-scenario-traceability.sh` extracts any length. No change needed there.

## Q14 — Acceptance criteria
**Q:** How is done measured?
**A (auto):** case48 green, sabotage arms (p) and (q) red on case48, the two new fixture arms red on
HEAD and green after, and both suites fully green.

## Q15 — Reversibility
**Q:** Rollback story?
**A (auto):** Plain revert. No data or map is migrated.

## Q16 — Test fixtures must not spell real ids
**Q:** How do the new arms avoid binding a real scenario?
**A (auto):** Build ids at runtime as the harnesses already do (`id()` helper, placeholders). case15
and R3 police it.

## Q17 — Documentation of the locate recipe
**Q:** What should the locate grep be?
**A (auto):** `SC-[0-9]{3,}`. It matches every map id and no criterion under three digits.

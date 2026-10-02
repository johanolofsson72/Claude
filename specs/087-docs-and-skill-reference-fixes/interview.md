# Spec interview — 087-docs-and-skill-reference-fixes

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. No overflow: spec-only, no hardened trigger (no auth, PII, upload, new external
surface, state machine or entity). Every question below had a defensible recommendation.

## Q1 — Scope boundary
**Q:** What is in, what is out?
**A (auto):** In: F006, F007, F008, F009, F054 as R1–R6. Out: upgrading the allium CLI, harvesting
memory already stranded, other spec-kit templates.

## Q2 — Primary actor
**Q:** Who is hurt today?
**A (auto):** The developer whose new spec collides with the scenario map, whose review agent
reads an old tree or loses its memory, and whose elicit copies a warning-laden example.

## Q3 — SC renaming scheme (F008)
**Q:** Letters (`SC-A`), a spec-prefixed form (`NNN-SC001`), or another prefix (`OC-001`)?
**A (auto):** Letters. `/speckit-analyze` and `/speckit-converge` key on the `SC-` prefix, so a new
prefix would drop Success Criteria from their inventory. The template has no spec number to
prefix with. `SC-A` keeps the prefix and cannot match `SC-[0-9]+`.

## Q4 — Where the rewrite runs (F008)
**Q:** A new script, or the existing policy script?
**A (auto):** The policy script. It already runs after every `specify init` (speckit-sync,
autosync) and already patches spec-kit text with anchors and markers.

## Q5 — Moved anchor (F008)
**Q:** If spec-kit rewords the Success Criteria lines, is that exit 2 like the stop patches?
**A (auto):** Yes. A silent miss puts the collision back in every new spec, which is exactly the
defect. Same FAIL line shape.

## Q6 — Existing specs (F008)
**Q:** Rename SC ids in specs already written?
**A (auto):** No. The patch touches the template only; existing specs are the project's history,
and ighweld already renamed theirs.

## Q7 — Isolation removal vs write-through (F009)
**Q:** Drop `isolation: worktree`, or keep it and copy memory back on SubagentStop?
**A (auto):** Drop it. The three agents gain nothing from isolation that outweighs both defects:
the scanner and reviewer only read, and a worktree is what makes them read a stale tree (F007).
A write-through hook would fix F009 and leave F007.

## Q8 — db-agent (F009)
**Q:** db-agent writes migrations; does it keep isolation?
**A (auto):** No. It writes to the project like the main session does, on main, with no branch to
merge back. Its isolated edits would need a merge step this workflow does not have.

## Q9 — Regression guard (F009)
**Q:** Prose only, or a check?
**A (auto):** A check in `project-maintenance.sh` (`[AGENTS]`), because synced projects add their
own agents and a doc line does not stop them.

## Q10 — Finding or note (F009)
**Q:** Is the combination a finding or a note?
**A (auto):** A finding. It loses data every time the agent runs.

## Q11 — How the agent proves its tree (F007)
**Q:** `security-scanner` has no Bash; how does it name the tree?
**A (auto):** The dispatcher passes HEAD and the changed paths in the prompt; the agent echoes them
in its first line and globs a path before calling anything missing. Granting Bash to a read-only
scanner is a wider change than the finding needs.

## Q12 — Missing-claim wording (F007)
**Q:** What does the agent say when it cannot find something?
**A (auto):** "not found at <path>", never "not implemented".

## Q13 — Contrast section placement (F006)
**Q:** testing.md, or the design reference library?
**A (auto):** testing.md, next to visual regression: it is a test that lies, not a design rule.

## Q14 — Recommended contrast method (F006)
**Q:** Which method does the doc recommend?
**A (auto):** axe-core's `color-contrast` rule first; for a hand-rolled check, normalise through a
1×1 canvas pixel so the browser does the colour-space conversion.

## Q15 — Allium target version (F054)
**Q:** Which CLI must the example be clean on?
**A (auto):** 3.6.1, the version the finding measured. Verified with a scratch `cargo install`, not
by upgrading the machine's CLI.

## Q16 — Allium example coverage (F054)
**Q:** May the fix remove constructs from the example?
**A (auto):** No. Fix by declaring and using what is shown (a creation rule for `pending`, a deliver
rule, `Priority` and `Address` as Order fields, a cancel guard that matches the declared
transitions). The example teaches syntax; dropping syntax to silence a lint teaches less.

## Q17 — Error, empty, loading states
**Q:** Which of the four states apply?
**A (auto):** Error: the policy's exit 2 and the `[AGENTS]` finding. Empty: no template, no agents
dir, nothing reported. Loading: N/A, nothing interactive.

## Q18 — Reversibility
**Q:** Can it be undone?
**A (auto):** Yes. The policy patch is marker-stamped text; a re-init restores spec-kit's original,
and the agent and doc changes are plain edits.

## Q19 — Cross-platform
**Q:** Anything platform-specific?
**A (auto):** The template patch is Python inside the existing heredoc; the maintenance check is
grep/awk with no GNU-only flags.

## Q20 — Acceptance
**Q:** What is done?
**A (auto):** SC-A..SC-C in the spec, plus the touched self-tests and the declared suite green.

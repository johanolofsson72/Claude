# Spec interview — 081-always-loaded-context-budget

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. Spec-only, no hardened trigger; the cap and the target came with the approved proposal.

## Q1 — Scope boundary
**Q:** Does 081 trim path-scoped rules too?
**A (auto):** No. They load only when a matching file is touched; the proposal is about the per-session floor.

## Q2 — Scope boundary
**Q:** Does it change projects' own CLAUDE.md?
**A (auto):** No. Rules are CORE and reach projects through sync; a project's CLAUDE.md is project-owned. The report shows them their number.

## Q3 — Primary actor
**Q:** Who runs the measurement?
**A (auto):** The ratchet test in the template, `project-maintenance.sh` in projects, and a developer by hand.

## Q4 — Happy path
**Q:** What does success look like?
**A (auto):** `context-budget.sh` prints a total under 40,960 bytes for the template, and a later edit that grows it past the baseline turns the test red.

## Q5 — Data model
**Q:** What counts as always-loaded?
**A (auto):** CLAUDE.md, .claude/CLAUDE.md, unscoped .claude/rules/**/*.md, and @-imports from CLAUDE.md. That is what Claude Code loads at session start.

## Q6 — Data model (frontmatter)
**Q:** How is "scoped" detected?
**A (auto):** A `paths:` key inside a leading `---` frontmatter block. A `paths:` line in the body does not count.

## Q7 — Validation
**Q:** What does the script do with an @-import that does not exist?
**A (auto):** Reports it as missing and exits 2. A budget that silently skips a file is under-reporting.

## Q8 — Observable states
**Q:** What does each outcome print?
**A (auto):** Within cap: the table and "within budget". Over: the table and the bytes over. Error: what could not be measured. Empty (no CLAUDE.md, no rules): total 0, within budget.

## Q9 — Units
**Q:** Bytes or tokens?
**A (auto):** Bytes. Deterministic and tool-free; tokens are roughly bytes/4 and the line says so.

## Q10 — The cap
**Q:** Why 40 KB?
**A (auto):** From the proposal: 69 KB to about 10k tokens is a 40% cut, reachable by moving rationale without losing a contract.

## Q11 — Ratchet semantics
**Q:** How does the ratchet move?
**A (auto):** Down only. Total above the baseline fails; more than 1 KB below prints the update command. Raising it is an explicit baseline edit in a diff.

## Q12 — Integration
**Q:** Which scripts read rule text that could break?
**A (auto):** Checked: only local-llm-plan-feasibility-hook.sh parses CLAUDE.md, for the `## Tech stack` section. Other scripts cite rule files by path, and those paths stay.

## Q13 — Edge case (cited headings)
**Q:** What about docs citing a rule section by name?
**A (auto):** Every `rules/<file>.md` "§ <heading>" or quoted heading reference is grepped before and after; a moved heading keeps a stub with a pointer.

## Q14 — Edge case (template detection)
**Q:** How does the test know it runs in the template?
**A (auto):** The same test the guards use in reverse: no language marker at the repo root. A project runs only the fixture half.

## Q15 — Non-functional
**Q:** Runtime?
**A (auto):** One pass over a dozen files; well under a second. Pure bash + awk, Git Bash safe.

## Q16 — Reversibility
**Q:** How is a trim undone?
**A (auto):** The moved text is verbatim in the rationale doc; moving it back is a cut and paste, and git has the before.

## Q17 — Non-goals
**Q:** Is rewording a rule in scope?
**A (auto):** No. Moving is in scope, rewording is not: a moved paragraph keeps its words so the rationale docs stay greppable for the old text.

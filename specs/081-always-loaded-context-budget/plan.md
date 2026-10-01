# 081 — plan

1. `scripts/context-budget.sh` — bash 3.2 + awk: collect CLAUDE.md, .claude/CLAUDE.md, unscoped rules (frontmatter `paths:` check), @-imports; table, total, cap, exit 0/1/2; CLAUDE.local.md reported apart (R1).
2. `scripts/context-budget.baseline` + `scripts/test-context-budget.sh`: fixtures for every rule in R1; template-only ratchet check (R2).
3. `project-maintenance.sh` — one report line, never a failure (R3).
4. Trim (R4): CLAUDE.md first (critical rules restate loaded rules → one line each; DoD and reference list compressed; rationale → claude-md-rationale.md), then spec-register.md, feature-pipeline.md, spec-interview.md, carve-budget.md, spec-hardening.md, the small rules. Before/after grep of cited headings.
5. CORE registration (R5); suites green.

# Plan — 106

| R | Files | Check |
|---|---|---|
| R1 | `scripts/template-autosync.sh` (readable-HEAD check, rc 5), `scripts/harness-gitignore.sh` (`--tracked` exit 2) | `[106]` cases with a git that cannot run, in test-template-autosync-ships.sh and test-harness-gitignore.sh |
| R2 | `scripts/core-gates.sh` (ENVIRON), `scripts/project-maintenance.sh` (5b stdout only) | `[106]` case in test-core-gates.sh: no stderr under gawk/any awk |
| R3 | `scripts/validate-rule-citations.sh` (downstream skip of sync-prompt.md) | `[106]` case in test-validate-rule-citations.sh, both directions |
| R4 | `scripts/template-autosync.sh` (RULE_DOCS, RULE_ADDS), reworded citations in sqlite-nfs-safety-hook.sh, design-references.md, project-update and project-wizard skills | `[106]` parity section + RULE_ADDS fixture case in test-template-autosync-ships.sh |
| R5 | `scripts/test-context-budget.sh` | billing sandbox green |
| R6 | `scripts/test-template-identity.sh` | sandboxes green, template green |
| R7 | `scripts/validate-sync-sandbox-declarations.sh` (message) | `[106]` case in its test |
| R8 | sandbox rerun | only project-owned or recorded reds |

Hardening: threat model in spec.md; adversarial review of R1/R4; mutation pass on changed lines
(run-mutation-gate); stress n/a (no input-size dependence beyond a grep over the tree).

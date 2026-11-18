# Plan — 110

| R | Where | Check |
|---|---|---|
| R1 | `max-id-in-refs.sh --next/--block` + `SPEC_LANE_SLOT`; `finding.sh --add`; `next-scenario-id.sh --block` | `test-next-scenario-id.sh`, `test-finding.sh` stripe cases |
| R2 | none (gate exists) | `test-validate-scenario-traceability.sh` split-layout duplicate case |
| R3 | `checkpoint-cadence.sh`: highest H, git tick order, file-order fallback | `test-checkpoint-cadence.sh` milestone-order case in a real git fixture |
| R4 | `lane_status.py` OWNER, `spec_active.py` OWNER_RE, orientation hook awk | `test-lane-orientation.sh`, `test-active-spec-resolution.sh` |
| R5 | `lane_status.py` `phase_debt_open` | `test-lane-orientation.sh` (or lane-status test) |
| R6 | `archive-completed-rows.sh` membership | `test-archive-completed-rows.sh` |
| R7 | `scenario-map-reminder-hook.sh` SLUG | `test-scenario-map-reminder.sh` |
| R8 | `context-budget.sh` synced branch | `test-context-budget.sh` |
| R9 | `validate-scenario-traceability.sh` extractor regex + sed | `test-validate-scenario-traceability.sh` |

Docs: `lane-handoff-rationale.md` gets the `SPEC_LANE_SLOT` paragraph; the lane-handoff rule's tool
line names it in a few words (budget checked).

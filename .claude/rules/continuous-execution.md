# Continuous execution rule

A multi-phase plan is **one task, not N tasks**. Phases are chapter headings, not permission gates. Long form (the anti-pattern list, the full pre-081 and pre-099 text): `.claude/docs/continuous-execution-rationale.md`.

## The contract (BLOCKING)

Once the work is authorized, run it to completion without stopping between phases, todos, files or `tasks.md` items. Never ask "Phase 1 complete, should I continue?", "ready for the tests?" or "want me to proceed?", and never relay spec-kit's checklist stop.

## Legitimate stops

1. Genuine ambiguity the plan does not cover (`AskUserQuestion`).
2. A hard blocker: missing credentials or infrastructure, a failing external dependency, conflicting requirements.
3. The plan is fully complete and verified.
4. Allium/TLA+ findings (`.claude/rules/validation-followup.md`).
5. The end of a spec when a register exists: the status summary (`.claude/rules/spec-register.md`).
6. A register-rewrite proposal.
7. A convergence stop (`.claude/rules/carve-budget.md`).

Before any other stop, check whether the next step is already in the plan; if it is, continue. `scripts/continuous-execution-hook.sh` refuses phase-continuation questions: stop asking, don't rephrase.

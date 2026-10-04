# Spec hardening rule (risk tier above "full", plus integration checkpoints)

**Hardened** is the full pipeline plus four additions. A periodic **integration checkpoint** covers the seams between specs. Long form (reasoning, the full pre-081 and pre-099 text): `.claude/docs/spec-hardening-rationale.md`.

## When a spec is HARDENED (BLOCKING — any one trigger)

At triage: (1) **risk domain:** auth/authz, payments, PII or secrets, file upload/parsing, or a **new external API surface**; (2) a full track with a **state machine or concurrency**; (3) a **`[hardened]`** row tag; (4) a **new entity/aggregate** or an estimated **≥ 6 files**. When in doubt, harden.

## What hardening adds (BLOCKING — all four)

1. **Threat model before implement:** `security-scanner` plus a STRIDE pass per new trust boundary, in a `## Threat model` section of the spec. A threat with no mitigation is an open finding.
2. **Expanded destructive tests and stress:** the top of the input-domain band, plus `.claude/docs/stress-testing.md`. The four states hold under stress.
3. **Hard mutation gate:** the Stryker kill rate on the changed critical modules blocks the tick. A timed-out mutant is not a kill (`.claude/rules/mutation-timeouts.md`).
4. **Adversarial review:** `security-scanner` in "assume it's exploitable" mode, a language reviewer on the new trust boundaries, and `/security-review`. Every flag gets fix, defer or dismiss.

## Integration checkpoint (BLOCKING — every 5 feature specs)

After 5 feature specs since the last checkpoint (`scripts/checkpoint-cadence.sh` counts), work the row `H<n> — integration-hardening — checkpoint`: **full regression** (unit + integration + E2E + visual), **security sweep** (`security-scanner` + `scripts/project-freshness.sh`), **scenario-map reconciliation**, and a **mutation spot-check** on the 2–3 most-changed critical modules. Many findings become **one consolidated row**. It ends with a status summary.

Full, hardened and checkpoint rows begin in a fresh session: when the SessionStart banner fires over unrelated context, stop and tell the user to run `/clear`.

## Forbidden

A risk-domain spec on the plain full track. Treating `[hardened]` as decorative. Skipping the checkpoint. Downgrading the mutation gate on a hardened spec. Powering through after the `/clear` banner. Any hardening step as a GitHub Action: local or Claude cloud only (`scripts/workload-placement.tsv`).

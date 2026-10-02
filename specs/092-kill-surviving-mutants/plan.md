# Plan — 092 kill surviving mutants

## Approach

Measure first (done: 28/69, seed 20261002). Then arm each survivor in the suite that owns the
behaviour, and re-measure with the same `--lines`. No production behaviour changes. If a survivor
turns out to be dead code, the smallest change that makes the intent testable is recorded here.

| R | Files | Shape |
|---|---|---|
| R1 | test-guard-canonical-paths.sh | no-marker fixture (three guards), a marker in a subdir only, and the `.csproj` beside the file as the positive control |
| R2 | hook-verdict.sh, test-hook-channels.sh, test-guard-root-anchor.sh, test-pipeline-hooks.sh | `hook_verdict OUT [RC]` → `exit-<RC>` on non-zero; the rc-blind helpers pass `$?` |
| R3 | test-guard-fail-closed.sh | four deny routes, each `deny` + exit 0 |
| R4 | test-template-autosync-arms.sh (+ owning suites) | one case per autosync line |
| R5 | test-project-maintenance.sh, test-maintenance-trust.sh | one case per maintenance line; 1081/1098 as contract tests |
| R6 | test-validate-scenario-traceability.sh, test-project-freshness.sh | `--dir` with no value; a bounded no-trailing-newline allow file |
| R7 | — | re-run the gate on the same lines |

Three workers in parallel: autosync (R4), maintenance (R5), guards + R6 (R1–R3, R6). Each verifies
its own lines with `--lines` before handing back.

## Verification

Each touched suite green on its own, the full template suite, `--lines` ≥ 95%, adversarial review of
the diff (no relaxed expectation), /security-review, /tla on the verdict rule (R2).

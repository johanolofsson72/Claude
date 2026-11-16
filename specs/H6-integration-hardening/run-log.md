# Run log — H6-integration-hardening

One line per event. Failure memory for a spec resumed in a fresh session.
Append-only, deduped, capped. NOT pipeline input — read the tail, never the whole file.

- 2026-10-04T17:58Z · 2026-10-04 state: §2 security done (freshness clean; scanner sweep 10 items, F184 F187 F193 reproduced, rest read from code -> F184–F193). §3 n/a (no SCENARIOS.md). §4 mutation seed 6, custom table guard-lib/trust-anchor/settings-edit/hook-notice: 41/48 = 85.4%, guard-lib 11/12, trust-anchor 11/12, settings-edit 11/12 +1 timeout, hook-notice 8/12 -> F194 F195. §1 suite: project-maintenance.sh --suite started ~19:10 in background; log was in session scratchpad (gone next session) -> check stamp via maintenance-due.sh --brief, rerun if not green. TODO: write checkpoint.md (H5 shape), commit F184–F195 + checkpoint, tick H6, push, status summary.
- 2026-10-04T18:27Z · Suite result 2026-10-04: UNMEASURED, exit 124 (the inner loop exits 1 before 124 on any FAIL, so zero FAILs); one TIMEOUT: test-validate-scenario-traceability.sh past 900s (249s at H5; the mutation run shared the machine). Not stamped, maintenance still due. Tomorrow: rerun that one test alone, then the full suite on a quiet machine to stamp it.
- 2026-11-16T09:08Z · 2026-11-16 resume: findings F184–F195 already committed upstream. Rerunning project-maintenance.sh --suite (log: scratchpad/h6-suite.log), then checkpoint.md, tick, push.
- 2026-11-16T09:50Z · 2026-11-16: suite run 1 red: test-on-linux, test-portability-audit, test-self-test-prologue — all from test-worktree-root-detection.sh (d6cc25c) missing the self-test prologue; fixed in place. F224 (suite report hides FAIL lines), F225 (+x on mod installer: guard refuses, developer's). Run 2 started for the stamp.

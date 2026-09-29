# Plan — 035

1. Tests first: C46-C53 in `scripts/test-project-maintenance.sh` for SC-035-01..08. Confirm the red arms (C48, C49, C52) fail on HEAD.
2. Section 6d in `scripts/project-maintenance.sh`: per-config narrow-viewport check, .NET fallback, marker exemption (FR-01..07).
3. `.claude/docs/testing.md`: Viewports subsection (shared config project, .NET fixture parameter, overflow assertion); retire the per-test `SetViewportSizeAsync` example.
4. `.claude/docs/spec-testing-checklist.md`: cross-cutting line.
5. Verify: maintenance self-test, `test-skill-reachable.sh`, `validate-portability.sh` on the changed script, and a real pass against fundit/agentcrm copies.

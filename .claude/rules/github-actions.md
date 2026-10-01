# GitHub Actions rule (CI minimalism — budget protection)

Actions minutes come from one shared 3000-min/month free tier. iskvalp burned it in four days with 17 workflows that re-ran checks already done locally. Long form (the incident, caching YAML, mobile, the full pre-081 text): `.claude/docs/github-actions-rationale.md`. Read it before creating or editing anything under `.github/workflows/`.

## The contract (BLOCKING)

A solo project's `.github/workflows/` holds **at most two workflows**: `deploy-[projectname].yml` (`workflow_dispatch` only, with the `confirm_deploy: "deploy"` input, never on push), and at most one minimal validation workflow for a check that genuinely cannot run locally. Before creating any file there, count what exists. If it is not the deploy workflow, ask with `AskUserQuestion` and name this rule. Report an existing sprawl as an inventory; delete nothing silently. "Add a CI gate" means a local script, a hook, or a step in the deploy gate.

Recurring work runs through `scripts/maintenance-due.sh`, not a scheduler (`install-nightly-maintenance.sh --if-due` is opt-in).

**Hygiene for allowed workflows:** `workflow_dispatch` + `confirm_deploy`, `concurrency` with `cancel-in-progress`, `timeout-minutes` on every job, well-known actions only. **Caching is blocking:** setup-dotnet/setup-node caches with lock files, docker `cache-from/to: type=gha`, restore before copying source.

Team + PRs: one push/PR build + unit-test workflow with `paths` filters is fine. Mobile: EAS Workflows or one `workflow_dispatch` build.

## Forbidden as workflows

CodeQL, secret scanning, Stryker, a11y/Lighthouse, per-spec workflows, actionlint, matrix builds, **any `schedule:` trigger**, push-triggered tests or builds, store builds on push.

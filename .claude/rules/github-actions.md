# GitHub Actions rule (CI minimalism — budget protection)

Actions minutes are one shared 3000-min/month tier; iskvalp burned it in four days with 17 workflows. Long form (the incident, caching YAML, mobile, the full pre-081 and pre-099 text): `.claude/docs/github-actions-rationale.md`. Read it before creating or editing anything under `.github/workflows/`.

## The contract (BLOCKING)

A solo project's `.github/workflows/` holds **at most two workflows**: `deploy-[projectname].yml` (`workflow_dispatch` only, with a `confirm_deploy: "deploy"` input, never on push), and at most one minimal validation workflow for a check that cannot run locally. Count what exists before creating any file there; for anything but the deploy workflow, ask with `AskUserQuestion` and name this rule. Report existing sprawl as an inventory; delete nothing silently. "Add a CI gate" means a local script, a hook, or a step in the deploy gate. Recurring work runs through `scripts/maintenance-due.sh`, not a scheduler.

**Allowed workflows:** `concurrency` with `cancel-in-progress`, `timeout-minutes` on every job, well-known actions only, and **caching (blocking):** setup-dotnet/setup-node caches with lock files, docker `cache-from/to: type=gha`, restore before copying source. Team + PRs: one push/PR build + unit-test workflow with `paths` filters. Mobile: EAS Workflows or one `workflow_dispatch` build.

## Forbidden as workflows

CodeQL, secret scanning, Stryker, a11y/Lighthouse, per-spec workflows, actionlint, matrix builds, **any `schedule:` trigger**, push-triggered tests or builds, store builds on push.

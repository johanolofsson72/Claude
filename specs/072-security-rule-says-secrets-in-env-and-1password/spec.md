# 072 — security-rule-says-secrets-in-env-and-1password

Track: spec-only. A documentation fix across the template's secrets guidance plus a template-only
guard test. No entity, no state machine, no new external surface. No hardening trigger: the spec
changes advice about secrets, not a code path that handles them.

Evidence: teach F061 (spec 014 deploy-hardening, 2026-09-28). ekofak's `.env.example` and
`deploy/RUNBOOK.md` for the 1Password practice already in use. Diagnosis in `specs/INDEX.pending.md`.

## The defect

Five places tell a project where secrets live, and all five steer it toward the weaker shape:

| File | Says |
|---|---|
| `.claude/rules/security.md` | "use appsettings.json (local) or environment variables (production)" |
| `.claude/docs/security.md` | the same sentence |
| `.claude/skills/deploy-checklist/SKILL.md` | "No secrets in appsettings.json (only in environment variables)" |
| `.claude/docs/deployment.md` § Environment variables and secrets | GitHub Secrets + appsettings.Production.json, no runtime secret store |
| `.claude/skills/project-wizard/SKILL.md` Q39 | offers "Environment variables in `appsettings.Production.json`" |

Environment variables are readable by anyone with Docker API access (`docker service inspect`,
`docker inspect` print `Env`), they are inherited by every child process, and they end up in crash
dumps and diagnostics. teach spec 014 moved every production secret to Swarm secrets mounted as files
and refused a secret-class key from any other source. `appsettings.json (local)` is also wrong on
its own terms: that file is committed.

The fleet already keeps the real values in a shared 1Password vault (ekofak: `op run` / `op inject`
locally, `op://` references committed), but the template never says so. A new project gets no pointer
to the vault and invents its own `.env` habit.

## Requirements

- **FR-01** Production: secrets come from the orchestrator's secret store mounted as files (Swarm
  secrets at `/run/secrets`, Kubernetes secrets) or a vault. .NET reads them with
  `Microsoft.Extensions.Configuration.KeyPerFile`. The reason is stated (inspect shows env).
- **FR-02** Environment variables are the fallback only where the platform offers nothing else. A
  secret is never baked into an image: no `ENV`/`ARG` secret in a Dockerfile; build-time secrets use
  `RUN --mount=type=secret`.
- **FR-03** 1Password is the source of truth for real values. Locally: `op run --env-file=.env.op`
  (or `dotnet user-secrets` for a .NET-only value), with `op://` references committed and no value in
  any committed file. For production: the Swarm secret is created from the vault through a pipe
  (`op read … | docker secret create <name> -`) so the value never touches disk or shell history.
- **FR-04** Committed config (`appsettings.json`, `appsettings.Production.json`, `.env.example`)
  holds placeholders only.
- **FR-05** Rotation: Swarm secrets are immutable, so rotation is a new versioned name plus a stack
  update. The doc says so in one line.
- **FR-06** All five places agree: the rule and the checklist are one line each and point at
  `docs/security.md § Secrets` for the pattern; the wizard's Q39 offers the new default.
- **FR-07** A template-only guard fails when any template doc says production secrets go in
  environment variables, or puts secrets in `appsettings.json`.

## Acceptance

- AC1 The guard is red against HEAD's docs (names all five files), green after the fix.
- AC2 Sabotage: the pre-072 rule line fed to the guard is caught; the new wording is not flagged.
- AC3 `docs/security.md § Secrets` carries a runnable local command, the pipe into
  `docker secret create`, a stack-file `secrets:` example, and the KeyPerFile line.
- AC4 `template-autosync.sh --unlisted` stays silent (guard listed in TEMPLATE_ONLY_SCRIPTS).

## Non-goals

A 1Password Connect server or service-account token at runtime (it moves the secret-zero problem into
the container). Changing GitHub Secrets for CI credentials (`LIVE4_SSH_KEY` stays). Any code or hook.

## Clarifications

### Session 2026-09-30

- Q: What role does 1Password play — local only, source of truth, or runtime? → A: Source of truth
  for every real value, resolved locally with `op run` and piped into `docker secret create` for
  production. Not a runtime dependency (non-goal above).
- Q: Does the deploy workflow keep using GitHub Secrets? → A: For CI credentials, yes. A runtime
  secret the workflow must set goes into a Swarm secret, not into the service's `environment:`.
- Q: Ship the guard to projects? → A: No. It checks the template's docs, like 071's guard.

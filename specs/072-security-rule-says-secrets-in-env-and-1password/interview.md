# Spec interview — 072-security-rule-says-secrets-in-env-and-1password

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. Spec-only, no hardening trigger (documentation and one template-only self-test; no code
path that handles a secret changes), so no overflow.

## Q1 — Scope boundary
**Q:** What is in, what is out?
**A (auto):** In: the five places that give secrets advice (rules/security.md, docs/security.md, deploy-checklist, deployment.md, project-wizard Q39) and a guard test. Out: deployment-mobile.md (EAS secrets are already right), any hook, runtime 1Password integration.

## Q2 — Primary actor
**Q:** Who is hurt today?
**A (auto):** An agent building the first production deploy of a new project. It follows the rule and puts the DB password in the service's `environment:`, where `docker service inspect` prints it.

## Q3 — Happy path
**Q:** What does done look like?
**A (auto):** A reader of docs/security.md § Secrets can put a secret in 1Password, run the app locally with `op run`, create the Swarm secret with one pipe, mount it in the stack file, and read it with KeyPerFile — without writing the value to a file.

## Q4 — Is the claim true?
**Q:** Do `docker service inspect` / `docker inspect` really show environment variables?
**A (auto):** Yes. `Spec.TaskTemplate.ContainerSpec.Env` and `Config.Env` list them in plain text; Swarm secrets appear only as a name and a target file.

## Q5 — Role of 1Password
**Q:** Local only, source of truth, or runtime?
**A (auto):** Source of truth for real values, used locally and at secret-creation time. Runtime use (Connect server, service-account token) moves the secret-zero problem into the container; out of scope.

## Q6 — Local development
**Q:** What replaces "appsettings.json (local)"?
**A (auto):** `op run --env-file=.env.op -- <cmd>` with a committed `.env.op` of `op://` references (ekofak's pattern). `dotnet user-secrets` stays acceptable for a .NET-only value that does not need sharing. Env vars are fine locally: the inspect exposure is a production problem.

## Q7 — Creating the production secret
**Q:** How does the value get from 1Password into Swarm?
**A (auto):** `op read "op://<vault>/<item>/<field>" | docker secret create <name> -` on the manager, or via ssh. stdin, so nothing lands on disk or in shell history.

## Q8 — Reading the secret in .NET
**Q:** Which mechanism does the app use?
**A (auto):** `builder.Configuration.AddKeyPerFile("/run/secrets", optional: true)`, added last. The file name is the key; `__` maps to `:`. teach R3 uses exactly this.

## Q9 — Non-.NET containers
**Q:** What about postgres, grafana, redis?
**A (auto):** Use the image's `*_FILE` convention (`POSTGRES_PASSWORD_FILE=/run/secrets/...`). One line in the doc.

## Q10 — When env vars are still allowed
**Q:** Is an environment variable ever acceptable in production?
**A (auto):** Only where the platform has no file-mounted store. The doc says fallback, not forbidden, so a project on such a platform is not blocked.

## Q11 — Images
**Q:** What about build time?
**A (auto):** Never `ENV` or `ARG` a secret (`docker history` shows both). Build-time secrets use `RUN --mount=type=secret`.

## Q12 — Rotation
**Q:** How is a Swarm secret rotated?
**A (auto):** Secrets are immutable. Create `<name>_v2`, point the stack's `secrets:` at it, `docker stack deploy`, remove the old one. One line.

## Q13 — GitHub Secrets
**Q:** Does this retire GitHub Secrets?
**A (auto):** No. They still hold CI credentials (`LIVE4_SSH_KEY`). The change: a runtime value the workflow sets goes into a Swarm secret, not the service `environment:`.

## Q14 — Committed config
**Q:** What may committed config contain?
**A (auto):** Placeholders only. `appsettings*.json` and `.env.example` document the key, never the value.

## Q15 — Wizard default
**Q:** What does project-wizard Q39 recommend?
**A (auto):** "1Password vault → Swarm secrets (files) ★". GitHub Secrets stays as the CI-credential option, cloud key vaults stay as an option, the appsettings.Production.json option is removed.

## Q16 — Regression guard
**Q:** How does the fix stay fixed?
**A (auto):** A template-only script scanning docs/rules/skills/CLAUDE.md for "environment variables (production)"-shaped advice and for secrets placed in appsettings.json. Red at HEAD first.

## Q17 — False positives
**Q:** What must the guard allow?
**A (auto):** The new wording ("fallback", "never in appsettings"), and prose that talks about env vars without prescribing them for secrets. Sabotage + allow arms in the test.

## Q18 — Reversibility
**Q:** Rollback story?
**A (auto):** A doc revert. Nothing migrates; projects get the change by sync and can revert the same way.

## Q19 — Acceptance
**Q:** Measurable done?
**A (auto):** AC1–AC4 in spec.md: guard red→green, sabotage caught, § Secrets carries the four commands, `--unlisted` silent.

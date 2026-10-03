# Security

## Fundamental rules

- ALWAYS use parameterized queries — never string concatenation for SQL.
- Sanitize all user input (XSS protection).
- Configure HTTPS, CSRF protection, and CORS correctly.
- Secrets never go in code or committed config. The real value lives in 1Password. Production reads it from a secret file (see § Secrets).
- Never commit `.env`, `appsettings.Development.json`, or similar.
- All API endpoints require authentication unless otherwise specified.
- Never use `eval()` or `extract()` — neither in PHP nor JavaScript.

## Secrets

The team's 1Password vault holds every real value. Code, committed config and images never do.
`appsettings*.json` and `.env.example` name the key with an empty placeholder.

**Why not environment variables in production.** `docker service inspect` and `docker inspect`
print a service's environment in plain text to anyone with Docker API access. Child processes
inherit it, and it shows up in crash dumps and diagnostics pages. A Swarm secret shows up as a name
and a file path only. teach spec 014 moved every production secret to secret files for this reason.
Environment variables are the fallback only on a platform with no file-mounted secret store.

**Locally.** Commit a `.env.op` that holds `op://` references (a reference is not a secret) and let
1Password resolve them into the process without writing a file:

```bash
# .env.op (committed)
ConnectionStrings__Default=op://<vault>/<project>-db/connection-string
Stripe__ApiKey=op://<vault>/<project>-stripe/api-key

op run --env-file=.env.op -- dotnet run --project src/<Project>
op run --env-file=.env.op -- docker compose up
```

`dotnet user-secrets` also works for a .NET-only value that nobody else needs. Locally, environment
variables are fine: `docker inspect` exposure is a production problem.

**Production (Docker Swarm).** Pipe the value from 1Password straight into a Swarm secret on the
manager. It goes through stdin, so it never lands on disk or in shell history:

```bash
op read "op://<vault>/<project>-db/connection-string" | ssh live4-mgr-01 docker secret create <project>_db_connection -
```

Mount it in the stack file. The `target` becomes the file name, and the configuration provider maps
`__` to `:`:

```yaml
services:
  app:
    secrets:
      - source: <project>_db_connection
        target: ConnectionStrings__Default
secrets:
  <project>_db_connection:
    external: true
```

Read it in .NET with KeyPerFile. It ships in the ASP.NET Core shared framework, so there is no
package to add. Add it last so it wins over everything else:

```csharp
builder.Configuration.AddKeyPerFile("/run/secrets", optional: true);
```

Third-party images use their `*_FILE` convention, for example
`POSTGRES_PASSWORD_FILE=/run/secrets/<project>_pg_password`.

- **Images:** never put a secret in `ENV` or `ARG`, because `docker history` shows both. A build-time
  secret uses `RUN --mount=type=secret,id=<name>`.
- **Rotation:** Swarm secrets are immutable. Create `<name>_v2`, point the stack's `secrets:` at it,
  run `docker stack deploy`, then `docker secret rm` the old one.
- **CI:** GitHub Secrets still hold CI credentials (`LIVE4_SSH_KEY`). A runtime value the deploy
  workflow has to set goes into a Swarm secret, not into the service's `environment:`.

## Claude Code permissions.deny and the hooks behind it

`permissions.deny` in `.claude/settings.json` is the first layer, and it is not enough on its own. It has known enforcement bugs (GitHub issues #6699, #6631, #27040), and a Bash rule matches the command text by prefix. `Bash(rm -rf *)` does not match `rm -r -f x`, `/bin/rm -rf x` or `command rm -rf x`, and `Bash(git push --force*)` does not match `git push -f`. This template runs with `defaultMode: bypassPermissions` and `allow: Bash`, so every other spelling runs (spec 083, F038).

Two PreToolUse hooks sit behind the list and deny with `hookSpecificOutput.permissionDecision: "deny"`:

- `scripts/sensitive-file-guard-hook.sh` keeps credential paths out of Read, Edit, Write, MultiEdit, NotebookEdit, Grep, Glob and Bash. That covers anything under `.ssh`, `.aws`, `.azure`, `.kube` or `.gnupg`, the Docker and `gh` configs, `.git-credentials`, `.netrc`, `.npmrc`, `.env` and `.env.<suffix>`. `.env.example`, `.env.sample` and `.env.template` hold empty placeholders and are allowed. It replaced an inline hook that only covered Read, Edit and Write.
- `scripts/destructive-command-guard-hook.sh` splits a Bash command the way the shell does and denies the deny list's commands in any spelling: a recursive forced `rm`, `sudo`, a force push (`+refspec` and `--force-with-lease` included), a push that deletes or mirrors remote refs (`--delete`, `-d`, `origin :main`, `--prune`, `--mirror`, and a `remote.<name>.mirror` or `remote.<name>.push` setting that makes a plain `git push` do the same), `git reset --hard`, `git clean -f`, and `find -delete` or `find -exec rm`.

Both have limits, written in the hook headers. They see what a command names, not what it computes. A variable, an alias, a script that deletes, `eval "$x"` or `python -c "shutil.rmtree(...)"` gets through, and `grep -r` over a directory reads a `.env` it never names. They stop a careless or injected command; they are not a sandbox against a program written to get around them. Neither has an override. If the operation is really needed, the developer runs it with `!`.

The guards that take a path judge the file the write lands on. Before spec 090 they judged the spelling in the payload. On macOS and Windows the canonical path uses the name the file system stores, so `SCRIPTS/x.sh` and `scripts/x.sh` get the same verdict. A symlink anywhere in the path is followed, and on NTFS `App.cs.` counts as `App.cs`. The `scripts/guard-lib.sh` header lists what is still open: a hard link that already exists, and a name that does not exist yet.

A third guard keeps the hook wiring itself out of reach. `scripts/settings-edit-guard-hook.sh` (spec 089) refuses an agent change to `hooks`, `disableAllHooks` or `env` in `.claude/settings.json`, `.claude/settings.local.json` and `~/.claude/settings.json` (or `$CLAUDE_CONFIG_DIR/settings.json`). An Edit or Write is judged on the JSON it would leave behind, so a permissions entry or a re-indent passes, and a removed hook or `SPEC_ACCEPTANCE=off` does not. In the shell, a command that names one of the three files passes only when it reads it. There is no override and no template exemption: the developer makes those changes by hand or with `!`. It has the same limit as the other two. A script that writes the file without naming it on the command line gets through, and so does `sync-core-hooks.py` when it wires a project.

The same guard keeps mods out of reach (spec 095a). A mod is a plugin folder whose `hooks/hooks.json` names a module of function hooks. Once one is loaded, a hook on `tool.call` that answers allow skips every settings hook, this guard included, and the module can rewrite settings itself. So no agent tool may write a mod path. That means anything in a folder holding `.claude-plugin` or `hooks/hooks.json`, wherever it is on disk (developer decision M1), and anything under `~/.claude/plugins`, `~/.claude/dev-mods` or a folder on `CLAUDE_CODE_PLUGIN_DIRS`. It also covers each skill folder in `~/.claude/skills`, because Claude Code 2.1.288 loads a plugin from there without asking, and every skill's `hooks/` folder. A project's own `.claude/skills` stays editable; only a verb that drops a whole folder in (`cp`, `mv`, `ln`, `tar`, `git clone`) is refused there. Git verbs are judged by what they would write, as for settings (M3). `claude plugin install`, `--plugin-dir`, `--plugin-url` and `--settings` count as writes; `claude plugin list` and `validate` do not. Reads stay open. A mod the developer wants is staged under a name that does not load and installed by a script they run with `!` (row 096). The bounds are in the hook header; the largest is a plugin-shaped folder staged outside every root and loaded later by the developer's own command.

Spec 091 closed the places where a trust decision still rested on state the agent could write:

- **Which repository is the template.** The CORE guards exempt the template, and autosync skips it. Both used to decide by origin's URL, which `git remote set-url` changes. `scripts/template-identity.sh` now also requires that HEAD's history starts at the template's first commit, read with replace refs and grafts turned off. A project whose origin points at the template is treated as a project, and autosync on one writes nothing and warns.
- **Remotes, upstreams and remote-tracking refs.** `scripts/trust-anchor-guard-hook.sh` denies `git remote add|set-url|rename|remove`, `git config` writes under `remote.*`, `url.*` (insteadOf), `branch.*`, `include*` and `alias.*`, `git update-ref`, `git symbolic-ref` with a target, and a fetch or push refspec that writes `refs/remotes/`. The developer runs those with `!`.
- **The template updater's model.** `scripts/update-template.sh` starts `claude -p` with `--restricted`, `--permission-mode dontAsk` and `--tools`, so it cannot write outside the repository. It refuses to start on a `claude` without `--restricted`. A skill, agent or command that gains `hooks:` (or `allowed-tools`, `permissionMode`, `mcpServers`) in its frontmatter, or a new script under those directories, is named `[REVIEW]` and the run exits 4.
- **What the nightly runs.** The trusted suite identity includes a blob hash of every file the suite command reaches, so an edited or new test file un-trusts it. A command that reaches files through `$`, a backtick or `..` is never trusted.
- **Cloud stamps.** A stamp pulled from `claude/maintenance-results` counts only for a job placed in the cloud on this machine. `secrets` is always local. The agent cannot edit `.claude/workload-placement.tsv`.
- **Acceptance confirmations.** Only a click on `Confirm`, given to a question that showed every case in full (`acceptance-cases.sh --question`), binds the digest. A committed Confirmed line is trusted without a recorded answer only once it is on the upstream, not because it is at HEAD.

The residuals are in `specs/091-trust-residuals/spec.md` under Threat model.

If you add a deny rule for a security-critical file or command, extend one of these two hooks as well and add the case to its test (`scripts/test-sensitive-file-guard.sh`, `scripts/test-destructive-command-guard.sh`).

**March 2026 fix:** A bug where PreToolUse hooks returning "allow" could bypass deny rules (including enterprise managed settings) has been fixed. The hooks above are still the reliable layer.

## Subprocess credentials

Set `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1` in your environment to automatically strip Anthropic and cloud provider credentials from subprocess environments. Prevents API keys and tokens from leaking to child processes.

## Dependencies and supply chain

Third-party packages are the largest attack surface a project has, and most of it arrives transitively.
See `.claude/docs/supply-chain.md` for the defaults: npm 12's install-script approvals, release-age
cooldowns, NuGet audit as a build error, lockfile-only installs, SHA-pinned actions, and osv-scanner.
`bash scripts/project-freshness.sh` runs the scans locally (trufflehog, a key-shape scan, npm audit,
osv-scanner, `dotnet list package --vulnerable`). trufflehog reports only credentials a provider can
verify. A Data Protection key ring, a `.pfx` or a private key matches no provider, so the key-shape
pass looks for them by name and content across all of git history. Silence a harmless fixture with a
`<path-glob>  # <reason>` line in `.secret-shapes-allow`, and the reason is required.

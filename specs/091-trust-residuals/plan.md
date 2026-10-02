# Plan — 091 trust residuals

## Approach

One requirement per code path, tests first, each test reproducing the Problem-table row before the
fix. No new runtime dependency: bash 3.2, git, python3 where the code already uses it.

| R | Files | Shape of the change |
|---|---|---|
| R1 | new `scripts/template-identity.sh`; core-machinery-guard, core-owed-tick-guard, template-autosync.sh, template-autosync-hook.sh | `template_identity DIR` → template/impostor/project; anchored `case` on the URL, then `GIT_GRAFT_FILE=<missing> git --no-replace-objects rev-list --max-parents=0 HEAD`. Callers source it with `2>/dev/null` and treat a missing lib as `project`. `refresh_local_template` keeps a URL-only check via `template_url_matches`. |
| R2 | trust-anchor-guard-hook.sh (+ its python verdict) | Trigger words `remote`, `insteadof`, `pushurl`, `update-ref`, `refs/remotes`; the parser walks words after `git` (skipping `-C x`, `-c k=v`, `--git-dir=…`, `--work-tree=…`) and denies `remote add|set-url|rename|remove|rm`, `config` writes to the four keys, `update-ref`, and `fetch`/`push` refspecs whose destination starts `refs/remotes/`. |
| R3 | template-autosync.sh | `pin_on_main PIN [CLONE]`: clone ancestry first, else curl the compare API to a temp file and read it with python3. Called before `resolve_local_template` accepts a clone and before `resolve_remote_template` downloads. |
| R4 | template-autosync.sh | `flagged_paths CLONE` from `git ls-files -v`; merged into `EOL_DIVERGED` before `stage_committed_bytes`; skills list from `git ls-files` when the template is a work tree. |
| R5 | update-template.sh | help probe; `--restricted --permission-mode dontAsk --tools`; `.mcp.json` denies; post-run frontmatter scan over `git status --porcelain` + untracked under .claude/skills and .claude/agents. |
| R6 | project-maintenance.sh | `suite_files TEXT` → sorted path list; `suite_identity` appends `git hash-object --stdin-paths` output paired with paths. |
| R7 | workload-placement.sh, cloud-maintenance.sh, trust-anchor-guard-hook.sh | secrets hard-local; pull asks `--place` per stamp; guard path rule for `.claude/workload-placement.tsv`. |
| R8 | acceptance_cases.py, acceptance-cases.sh | `record_answers` binds a digest only for Confirm + every case title; `--question`. |
| R9 | acceptance_cases.py | `_committed_unchanged` reads `@{upstream}:./acceptance.md`. |
| R10 | template-autosync.sh CORE_SCRIPTS; docs | names + prose. |

## Tests

- new `scripts/test-template-identity.sh`: R1, 091-AC-1, sabotage arm (URL-only identity fails it).
- `test-trust-anchor-guard.sh`: R2 + R7 guard arms, 091-AC-1 set-url.
- `test-template-autosync-supply-chain.sh`: R3, R4, 091-AC-2 (curl shim answers the compare URL).
- `test-update-template.sh`: R5, 091-AC-3.
- `test-maintenance-trust.sh`, `test-workload-placement.sh`, cloud pull arms: R6, R7, 091-AC-4.
- `test-acceptance-cases.sh`, `test-developer-answers.sh`: R8, R9, 091-AC-5.

## Verification

Full template suite, mutation gate on template-identity.sh / acceptance_cases.py / the changed
autosync functions, /tla on the confirm binding (R8+R9), adversarial review, /security-review.

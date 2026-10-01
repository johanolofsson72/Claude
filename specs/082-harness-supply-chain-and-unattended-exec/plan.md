# Plan — 082 harness supply chain and unattended execution

Shell and Python only, bash 3.2-safe, no new dependencies. Every change fails toward *not doing the
dangerous thing*: not syncing, not running, not removing, not sending.

## Changes by file

| File | Requirement | Change |
|---|---|---|
| `scripts/template-autosync.sh` | R1 R2 R3 R4 | `resolve_remote_template` downloads `codeload…/tar.gz/<40-hex>`; `CLAUDE_TEMPLATE_PIN` validated and honoured in local + remote resolution; dirty clone refused unless `--force`/`CLAUDE_TEMPLATE_ALLOW_DIRTY=1`; `copy_file` skips a symlink source |
| `scripts/project-maintenance.sh` | R5 R7 | `--unattended`, `--trust`; trust store `.git/claude-trusted-commands`; suite + mutation gated on hash when unattended; every `stryker_guard.py` call through `guard_bounded` (timeout/gtimeout, `MAINTENANCE_GUARD_TIMEOUT`, default 60) |
| `scripts/install-nightly-maintenance.sh` | R6 | `--unattended` in cron, schtasks and `/loop` lines; STALE report for a line without it |
| `scripts/stryker_guard.py` | R7 R8 | `glob_rx` replaced by a tokenised NFA matcher (O(glob × path)); `safe()` for every path/detail in `sweep_note` |
| `scripts/lane-catchup.sh` | R9 | credential-store denies kept; backup `settings.json.bak-<UTC stamp>`; temp file + `os.replace`, mode preserved |
| `scripts/prune-agent-worktrees.sh` | R10 | reachability by worktree HEAD SHA; untracked outside agent-memory keeps; any git failure keeps |
| `scripts/maintenance_ledger.py` | R11 | `--all` runs this repo's `register-convergence.sh --dir <sibling>`; append uses `O_NOFOLLOW` and a realpath containment check |
| `scripts/update-template.sh` | R12 | `--disallowedTools`, mktemp log, dirty-tree refusal, closing `git diff --stat` |
| `scripts/local-llm-detect.sh`, `quality_gates.py`, `register-similarity.sh` | R13 | one loopback predicate per language; `LOCAL_LLM_ALLOW_REMOTE=1` opt-in |
| `scripts/local-llm-*-hook.sh` (38) | R14 | additionalContext prefixed with the untrusted label (mechanical edit, asserted by a test over every hook) |
| `scripts/sync-prompt.md`, `.claude/skills/tla/SKILL.md` | R15 | tla2tools v1.7.4 + SHA-256 check; seven skill clones checked out at pinned SHAs |
| docs | R16 | `template-autosync.md`, `local-llm.md`, maintenance docs, `template-sync-verify.sh` header |

## Tests (one file per boundary; names cite `082-AC-<n>` and `R<n>`)

- `scripts/test-template-autosync-supply-chain.sh` — R1–R4, 082-AC-1 (fixture template clone + fake `curl`/`git ls-remote` on PATH, sandboxed with `CLAUDE_TEMPLATE_SYNC_SANDBOX`)
- `scripts/test-maintenance-trust.sh` — R5, R7 timeout arm, 082-AC-2
- `scripts/test-install-nightly-maintenance.sh` — R6 (extend)
- `scripts/test-stryker-guard.sh` — R7 matcher equivalence + pathological glob < 2 s, R8 (extend)
- `scripts/test-lane-catchup.sh` — R9, 082-AC-3 (fake `$HOME`)
- `scripts/test-prune-agent-worktrees.sh` — R10, 082-AC-4
- `scripts/test-maintenance-ledger.sh` — R11 (extend)
- `scripts/test-update-template.sh` — R12 (fake `claude` on PATH records argv; template-only)
- `scripts/test-local-llm-host.sh` — R13, R14, R15 static checks, 082-AC-5

New test scripts go into `CORE_SCRIPTS` (`test-update-template.sh` into `TEMPLATE_ONLY_SCRIPTS`, beside the script it tests).

## Order

Tests first per area (acceptance gate step 2), then code, then docs, then the suite.

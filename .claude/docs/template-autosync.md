# Template auto-sync (no more manual `/project-update` for the mechanical half)

`/project-update` does two different jobs. One needs a brain — merging `CLAUDE.md` prose, resolving project-specific hooks in `settings.json`, deciding the tech stack. The other is pure mechanics — copy the current `scripts/`, `.claude/rules/`, `.claude/docs/`, `.claude/agents/` from the template and re-run the hook wiring. The mechanical half is ~90% of what actually drifts, and it needs no judgment at all.

Auto-sync automates exactly that half, on a SessionStart hook. The judgment half still waits for a deliberate `/project-update`.

## The two pieces

| File | Role |
|---|---|
| `scripts/template-autosync.sh` | The worker. Deterministic file sync + `sync-core-hooks.py` rewiring + commit. Runnable by hand. |
| `scripts/template-autosync-hook.sh` | SessionStart wrapper. Rate-limits, runs the worker, reports the result as a `systemMessage`. Fails open. |

Wiring (already in the template's `settings.json`, so `sync-core-hooks.py` propagates it):

```json
{ "matcher": "startup|resume",
  "hooks": [{ "type": "command",
              "command": "bash \"$CLAUDE_PROJECT_DIR/scripts/template-autosync-hook.sh\"",
              "statusMessage": "Checking template freshness...",
              "timeout": 130 }] }
```

`startup|resume` only — not `compact` or `clear`, which fire mid-work where a config change under your feet is the last thing you want.

## What it will and will not touch

**Synced:** `scripts/*.sh`, `scripts/*.py`, `.claude/rules/*.md`, `.claude/docs/*.md`, `.claude/agents/*.md`, plus core-hook wiring inside `.claude/settings.json` via `sync-core-hooks.py`.

**Never touched:** `CLAUDE.md`, the project's own hooks and permissions in `settings.json`, `specs/`, `CLAUDE.local.md`, and any source code. Nothing is ever deleted.

**Two policies decide each file:**

1. **Update-existing-only.** A rule or doc the project doesn't have is not added — a `.NET` project deleted `wordpress.md` on purpose and must not get it back. The exception is the **CORE set** (the enforcement spine: pipeline/register/interview guards, the reminder emitters, the sync helpers, the pipeline rules), which is always installed and always overwritten. Core drift is what silently disables a gate.

2. **The manifest.** Every sync writes `<sha256>  <path>` for each file into `.claude/.template-sync`. Next run, a file is only overwritten when its hash still matches the manifest — proof nobody edited it locally. A locally-modified file is skipped and reported, never clobbered.

**First run has no manifest**, so a differing file is ambiguous: older template copy, or your customization? The worker resolves it against the template's own git history — if the project's exact bytes ever were a template version, it's stale and gets updated ("adopt"); otherwise it's yours and gets skipped. History lookup needs a local template clone; over the tarball path it degrades to the safe answer (skip + report).

**Stack gate.** `.claude/.sync-stack` with `testing=mobile` means `.claude/docs/testing.md` holds *mobile* content under the canonical name. The sync maps `testing-mobile.md → testing.md` and never stamps the browser version over it — that's the documented failure that left a native app reading "browser back mid-flow" instructions.

## Cost

Rate-limited to one check per 6 hours per project (`TEMPLATE_AUTOSYNC_INTERVAL`, mtime of `.claude/.template-sync-check`). With a local template clone the check is a local `git rev-parse` — no network. Without one it's a single `git ls-remote`, and the tarball downloads only when the SHA actually moved.

## Running it by hand

```bash
scripts/template-autosync.sh --check      # what drifted, no writes
scripts/template-autosync.sh --dry-run    # same, with the file list
scripts/template-autosync.sh              # sync + commit + push
scripts/template-autosync.sh --no-commit  # sync, leave it unstaged
scripts/template-autosync.sh --force      # ignore the "already at this SHA" stamp
```

Environment: `CLAUDE_TEMPLATE_AUTOSYNC=0` disables it for a project · `CLAUDE_TEMPLATE_DIR` points at a local template clone · `CLAUDE_TEMPLATE_AUTOSYNC_ALWAYS=1` bypasses the rate limit.

## Commits

The sync commits only the paths it wrote, with `chore(sync): template <sha> — N updated, M added`, then pushes if an upstream exists. It refuses to commit during a rebase/merge/cherry-pick and leaves the files staged instead. It never runs `git add -A`, so unrelated work in the tree is not swept in.

## When you still need `/project-update`

- The summary lists skipped, locally-modified files.
- `CLAUDE.md` needs the template's new critical rules merged in.
- The tech stack changed, or speckit itself needs reinstalling.
- A new external skill bundle shipped in the template.

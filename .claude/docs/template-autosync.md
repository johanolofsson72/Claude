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

**Three policies decide each file:**

1. **Update-existing-only.** A rule or doc the project doesn't have is not added — a `.NET` project deleted `wordpress.md` on purpose and must not get it back. The exception is the **CORE set** (the enforcement spine: pipeline/register/interview guards, the reminder emitters, the sync helpers, the pipeline rules), which is always installed and always overwritten. Core drift is what silently disables a gate.

2. **The manifest.** Every sync writes `<sha256>  <path>` for each file into `.claude/.template-sync`. Next run, a file is only overwritten when its hash still matches the manifest — proof nobody edited it locally. A locally-modified file is skipped and reported, never clobbered.

**First run has no manifest**, so a differing file is ambiguous: older template copy, or your customization? The worker resolves it against the template's own git history — if the project's exact bytes ever were a template version, it's stale and gets updated ("adopt"); otherwise it's yours and gets skipped. History lookup needs a local template clone; over the tarball path it degrades to the safe answer (skip + report).

3. **The intentional-difference record** (`.claude/.sync-local`). Some files are *supposed* to differ forever — a project's `.claude/docs/testing.md` ends up naming its own gate script and its own solution files, none of which exist in a template-generated project. Reporting those on every run is a permanent false alarm, and a permanent false alarm is worse than none: it is the one line in this output a reader learns to skip, and the next genuinely-stale file gets reported on that same line. So a difference can be *accepted*:

```bash
scripts/template-autosync.sh --accept-local .claude/docs/testing.md
```

which writes one line — `<project-sha256>  <template-sha256>  <path>` — and nothing else. No sync, no commit, no push; you commit the record alongside whatever made the difference intentional.

**Two hashes, not one.** A record keyed on the project's bytes alone goes silent and then *stays* silent when the template rewrites that file — the same defect pointed upstream. With both:

| project side | template side | what happens |
|---|---|---|
| as accepted | as accepted | silent — no summary line, no `[manual]` entry |
| changed | — | reported: *the local copy changed since it was accepted* |
| as accepted | changed | reported: *the template changed under an accepted local difference* |
| no record | — | reported: differs — merge it, or record it |

That is what stops the record becoming a blindfold. `--check` / `--dry-run` still list accepted differences (and flag records that have gone stale) — silent means silent in the ambient path, not invisible to inspection.

`--accept-local` refuses a path that is missing, that the template does not ship, that is already identical, that it cannot see the template for, or that is in the **CORE set** — CORE files are overwritten unconditionally, so recording one would promise silence *and* let the file be clobbered on the next run. It is also the only thing that ever writes the record: a sync that recorded its own skips would be a rubber stamp, and the failure that causes — a genuinely stale file going quiet — is invisible.

**Stack gate.** `.claude/.sync-stack` with `testing=mobile` means `.claude/docs/testing.md` holds *mobile* content under the canonical name. The sync maps `testing-mobile.md → testing.md` and never stamps the browser version over it — that's the documented failure that left a native app reading "browser back mid-flow" instructions.

## Cost

Rate-limited to one check per 6 hours per project (`TEMPLATE_AUTOSYNC_INTERVAL`, mtime of `.claude/.template-sync-check`). With a local template clone the check is a local `git rev-parse` — no network. Without one it's a single `git ls-remote`, and the tarball downloads only when the SHA actually moved.

## Three outcomes, not one silence

The hook fails open — every path exits 0, because a template sync problem must never stop a session from
starting. Failing open is not the same as failing indistinguishably, though, and until H6t it was: a sync
that completed, a sync killed at the 120 s bound, and a sync that failed for any other reason all exited 0
without saying anything, and the rate-limit marker was refreshed *before* the sync ran. A sync that always
exceeded the bound therefore bought itself six hours of quiet, then bought six more, and template updates
stopped arriving with nothing to indicate it.

| Outcome | What you see | What the marker records |
|---|---|---|
| **completed** | the summary of what moved (silent if nothing moved) | `ok` — next check in `TEMPLATE_AUTOSYNC_INTERVAL` (6 h) |
| **timed out** | one line naming the timeout and the retry | `timeout` — next check in `TEMPLATE_AUTOSYNC_TIMEOUT_BACKOFF` (30 min) |
| **other failure** | nothing | `ok` — this hook names the timeout and nothing else |

Two details are load-bearing. The exit code is classified **before** the sync's output is matched, because a
sync killed mid-flight has usually already printed its `[synced]` header — matching output first reports a
dead run as a completed one. And the marker is written **after** the run, carrying which kind of run it was,
so a run that never finished cannot charge itself the full six-hour window.

The bound itself is not optional either, and it needed more than one fix to become real. `timeout N` on
its own signals at N and then *waits* for the child to die, so a sync that ignores `TERM` is not bounded at
all — a 2 s bound against a 30 s TERM-ignoring sync returns after the full 30 s. The hook therefore uses
`timeout -k 5`, probing for `-k` support first so an implementation without it degrades instead of erroring
out. And stock macOS ships neither `timeout` nor `gtimeout`, so where neither exists the hook runs its own
bash watchdog — `TERM`, then `KILL` after a grace, aimed at the sync itself rather than at a wrapper around
it — instead of running the sync unmeasured.

**Environment overrides:** `TEMPLATE_AUTOSYNC_INTERVAL` (default 21600), `TEMPLATE_AUTOSYNC_TIMEOUT_BACKOFF`
(default 1800), `TEMPLATE_AUTOSYNC_LIMIT` (default 120 — keep it below the hook's own `timeout` in
`settings.json`, currently 130).

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

- The summary lists files that differ and are not recorded as intentional.
- `CLAUDE.md` needs the template's new critical rules merged in.
- The tech stack changed, or speckit itself needs reinstalling.
- A new external skill bundle shipped in the template.

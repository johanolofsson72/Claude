# 010 — the autosync self-test writes to the repository it tests

Track: full [hardened]. The row carries the tag, and the change touches a script that writes to a
working tree, commits and pushes to a remote. It spans 11 files: `template-autosync.sh`, six
self-tests that drive it, one production hook, and a new gate with its harness.

Source: consultpilot H7bm (`95ba64a`, 2026-09-01). consultpilot diagnosed and fixed this locally,
with a spec, a 22-question interview (four overflow answers from the developer), Allium, TLA+ and an
adversarial review. Its task T019 ("land it in the template") never happened, so the next autosync
overwrote every CORE half of the fix with the template's unguarded bytes. This spec is that landing.
The long-form diagnosis lives in consultpilot's `specs/H7bm-autosync-test-writes-to-the-repo-it-tests/spec.md`.

## Problem

`template-autosync.sh` resolves its target as `${CLAUDE_PROJECT_DIR:-$PWD}`. A caller that picks its
sandbox with `cd` alone has not picked it. Under a Claude Code hook the harness has already exported
`CLAUDE_PROJECT_DIR`, pointing at the real repository, and that value beats the `cd`.

On 2026-08-30 consultpilot's Stop hook ran `test-template-autosync-stranded.sh` that way. It synced
the real repository against a three-file sandbox template. It made and pushed 54 `chore(sync)` commits
to `origin/main` and deleted 505 lines in the working tree, including 61 of the 62 lines of
`.claude/rules/continuous-execution.md`.

State of the template on 2026-09-29, measured:

- `9b0b5ad` fixed the one line the incident named: `test-template-autosync-stranded.sh` now passes
  `CLAUDE_PROJECT_DIR`. The other layers did not land.
- `template-autosync.sh` has no way for a caller to declare a sandbox. A contained reproduction
  (scratchpad, a stand-in "real" repo) set `CLAUDE_TEMPLATE_SYNC_SANDBOX` to the sandbox and
  `CLAUDE_PROJECT_DIR` to the stand-in. The sync wrote 2 files into the stand-in and exited 0.
- `test-core-owed-tick-guard.sh:327` (`rc_of`) and `:336/:343/:346` still pick their target with `cd`
  alone. Those modes write nothing, so an ambient `CLAUDE_PROJECT_DIR` does not damage anything. It
  makes five assertions answer about the wrong repository without any visible sign.
- `core-owed-tick-guard-hook.sh:151,153` asks `--owed`/`--unlisted` with `cd "$ROOT"` alone. When the
  edited file lives outside the session's repository, the guard asks the wrong repository whether
  CORE work is owed. That is a production instance of the same defect.
- No gate stops the next self-test from being written the old way.

## Requirements

- **R1 — the interlock.** `template-autosync.sh` reads an optional `CLAUDE_TEMPLATE_SYNC_SANDBOX`.
  When it is set, and after the project root is resolved but before any write, stage,
  commit or push, the script verifies that the physical project root is inside the physical sandbox
  or equal to it. The comparison is segment-wise, not a string prefix. It refuses with exit 1 and a
  `[refused]` message naming both paths (through `tell`, so `--quiet` does not hide it) when:
  - the variable is set but empty (a departure from consultpilot, which read empty as undeclared;
    see "Adversarial review");
  - the declared path is not an existing directory;
  - the declared path resolves to `/`;
  - the project root falls outside it.

  Path resolution ignores an ambient `CDPATH`. A declared run clears the inherited `GIT_DIR`,
  `GIT_WORK_TREE`, `GIT_INDEX_FILE`, `GIT_COMMON_DIR` and `GIT_OBJECT_DIRECTORY`, so that its commit
  lands in the root it checked.
- **R2 — undeclared is unchanged.** With the variable unset, output and writes are
  byte-identical to the pre-change script for a full sync, `--check`, `--owed` and `--unlisted`.
  "Fails open" still holds for every other failure. The interlock is the one deliberate fail-closed
  path, and it only applies to runs that declared a sandbox.
- **R3 — quiet skips stay quiet.** Outside a git repository, the existing `[skip]` exit happens
  before the interlock, and `--is-core` returns before the root is resolved. Neither mode gains a
  refusal or any cost.
- **R4 — drivers name and declare.** Every self-test that drives the sync in a root-resolving mode
  passes both `CLAUDE_PROJECT_DIR=<target>` and `CLAUDE_TEMPLATE_SYNC_SANDBOX=<its mktemp dir>`:
  `test-template-autosync-{stranded,owed,eol,unlisted}.sh`, `test-core-owed-tick-guard.sh` and
  `test-sync-count-honesty.sh`. No existing assertion is removed.
- **R5 — the production hook names its target.** `core-owed-tick-guard-hook.sh` passes
  `CLAUDE_PROJECT_DIR="$ROOT"` on both queries. It declares no sandbox, because its target is the
  real repository on purpose.
- **R6 — the gate.** `scripts/validate-sync-sandbox-declarations.sh` reads `scripts/*.sh` as text.
  It does not execute the sync and makes no network call. It reports every invocation of
  `template-autosync.sh` that lacks either half of R4, or that declares `/`, with file and line, and
  exits 1. Callers whose only invocation is `--is-core` are exempt because of that property, not by
  name. Production hooks and files that only quote the command are excluded through an argued
  `path|reason` list. Exit codes: 0 clean, 1 violations, 2 cannot answer.
- **R7 — the gate's harness.** `scripts/test-validate-sync-sandbox-declarations.sh` covers the
  interlock end to end (inside, outside, `/`, empty, missing, symlinked `/var`→`/private/var`,
  shared-prefix sibling, `--quiet`, undeclared byte-identity, the `--is-core` ordering property) and
  the gate (clean tree, each missing half, `/`, `exec`/backtick forms, the `--is-core` exemption, the
  exclusion list). It includes sabotage arms that remove the interlock and confirm the harness goes
  red.
- **R8 — shipped.** Both new scripts join `CORE_SCRIPTS`, so every project receives the gate that
  checks the drivers it already receives.

## Out of scope

- One `drive_sync` helper that replaces the heuristic gate. That is row 011 (consultpilot H7bo).
- The 120 s timeout in a project's `run-gates.sh`. Registering new gates in projects' `run-gates.sh`
  is row 014.
- Rewriting consultpilot's pushed history.

## Acceptance

- AC-1 The contained reproduction exits 1 with `[refused]` and leaves the stand-in repo clean, against
  the new script. Against HEAD it wrote 2 files.
- AC-2 All six drivers keep their assertion counts (45/34/36/31/36/21 at baseline) and pass. They also
  pass with `CLAUDE_PROJECT_DIR` exported at a throwaway clone of this repo, which stays byte-identical.
- AC-3 The gate passes on this tree, and reports each deliberate violation in the harness.
- AC-4 An undeclared run gives byte-identical output to HEAD's script for full sync, `--check`,
  `--owed` and `--unlisted` in the same fixture.
- AC-5 TLC checks the interlock model with zero invariant violations, and a falsifying control
  (the `/` acceptance) produces a counterexample.

## Threat model

One new trust boundary: the environment variable read by a script that writes, commits and pushes.
The declaration can only *narrow* what the sync may touch. A value that is honoured is never less
restrictive than no value, so the risk is a declaration that gets ignored or accepted when it should
not be.

| STRIDE | Threat | Disposition |
|---|---|---|
| Spoofing | A caller claims a sandbox it is not in | No gain. The check proves root ⊆ sandbox, and lying only narrows the run. |
| Tampering | Declaration `/` | Refused in the interlock and in the gate. consultpilot's first implementation accepted it, and the adversarial review caught it. |
| Tampering | Shared-prefix sibling (`/tmp/sbx-evil` vs `/tmp/sbx`) | Refused: segment-wise compare. |
| Tampering | Symlink swap after the check (TOCTOU) | Not mitigated, deliberately. The swap needs write access to the sandbox's parent, which already grants direct access. This guards against mistakes, not against someone who already owns the filesystem. |
| Repudiation | A refusal leaves no trace | `tell` ignores `--quiet`, and exit 1 is visible to every caller. |
| Info disclosure | The refusal prints two absolute paths | Intentional. They are the diagnosis, and neither is a secret. |
| DoS | A bad declaration stops every sync | Only for callers that declare. Production declares nothing (R2). |
| DoS | Extra cost on `--is-core` before every edit | Unreachable: `--is-core` returns above the resolution (R3, asserted). |
| Elevation | Setting the variable grants anything | No. It only removes capability. |

Residual, named: a caller that declares nothing gets no check. That is by design (R2), and it is why
the gate (R6) exists. A broad but genuine sandbox (`$HOME`) passes both checks. `/` is the one value
where "declared" and "protects nothing" coincide exactly, so it is the one value the script hard-codes.

## Clarifications

### Session 2026-09-29

Auto-picked. The interview settled scope, data shape, error semantics, authorization and edge cases.
What remained was porting detail:

- Q: Port consultpilot's H7bm gate (heuristic invocation matcher) or its H7bo successor (`drive_sync`)?
  → A: H7bm. H7bo is register row 011, and taking it here would work two rows at once.
- Q: The template has no `run-gates.sh`. Where is the gate "registered"? → A: In `CORE_SCRIPTS`
  (R8), so it ships. Adding it to each project's runner is row 014's job.
- Q: The exclusion list names `scripts/core-machinery-guard-hook.sh` for a quoted command on its
  line 136. Does that hold in the template? → A: Measure it at implement time. Keep an entry only
  where running the gate without it reports a false positive.
- Q: Should consultpilot's AC numbering (AC-01..AC-30) carry over into the harness? → A: Keep the
  harness labels as ported, so a cross-reference to consultpilot's spec still resolves.

## Adversarial review (2026-09-29)

Two reviews ran. `/security-review` reported no findings at confidence 8 or above. The security-scanner,
told to assume the change was exploitable, raised ten items. It could not execute commands, so each
repro was re-run here before any decision was taken:

1. **Fixed.** A set-but-empty declaration turned the interlock off, and the gate still passed the
   driver. It now refuses (harness AC-16). Reverting the fix turns three assertions red.
2. **Fixed.** An ambient `CDPATH` sent `_phys` to a decoy directory inside the sandbox, while the walk
   wrote to the real relative project. The repro was confirmed. The fix is `CDPATH='' cd -P --`
   (AC-31). The first version of AC-31 passed even against the bug: on macOS the `/var` and
   `/private/var` spellings differ, and that mismatch refused by accident. The arm now uses physical
   paths and goes red when the fix is reverted.
3. **Fixed.** An inherited `GIT_DIR`/`GIT_INDEX_FILE` (git exports these to its hooks) redirected a
   declared run's commit into another repository while the root check passed. The confirmed repro
   moved the victim's HEAD. A declared run now unsets them (AC-32).
   **Dismissed:** a `.git` inside the sandbox that is a symlink pointing out of it. Building one
   requires owning the sandbox, which is outside this threat model (mistakes, not an attacker who
   owns the filesystem), for the same reason TOCTOU is outside it.
4. **Recorded (finding).** A declared run still pushes to whatever remote the fixture has, and
   refreshes the first local template clone when `CLAUDE_TEMPLATE_DIR` is unset. No driver in the
   template reaches either path: every full sync sets `CLAUDE_TEMPLATE_DIR` and has no remote.
   Closing it needs a push/refresh policy for declared runs, which is new behaviour.
5. **Dismissed.** The gate accepts `="$HOME"` or `="$REAL_REPO"`. The threat model already names broad
   sandboxes as inherent to prefix containment. An empty value is now refused at runtime (1).
6. **Recorded (finding, row 011).** False negatives in the heuristic gate: `/bin/bash`, `timeout`/
   `env`/`nohup` wrappers, `source`, `zsh`, `local`/`export` handles, callers outside `scripts/*.sh`,
   and a trailing `# --is-core` comment treated as exempt. Row 011 replaces the matcher with a
   single `drive_sync` entry point, which removes the whole class.
7. **Accepted.** Excluding files by path hides a future write invocation in an excluded file. The
   gate's header names this cost.
8. **Fixed by 2.** A sandbox named `-` (the `--`). Accepted: a trailing newline in a directory name.
9. **Recorded (finding, pre-existing).** A relative `CLAUDE_PROJECT_DIR` with no `.git` above it
   loops forever in the root walk, because `dirname .` returns `.`. This change did not introduce it.
10. **Dismissed.** The self-update re-exec runs the template's copy, and once this lands that copy
    carries the interlock.

During verification (not from a reviewer): the ambient-env run found `test-core-owed-tick-guard.sh`'s
`[parity]` section driving `bash-write-guard-hook.sh` with the inherited `CLAUDE_PROJECT_DIR`, which
stamped `.claude/.bash-write-marker` into the real repository. It is the same class of defect in a
different consumer. Fixed by naming the fixture project.

# 084 — autosync sandbox and harness environment

Track: full, hardened (trigger 4: well over 6 files, since every `scripts/test-*.sh` gets a
prologue; and the change sits on the sandbox boundary that spec 010 drew after the 2026-08-30
incident).
Findings: F013 F015 F016 F017 F018 F019 F020, verbatim in `specs/FINDINGS.md`.

## Problem

Specs 010 and 011 fenced `template-autosync.sh` in after a self-test synced the real repository
and pushed 54 commits. Their reviews left seven holes, and they all have the same shape: a run
picks up a target or a side effect from its environment instead of from what the caller said.

- **F015.** The project-root walk in `template-autosync.sh` (and, measured at HEAD 82b28d2, in six
  more scripts: `template-autosync-hook.sh`, `lane-orientation-hook.sh`,
  `template-sync-verify-hook.sh`, `template-sync-verify.sh`, `stack-marker-canary-hook.sh`,
  `harness-state-gc.sh`) never terminates for a relative `CLAUDE_PROJECT_DIR` with no `.git` above
  it, because `dirname .` is `.`. Each was killed by `timeout 5` with
  `CLAUDE_PROJECT_DIR=a/b`. Five of them run from SessionStart or Stop.
- **F013.** A run that declared a sandbox still (a) pushes to `origin` when the fixture's branch has
  an upstream, wherever that remote is, and (b) fetches and fast-forwards the first template clone
  on the candidate list (`~/repos/Claude` and friends) when `CLAUDE_TEMPLATE_DIR` is unset. Both
  are writes outside the declared directory.
- **F016, F020.** A self-test inherits `CLAUDE_PROJECT_DIR` from the Claude Code harness and
  `CDPATH` from the developer's shell. Around 24 scripts resolve their target from the first, and
  every `scripts/test-*.sh` opens with a relative `cd "$(dirname "$0")/.."`, which the second
  redirects to another tree (measured in 011: a decoy clone on `CDPATH` turned 8 suites red).
- **F018.** `validate-sync-sandbox-declarations.sh` only treats `template-autosync.sh` as a
  target. `template-autosync-hook.sh` runs the sync, so a test that runs the hook with the real
  repository as `CLAUDE_PROJECT_DIR` passes the gate.
- **F019.** The gate says a target is run only when an interpreter or a known wrapper precedes it.
  An unknown wrapper (`chronic "$S"`, `unbuffer "$S"`) is a run the gate does not see.
- **F017.** Open question from 010: should the sync refuse when the project root is the repository
  the running script lives in?

## Requirements

- **R1 — Root walks terminate (F015).** Every walk that starts from `${CLAUDE_PROJECT_DIR:-$PWD}`
  or `$PWD` makes the start directory absolute first, and stops when `dirname` returns its input. A
  relative start that exists is resolved physically (`CDPATH='' cd -P`, so `..` lands where it points
  and not on the child it was spelled from, per the adversarial review); one that does not exist is
  prefixed with `$PWD` lexically. A relative
  `CLAUDE_PROJECT_DIR` now resolves to the same root as its absolute spelling. An absolute one
  behaves exactly as before, including one that does not exist.
- **R2 — A sandboxed run does not push out (F013a).** When `CLAUDE_TEMPLATE_SYNC_SANDBOX` is
  declared, the sync pushes only when **every** URL `git remote get-url --push --all origin` prints
  (so `pushurl`, `insteadOf` and `pushInsteadOf` are already applied) is a local directory inside the
  sandbox, judged physically and by segment, and is where git lands: the path's own git dir is the
  path or `<path>/.git`, and its git common dir is inside too (a `.git` file pointing out, an empty
  directory beside an outside `<path>.git`, and a worktree of an outside repository all fail; each
  was a verified escape in the adversarial review). A URL counts as local only when it is an absolute path,
  a relative path (resolved from the project root, where git resolves it), or `file:///…` with no
  host. A `%` anywhere, a `::` transport, an scp-like `host:path` and a URL with a host are outside,
  and so is a path that does not resolve. Outside: the commit stays local and the report says
  `not pushed — origin is outside the declared sandbox` (no URL is printed, since a URL can carry a
  token). An undeclared run pushes exactly as before.
- **R3 — A sandboxed run does not refresh a clone outside it (F013b, developer O3).** When a
  sandbox is declared, `refresh_local_template` runs only for a candidate whose directory **and**
  git common dir (`git rev-parse --git-common-dir`, which is where a fetch and a merge write) are
  both inside it. A clone outside is used as-is (no fetch, no fast-forward) and the run says so in
  one `[note]` line. A declared run also sets `GIT_OPTIONAL_LOCKS=0`, so its `git status` calls do
  not rewrite an outside clone's index. An undeclared run refreshes as before.
- **R4 — Self-tests inherit no target (F016, F020).** A new `scripts/self-test-env.sh` (CORE)
  unsets every ambient variable that picks a test's target or changes what the sync does: `CDPATH`,
  `BASH_ENV` (for the test's children; the test's own shell has already read it), `CLAUDE_PROJECT_DIR`,
  the git location variables (`GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE`, `GIT_COMMON_DIR`,
  `GIT_OBJECT_DIRECTORY`, `GIT_ALTERNATE_OBJECT_DIRECTORIES`, `GIT_CEILING_DIRECTORIES`), the
  command-line git config (`GIT_CONFIG_PARAMETERS`, `GIT_CONFIG_COUNT`), and the sync's and hook's
  knobs (`CLAUDE_TEMPLATE_DIR`, `_PIN`, `_ALLOW_DIRTY`, `_SYNC_SANDBOX`, `_AUTOSYNC`,
  `_AUTOSYNC_ALWAYS`, `TEMPLATE_AUTOSYNC_INTERVAL`, `_LIMIT`, `_NAME_LIMIT`, `_TIMEOUT_BACKOFF`).
  Every `scripts/test-*.sh` sources it as its first statement:
  `. "$(dirname -- "$0")/self-test-env.sh" || exit 1` (`dirname` does not `cd`, so `CDPATH` cannot
  steer it). A new `scripts/test-self-test-prologue.sh` fails when a test file does not source it,
  or sources it after its first `cd`, `pwd` or `$(dirname` resolution. It checks that the file
  names every variable above, and it runs a sample of suites with a decoy `CDPATH` and a decoy
  `CLAUDE_PROJECT_DIR`, asserting that the decoy stays byte-identical and the suites stay green.
- **R5 — The hook is a target (F018).** The gate treats `…template-autosync-hook.sh`, and a handle
  whose value ends in `-autosync-hook.sh`, as a target in the same way it treats the sync.
  `scripts/drive-sync.sh` gains `drive_hook <project> <sandbox> [args…]`, which runs
  `DRIVE_HOOK_SCRIPT` (required, absolute) with both halves set and the same argument checks as
  `drive_sync`, plus one more: the project must be physically inside the sandbox, because the
  hook writes its own marker (`.claude/.template-sync-check`) into the project even when the sync
  refuses. Every test that runs the hook goes through it. The gate's definition census covers
  `drive_hook`. The project must also be the root the hook resolves: with no `.git` of its own and a
  repository somewhere above it, `drive_hook` refuses, since the hook would walk up to that one.
  `DRIVE_SYNC_PATH` (both helpers) sets `PATH` for the driven script only, after the timeout binary
  is found, so a test that hides coreutils from the hook still gets its bound (drift 2, /tla).
- **R6 — More wrappers are known (F019, developer O2).** A target is also run when any of
  `chronic`, `unbuffer`, `flock`, `runuser`, `taskset`, `chrt`, `numactl`, `strace`, `ltrace`,
  `valgrind`, `firejail`, `systemd-run`, `watch` or `su` precedes it anywhere in its command segment.
  `watch` and `su -c` also hand their text to a shell, so they join `eval` and `bash -c` under the
  code rule: the target anywhere in the segment's text is a run. `bash -n` (and `sh`/`zsh`/… `-n`)
  parses without executing and is not a run (drift 3, /tla). These programs exist to run their
  arguments, so no option arity is needed: `taskset -c 0-3 "$S"`
  and `flock -E 3 f "$S"` are runs whatever their options take. An unknown wrapper stays a named
  residual in the gate's header. Inverting the rule was measured and declined: 130 new
  hits on the current tree, none of them a run.
- **R7 — No self-sync refusal (F017, developer O1).** Declined. The production hook runs
  `<project>/scripts/template-autosync.sh` against `<project>`, which is the shape F017 would refuse.
  The route it worried about is closed by R4 and R5. Nothing changes in the sync for F017.
- **R8 — Docs.** `.claude/docs/template-autosync.md` states what a declared sandbox now guarantees
  (R2, R3) and the named residuals. The headers of `drive-sync.sh` and the gate describe
  `drive_hook` and the new run rule.

## Out of scope

- The CDPATH-relative `cd` in non-test production scripts run directly by a developer. Under the R4
  prologue a test's children inherit no `CDPATH`, so the suites are covered. Recorded as a finding.
- Lexical `..` in a start directory. `CLAUDE_PROJECT_DIR=../..` walks `$PWD/../..` the way an
  absolute `/a/b/../..` already does today; R1 only makes the two spellings agree.
- A fixture whose git config points outside (`core.hooksPath`, `core.worktree`, a `.git` file), the
  developer's `~/.gitconfig` (`HOME` is left alone: fixtures commit with the developer's identity),
  and a hand-set `CLAUDE_TEMPLATE_SYNC_SANDBOX` that contains the real repository (`drive_sync`
  refuses that; the sync cannot, see O1). Named residuals.
- Temp directories the sync makes outside the sandbox (`mktemp -d` for the tarball and the EOL
  stage). Spec 010 already named them: they are created, used and removed by the run.
- The template mutation runner (row 085). The hard mutation gate is met with sabotage arms, as
  082 and 083 did.

## Clarifications

### Session 2026-10-01 (auto-picked, recommended option; R2–R6 widened after the threat-model review)

- Q: Which walks does R1 cover? → A: Every `while [ "$X" != "/" ] && [ -n "$X" ]` walk in a non-test
  script that starts from `CLAUDE_PROJECT_DIR`, `$PWD` or a value derived from them and has no `.`
  guard: twelve files at HEAD. Seven hang today; the other five reach an early exit first on the
  measured input, but they have the same loop and the same fix. The five Edit-path guards already
  canonicalise through `guard_canon` (083) and stay as they are.
- Q: Does R2 change the exit code or the machine-readable report? → A: No exit-code change (exit 0,
  like "no upstream — not pushed"). `pushed=no` in the machine report.
- Q: Does R4 cover `scripts/test-*.py`? → A: No. Python tests do not `cd` through CDPATH, and none
  resolves a target from `CLAUDE_PROJECT_DIR` without setting it. Shell tests only.
- Q: Does `drive_hook` accept the query-mode exemption like `drive_sync_readonly`? → A: No. The hook
  has no query mode. It always runs the sync, so it always needs a sandbox.
- Q: Does R6 need an option-arity table? → A: No (threat-model review): a listed wrapper anywhere
  before the target in its segment is a run. `takes_arg` stays as it is; it is global, and `-c` means
  code for `bash`.

## Threat model

Trust boundary: **a self-test or sandboxed driver → the developer's real repositories and remotes**.
The attacker is the next honest author of a self-test, or an ambient environment (the harness, a
shell profile, a git hook) that aims a run somewhere its author did not mean. Not an obfuscating
adversary (010, 011).

### TB1 — environment → target selection (R1, R4)

- **Tampering.** `CLAUDE_PROJECT_DIR`, `CDPATH` or `GIT_DIR` inherited by a test aims a sync, a guard
  or a gate at another tree. *Mitigation:* R4 clears all of them at every test's first line, and the
  children inherit the cleared environment. *Residual:* a production script a developer runs by
  hand with `CDPATH` set (recorded as a finding); `BASH_ENV` for the test's own shell; `HOME`'s git
  config.
- **Denial of service.** A relative `CLAUDE_PROJECT_DIR` hangs a SessionStart or Stop hook forever.
  *Mitigation:* R1. *Residual:* none known in the walk; the harness's own hook timeout stays the
  outer bound.

### TB2 — declared sandbox → writes outside it (R2, R3)

- **Tampering / repudiation.** A sandboxed run pushes to a real remote or moves the developer's
  template clone, while its declaration says it writes only inside. *Mitigation:* R2 (push only
  to an in-sandbox local origin, judged physically) and R3 (no fetch or fast-forward outside).
  *Residual:* temp directories under `$TMPDIR` (named in 010), and the tarball download's network
  read (a read, not a write).

### TB3 — scripts → the sync, unseen by the gate (R5, R6)

- **Elevation (gate bypass).** A test runs the hook, which runs the sync, with the real repository
  as target, or runs the sync behind a wrapper the gate does not know. *Mitigation:* R5 (the hook is
  a target and has its own helper), R6 (twelve more wrappers with their arity). *Residual:* an
  unknown wrapper, a positional-parameter call and a quote-spliced name, named in the gate header.

### Adversarial review (2026-10-01)

`security-scanner` in assume-exploitable mode read the diff (it had no shell, so every high finding
was verified here with a PoC before deciding). Fixed in this spec: (1) `drive_hook` judged the
argument, not the root the hook resolves; it now refuses a project with no `.git` of its own under
a repository. (2) Verified escape: a push URL whose directory has a `.git` file pointing out, or an
empty directory beside an outside `<path>.git`, was judged inside and pushed outside; R2 now judges
where git lands. (3) `..` in a relative start picked the child repository; resolved physically now.
(4) `self-test-env.sh` gained the `DRIVE_*` variables (an ambient `DRIVE_SYNC_SCRIPT` defeated "no
default") and the git config/transport variables. (5) The prologue checker accepted `set -u; cd …`
before the reset; only option-setting `set` lines pass now, and an empty population fails.

Recorded rather than fixed: rule (d) can flag a wrapper name used as a plain argument earlier in the
segment (`grep -q watch "$S"`, none on the tree); wrappers outside the list (`parallel`, `script -c`,
`ssh`, `docker`, `nsenter`, `xvfb-run`, `gdb --args`) and handle copies (`S2=$S`); `DRIVE_SYNC_PATH`
resolves `bash` through the shimmed PATH; `core.worktree` in an in-sandbox clone; a `case` pattern
spelled as the literal sync path reads as a run (false positive, met while writing the R1 test).

### /security-review (2026-10-01)

No high-confidence findings. Every new path narrows behaviour, and only for a declared sandbox: a push
or fetch that would leave it is skipped, the note carries no URL, and the root-walk input is a
trusted environment variable.

# 092 — kill surviving mutants

Track: full, hardened. Trigger 4 fires on file count alone (about ten test files and the verdict
helper). No risk domain, state machine or new entity is involved. Hardening here means a short threat
model (no new trust boundary), the hard mutation gate on every named line, and an adversarial review
of the diff.
Findings: F099 F100 F101 F102 F108, verbatim in `specs/FINDINGS.md`.

## Problem

H3 (eb791de) and 085 (088a3bb) sampled survivors at line numbers that have since moved. On
2026-10-02 each one was mapped by content to the current tree (0f9a90c) and every site on those lines
was measured with `run-mutation-gate.sh --lines` (seed 20261002): **28/69 killed (40.6%), 41
survived, 1 timeout**.

| Module | Lines (now) | Killed | Survivors |
|---|---|---|---|
| `template-autosync.sh` (F099, F108) | 737 938 2002 2310 2533 2613 2849 3107 3526 3764 | 5/21 | 16 on 938 2002 2310 2533 2613 3107 3526 3764 |
| `project-maintenance.sh` (F100, F108) | 236 264 327 352 659 1080 1081 1098 1150 1846 | 13/25 | 12 on 236 264 327 352 659 1081 1098 1150 |
| `spec-interview-guard-hook.sh` (F102) | 110 285 315 341 353 421 | 3/7 | `exit 0`→`exit 1` after the 96, 97, 98 and resolver-failure denies |
| `guard-lib.sh` (F101) | 518 519 542 | 4/11 | 7: every `&&`→`||` on the `.csproj`/`.sln` marker lines and all three `_guard_has_match` sites |
| `validate-scenario-traceability.sh` (F108) | 157 | 2/3 | `--dir` with no value `exit 2`→`exit 0` |
| `project-freshness.sh` (F108) | 404 | 1/2 | the `-n`→`-z` mutant loops forever at EOF: a timeout, never a kill |

Three causes behind the numbers:

1. **No fixture is a register with no language marker at all.** F101 asked for a `.csproj`-only
   project, and spec 090 added one (`test-guard-canonical-paths.sh` "markers"). It still leaves
   guard-lib's marker lines alive, because each mutant makes *every* directory a .NET project, and
   that is only visible in a project that has none. Without that fixture, the template/scratch-repo
   exemption is untested.
2. **Guard deny routes are tested without their exit code.** A guard that prints a deny and exits 1
   is a non-blocking error to the CLI, which then lets the call through. `test-guard-fail-closed.sh`
   and `test-guard-canonical-paths.sh` already turn a non-zero exit into its own verdict, but the 96,
   97 and 98 routes and the python3-missing route are reached only by suites that do not
   (`test-pipeline-hooks.sh`, `test-acceptance-cases.sh`, `test-guard-root-anchor.sh`), or not at
   all. `hook-verdict.sh` takes no exit code, so every suite has to remember on its own.
3. **Error exits and quiet branches have no case.** Missing `sha256sum`/`shasum`, an unwritable
   trust store, an unwritable temp dir for the private copy, `--if-due` with nothing due, two
   in-progress rows, `gtimeout` as the only timeout, `--dir` with no value, the template's own
   `--owed`, a template-history match, an exec-bit-only difference under `--check`, a resolved
   orphan, the `[check]` line of a never-synced project, a stamp line with no path, the commit's
   pathspec guard, and a project with no verify declaration.

## Requirements

- **R1 — A project with no language marker is not gated (F101).** A fixture with a git root, a
  register whose active spec owes everything, and no marker of any kind (no `package.json`, no
  `*.csproj`, no `*.sln`): spec-interview-guard, pipeline-state-guard and spec-register-guard all
  answer `none`, exit 0, for `src/App.cs`. A second fixture puts the marker in a subdirectory only
  (`src/App.csproj`, nothing at the root) and an edit at the root (`Root.cs`): `none` too, because
  the walk goes up from the file and never down. Both live in `test-guard-canonical-paths.sh` next to
  the existing `.csproj`/`.sln` cases. They kill guard-lib.sh 518, 519 and 542.
- **R2 — A guard's verdict includes its exit code (F102).** `hook_verdict OUT [RC]`: with a
  second argument that is not `0`, the answer is `exit-<RC>` whatever the output says, because the
  CLI reads a hook's JSON only on exit 0. Without the argument it behaves exactly as before.
  `test-hook-channels.sh` section 13 pins both forms. The rc-blind `verdict()`/`run_guard`/`iv_guard`
  helpers in `test-guard-root-anchor.sh` and `test-pipeline-hooks.sh` capture `$?` and pass it on.
- **R3 — Every spec-interview deny route is pinned at exit 0 (F102).** In
  `test-guard-fail-closed.sh` (already a target suite for the guard), one case per route, each
  asserting `deny` *and* exit 0 through R2:
  96, a full-track spec with 15 answers and no `acceptance.md`; 97, an active row whose id is outside
  the grammar; 98, the guard run from a copy of `scripts/` without `spec_active.py`; and the
  resolver failing to start, with python3 off PATH but jq still on it.
- **R4 — template-autosync.sh survivors (F099, F108).** One case each, in the suite that already
  owns the behaviour (`test-template-autosync-arms.sh` unless another suite is the natural home):
  - 938: `--owed` in the template exits 2 and prints nothing on stdout.
  - 2002: a project file whose bytes equal an *older* template version is classified as
    template-history (updated), not as a local edit (skipped).
  - 2310: an exec-bit-only difference under `--check` is listed as an update and the mode on disk is
    unchanged. Under a real sync, the mode is mirrored.
  - 2533: an orphan candidate the developer has deleted is not reported again.
  - 2613: `[check]` names `never synced` for a project with no stamp, and the stamp's SHA when there
    is one.
  - 3107: a stamp `# wrote` line with a hash and no path is ignored, so the carried entries stay
    intact.
  - 3526: a run with nothing to commit makes no commit, and HEAD does not move.
  - 3764: an unverified sync with no `.template-sync-verify` says how to declare one, and with a
    declaration it names the command.
- **R5 — project-maintenance.sh survivors (F100, F108).** In `test-project-maintenance.sh` or
  `test-maintenance-trust.sh`, whichever owns the flag:
  - 236: when the private copy cannot be made, the item is not run as trusted.
  - 264: `--trust` with neither `sha256sum` nor `shasum` on PATH exits 2 and names both.
  - 327: `--trust` with an unwritable store exits 2 and leaves the store unchanged.
  - 352: `--if-due` with nothing due exits 0 and says `nothing due`.
  - 659: two `- [/]` rows produce the `[REGISTER] 2 rows marked in-progress` finding, and one row
    does not.
  - 1081 and 1098: the functions' contracts are tested directly, as C106 did for 1080: with python3
    or `stryker_guard.py` missing, `mutation_break_of` prints nothing and returns 0, and
    `mutation_modules_under` prints `nopython` and returns 0.
  - 1150: with `gtimeout` the only timeout on PATH, stryker_guard runs bounded, and the `ran
    unbounded` note is absent.
- **R6 — traceability and freshness (F108).** `validate-scenario-traceability.sh --dir` with no value
  exits 2 and names `--dir`. `project-freshness.sh` reads a `.secret-shapes-allow` whose last line
  has no newline and finishes within a bound of its own (20 s), so the EOF-loop mutant fails the case
  instead of timing out the runner.
- **R7 — The gate is re-measured, not assumed.** After R1–R6, the same `--lines` invocation (same
  lines, rebased to wherever they then sit) runs again. Every site is killed or carries a
  `# mutant-equivalent: <reason>` marker on its line, and the reason must hold up. The `--lines`
  score must be at least 95%. Any site left alive is a finding with its reason.

## Out of scope

- Fresh sampling of other lines. That is the nightly's job, and new survivors are recorded, not
  folded in here.
- Changing production behaviour. If arming a survivor shows real dead code, the code change is the
  smallest that makes the line's intent testable, and it is recorded in this spec.
- The 093 row (section 5's report on the bash runner, suite timeouts). Separate row.

## Threat model

No new trust boundary: this spec adds test fixtures and one optional argument to a test helper.
STRIDE over what changes:

- **Tampering / elevation:** a test edit that weakens a guard's assertion would hide a fail-open.
  Mitigation: every change here adds assertions or makes them stricter (R2 can only turn a pass into
  `exit-N`). The adversarial review checks that no existing expectation was relaxed.
- **Denial of service:** the R6 freshness case runs a script under a bound. It uses the runner's
  `timeout`/`gtimeout` probe and falls back to a background-kill watchdog, so a host without either
  still cannot hang the suite.
- **Information disclosure:** fixtures live under `mktemp -d` with `HOME` redirected, as in every
  suite they join. Nothing reads the real `~/.claude` or `~/repos`.

## Clarifications

### Session 2026-10-02 (auto-picked, recommended option; measured where it could be)

- Q: Does the spec-register-guard need a no-marker case too? → A: Yes, but it only gates a project
  with no register, so its no-marker case removes the register (092-AC-1).
- Q: R2, should `hook_verdict` require the rc? → A: No. Optional and backwards compatible, so the
  suites that already map a non-zero exit to `exit-N` keep working. The rc-blind helpers named in R2
  pass it.
- Q: R3, where does the 98 route come from without breaking the real tree? → A: A copy of the guard,
  `guard-lib.sh` and `guard-precheck.sh` in a temp `scripts/` with no `spec_active.py`. The hook
  imports the resolver from its own directory.
- Q: R7, which seed? → A: `--lines` measures every site, so the seed only labels the run. 20261002
  is reused so the before and after line up.
- Q: R5 1081/1098, mark equivalent or test the contract? → A: Test the contract (Q12). Both lines
  hold a `&&`/`||` site that a marker would hide.

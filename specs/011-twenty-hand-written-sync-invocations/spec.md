# 011 — twenty hand-written sync invocations force a clever gate

Track: full [hardened]. The row says full; triage escalates it on the size trigger
(`.claude/rules/spec-hardening.md` trigger 4). The change touches 11 files, all of them CORE: a new
helper and its harness, the gate and its harness, six drivers, and `template-autosync.sh`'s
CORE_SCRIPTS list. The code being rewritten is spec 010's safety interlock, so a
maintainability change that loses one of the gate's abilities reopens the 2026-08-30 incident.

Source: consultpilot H7bo (`5078ed1`, 2026-09-02). consultpilot designed and built this with a spec,
a 21-question interview (three answered by the developer), Allium, TLA+ and an adversarial review
that found five bypasses in its first draft. The long-form diagnosis lives in consultpilot's
`specs/H7bo-twenty-hand-written-sync-invocations-force-a-clever-gate/spec.md`. consultpilot's local
copies of the converted drivers were overwritten by its next `chore(sync)` (finding F012), so the
design reaches this repository only through that commit. This spec lands it.

Row 026 (`port-drive-sync-and-its-gate-upstream`) has the same scope. At the tick it is deleted, per
the developer's decision of 2026-09-29.

## Problem

Spec 010 made every driver of `template-autosync.sh` spell two halves by hand:

```
CLAUDE_PROJECT_DIR=…            names the target; without it `cd` is decoration
CLAUDE_TEMPLATE_SYNC_SANDBOX=…  declares the only directory the run may write inside
```

Measured on 2026-09-29 in this tree: **19 hand-spelled declarations across 6 driver files**. They sit
under three wrapper names (`sync`, `run_sync`, `rc_of`) plus inline calls, with three sandbox
variables (`$TMP`, `$WORK`, `$root`). No single invocation form exists, so
`validate-sync-sandbox-declarations.sh` has to work out the convention backwards. It needs a
handle derivation, two match arms, a two-line lookback, a `/` branch and seven exclusions. Two of
those exclusions (REASON B) exist only to absorb its own false positives. Spec 010's adversarial
review recorded eight false negatives in it as finding F014.

The template also has more than consultpilot had. There are four query modes, not one
(`--is-core`, `--list-core-scripts`, `--list-core-rules`, `--template-dir`), plus a third production
driver, `lane-catchup.sh:149`. When consultpilot's gate runs unmodified against this tree it reports
**28 violations in 9 files**. Nineteen of those are the six drivers, and nine are query-mode callers
and a handle false positive that the port has to handle as properties.

## Requirements

**The helper (`scripts/drive-sync.sh`, sourced, never run)**

- **R1 — one entry point for writes.** `drive_sync <project> <sandbox> [args…]` runs the script named
  by `DRIVE_SYNC_SCRIPT` in a subshell. `CLAUDE_PROJECT_DIR` and `CLAUDE_TEMPLATE_SYNC_SANDBOX` are
  set from the two arguments. It forwards argv verbatim and returns the sync's exit code. The caller's
  shell is unchanged afterwards: no variable, no cwd.
- **R2 — values are validated before anything starts.** It refuses with exit **64**
  (`DRIVE_SYNC_EBADARG`), which is distinct from the sync's 0/1/2, and a message on stderr, when:
  - the project is empty, missing, or not a directory;
  - the sandbox is empty, relative, `/`, missing, not a directory, or **contains this repository**;
  - `DRIVE_SYNC_SCRIPT` is unset, missing, or unreadable;
  - `DRIVE_SYNC_CWD` cannot be entered;
  - a timeout was asked for and no `timeout`/`gtimeout` exists.
- **R3 — one mechanism per optional behaviour.** Extra env rides a prefix assignment on the call.
  Cwd comes from `DRIVE_SYNC_CWD`, the binary from `DRIVE_SYNC_SCRIPT` (required, no default), and the
  bound from `DRIVE_SYNC_TIMEOUT`.
- **R4 — a checked write-free entry point.** `drive_sync_readonly <project> [args…]` runs with no
  sandbox, and only when argv carries one of the four query modes. Those modes return above the
  project-root resolution in `template-autosync.sh`, so the proof is read off the arguments. Any other
  argv is refused with 64. *Template adaptation: consultpilot accepted `--is-core` only.*
- **R5 — shipped, not sourced by the sync.** `drive-sync.sh` and `test-drive-sync.sh` join
  CORE_SCRIPTS. `template-autosync.sh` does not source the helper, so the sync gains no dependency.

**The gate (`scripts/validate-sync-sandbox-declarations.sh`)**

- **R6 — one rule.** No script under `scripts/` (recursively) may put `template-autosync.sh`, or a
  handle assigned a path ending in it, in command-word position (`bash`, `sh`, `exec`, `source`,
  `.`, `eval`) outside a quoted string, a heredoc or a comment, except through the helper. It no
  longer reads declarations, looks back two lines or has a `/` branch.
- **R7 — exemptions by property, checked.**
  - The sync itself.
  - The helper's definition site. The gate asserts **exactly one** file defines
    `drive_sync`/`drive_sync_readonly` and that it is `scripts/drive-sync.sh`.
  - Any line whose argv carries one of the four query modes.
- **R8 — exemptions by argued list: exactly 4.** They are `template-autosync-hook.sh`,
  `core-owed-tick-guard-hook.sh`, `lane-catchup.sh` (production drivers of the real repository) and
  the gate's own harness (its fixtures are the violations, and `run_sync` / `sync_undeclared` must hand
  the interlock invalid or absent declarations). Deleting any entry makes the gate report that file.
  *Developer decision 2026-09-29: the template's cap is 4. consultpilot's is 3.*
- **R9 — handle derivation matches values, not mentions.** A variable is a handle only when its
  assigned value ends in `-autosync.sh`, allowing only closing quotes or braces after it.
  `TPL=$( [ -f scripts/template-autosync.sh ] && … --template-dir )` is not a handle. That removes
  `lane-catchup.sh:172`'s false positive, which spec 010 had absorbed with a second reason on its
  exclusion.
- **R10 — offline and honest.** The gate reads text and starts nothing. A scanner failure (awk
  stderr) exits 2, never 0. Exit codes: 0 clean, 1 violations, 2 cannot answer.

**Callers**

- **R11 — the six drivers go through the helper.** These are
  `test-template-autosync-{stranded,owed,eol,unlisted}.sh`, `test-core-owed-tick-guard.sh` and
  `test-sync-count-honesty.sh`. Afterwards, their non-comment `CLAUDE_TEMPLATE_SYNC_SANDBOX=` count is
  **1**: the eol test's hook invocation. The hook is a different program that runs the sync itself,
  so it is not a sync call site. Every driver keeps its assertion count.

**Proof**

- **R12 — the helper's harness** (`scripts/test-drive-sync.sh`) covers the happy path, leak freedom
  (before/after, also under a hostile ambient env), each refusal, the read-only entry for all four
  modes, the contains-repo refusal, and sabotage arms that break one branch at a time. The arm count
  is reported as a number. It stands in for the mutation gate on bash.
- **R13 — the gate's harness** keeps every arm spec 010 had, or names the successor that tests the
  same ability. It adds consultpilot's quoting, bypass, recursion, uniqueness, census and per-driver
  falsification arms. consultpilot's AC-31..AC-42 are renumbered AC-45..AC-56 so spec 010's AC-31/32
  (CDPATH, GIT_DIR) keep their labels.

## Out of scope

- Any change to the interlock inside `template-autosync.sh` (only CORE_SCRIPTS changes).
- Registering gates in a project's `run-gates.sh` (row 014).
- consultpilot's deferred E1 (one scanner process instead of one per file) and A1 (a line-level
  fixture pragma instead of a file exclusion).
- Push/refresh policy for declared runs (F013). Relative-path root walk loop (F015).

## Acceptance

- AC-1 The gate passes on this tree with 0 direct invocations, and the four exclusions and all
  exemptions are counted.
- AC-2 Deleting any one of the four exclusion entries makes the gate report that file.
- AC-3 The six drivers keep their assertion counts (baseline measured before conversion), and all
  pass with `CLAUDE_PROJECT_DIR` exported at a throwaway clone, which stays byte-identical.
- AC-4 `test-drive-sync.sh` is green, and every sabotage arm reddens.
- AC-5 `test-validate-sync-sandbox-declarations.sh` is green with more assertions than its 010
  baseline, and every falsification arm reddens.
- AC-6 F014's false-negative shapes are each a fixture that the gate reports: `/bin/bash`, `timeout`
  / `env` / `nohup` wrappers, `source`, `zsh`, `local`/`export` handles, callers in subdirectories,
  and a trailing `# --is-core` comment.
- AC-7 TLC checks the model with zero violations. The sentinel control and the
  containing-sandbox control each produce a counterexample.

## Threat model

The trust boundary is not a network or user input. It is *a script under `scripts/` that runs the
sync without the gate seeing it*, and the adversary is accidental: the next person or agent to write
a self-test.

| # | STRIDE | Threat | Disposition |
|---|---|---|---|
| T1 | Tampering | A new driver writes the call in a shape the matcher does not know | The allowed surface becomes one word (`drive_sync`). Every other shape in command position is a violation (R6) |
| T2 | Tampering | The sync is copied to a name without `-autosync.sh` and run through a variable | Reduced, not closed. Drivers pass the copy as `DRIVE_SYNC_SCRIPT`, so the helper runs it. The residual blind spot is named in the gate header |
| T3 | Tampering | A sandbox of `/`, `$HOME` or the repo's parent (declared, constrains nothing) | Refused once in the helper, by value (R2) |
| T4 | Tampering | A sandbox that is empty, relative or missing | Refused in the helper (R2), and the interlock still refuses empty/missing (010) |
| T5 | Elevation | An argued exclusion used as a grandfather list: a listed file later gains a real call | The list is capped at exactly 4, pinned by the harness. The query-mode exemption is a property checked per line (R7, R8) |
| T6 | Tampering | The helper leaks env into the caller and poisons the next assertion | Subshell. Before/after assertions, including under a hostile ambient env, plus a sabotage arm that removes the subshell (R12) |
| T7 | DoS/Elevation | The gate becomes the caller that escapes (it runs the sync to decide something) | Reads text only. The AC-11 tripwire proves it (R10) |
| T8 | Spoofing | A driver defines its own `drive_sync()` and walks out through the definition-site exemption | Uniqueness assertion: exactly one definition site (R7) |
| T9 | Repudiation | A scanner crash reads as a clean tree | awk stderr is captured, and a non-empty capture exits 2 (R10) |
| T10 | Info disclosure | Refusals print absolute paths | Intentional. They are the diagnosis, and none is a secret |
| T11 | Tampering | `drive_sync_readonly` used to skip the sandbox on a writing call | argv must carry a query mode, or it refuses (R4). The model's control shows the empty-sentinel alternative fails |

Unmitigated threats: none. T2 is the one named, reduced residual.

## Clarifications

### Session 2026-09-29

Auto-picked, except the two answers marked as the developer's. The interview settled scope, data
shape, error semantics and edge cases. What remained was porting detail:

- Q: Which query modes may `drive_sync_readonly` accept? → A: All four. They share the property the
  gate's exemption rests on (they return above the resolution), and the harness asserts that property
  for each one. Accepting fewer would make a caller of `--list-core-scripts` either hand-spell or go
  through a writing entry with a fake sandbox.
- Q: The gate has four argued exclusions, one above consultpilot's cap of 3. → A (developer): the
  cap is 4 in the template, each entry argued and falsifiable.
- Q: What happens to row 026? → A (developer): delete it at the tick, with a Register history line.
- Q: consultpilot and spec 010 both use AC-31/AC-32 in the gate harness, for different things. → A:
  010's labels win, because they are this repository's own spec. consultpilot's AC-31..AC-42 become
  AC-45..AC-56, and each carries an `(H7bo AC-nn)` cross-reference.
- Q: consultpilot's files carry `Covers: SC-18xx` lines. → A: Strip them. CORE files ship into
  projects whose SC numbering is their own (row 012).
- Q: Does `lane-catchup.sh`'s second exclusion reason (the `TPL` handle false positive) survive? →
  A: No. R9 tightens the derivation so the false positive no longer occurs, and the entry keeps
  REASON A only.

## Adversarial review (2026-09-29)

Two reviews ran. `/security-review` reported nothing at confidence 8 or above. The security-scanner
was told to assume the change was exploitable. It could not execute, so each of its 16 items was
re-run here as a fixture before anything was decided. All 14 gate repros exited 0 against the
first lexer, and both helper repros went ahead.

- **Fixed in this spec** (fixtures AC-62 in the gate harness, J in the helper harness):
  - #1 a path glued after `$(…)` was never scanned;
  - #2 `$(( 1 << 3 ))` read as a heredoc and swallowed the rest of the file, silently;
  - #3 a handle inside a word (`$PWD/scripts/$NAME`, `${S:?}`);
  - #4 handles assigned before `;`, with `local -r`, as a `for` variable, or from `$(realpath …)`;
  - #5 an array holding the command;
  - the narrow half of #7: `bash -o`, `exec -a`, `env -u`, `timeout -s`, `setsid`, `busybox ash`;
  - #8 a query mode forged through a redirect target;
  - #9 `#` right after `)` read as a comment;
  - #10 extensionless, `.bash` and symlinked scripts never opened;
  - #11 the helper's internals redefined or reassigned, and a `DRIVE_SYNC_EBADARG=0` that turned
    refusals into runs (the helper now returns a literal 64);
  - #12 a run at the helper's top level was exempt;
  - #13 a relative `DRIVE_SYNC_SCRIPT` and a non-numeric `DRIVE_SYNC_TIMEOUT`;
  - #14 `command -v "$S"` read as a run;
  - #16 the contains-repo check failing open when the helper cannot resolve its own repository.
- **Recorded** (developer): #6 the hook route (F018), and #7's broad half, inverting the rule
  (F019).
- **Dismissed** (Claude, stated at the findings stop):
  - #10b a quote-spliced name, which is deliberate obfuscation and outside the threat model (it is
    named in the gate header);
  - #15 the read-only property is asserted for the repo's sync only, with no repro and no caller;
  - #14b `--help` counts as a run, the conservative direction.

The helper's own harness has to set the internals it tests, so it is the one file besides the
helper allowed to touch `_drive_sync_*`. It is named in the gate (`HELPER_HARNESS_REL`), not added
to the exclusion list, and it is still judged for runs.

## Measured outcome

| Criterion | Target | Measured |
|---|---|---|
| Hand-spelled sync declarations in the six drivers | 19 → 0 | 19 → 1. The one left drives the hook, not the sync, and AC-57 pins it |
| Call shapes | 4 → 1 | 1 (`drive_sync`) |
| Argued exclusions | exactly 4 (developer cap) | 4, each falsified by AC-60 |
| Six drivers' assertion counts | unchanged | 36/21/36/34/45/31 before and after, and again under an ambient `CLAUDE_PROJECT_DIR` |
| Decoy clone after the ambient run | byte-identical | 0 status lines incl. ignored, HEAD unmoved |
| Gate harness | > 84 (010) | 199 / 0 |
| Helper harness | green, arms red | 72 / 0, sabotage arms 15 / 15 |
| Gate sabotage (mutation stand-in) | all red | 27 / 27 |
| Gate cost | no regression | CPU 0.6 s vs 1.1 s for the old gate (one awk process for the tree) |
| TLC | 0 violations, controls fail | 233 states, 0 violations; both controls violate |

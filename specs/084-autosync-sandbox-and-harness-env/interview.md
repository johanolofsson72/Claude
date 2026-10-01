# Spec interview — 084-autosync-sandbox-and-harness-env

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO (base auto-answered with recommended; genuinely-ambiguous escalated; overflow human-answered if flagged).
Flag: hardened (≥ 6 files, on the sandbox boundary spec 010 drew), so the three policy questions go to the developer as overflow (O1–O3), one of them threat-surface (O3: what a sandboxed run may touch).

## Q1 — Scope boundary
**Q:** Does 084 fix the root walk only in `template-autosync.sh`, as F015 names it, or everywhere the same loop hangs?
**A (auto):** Everywhere it hangs. Measured at HEAD: seven scripts loop forever on `CLAUDE_PROJECT_DIR=a/b`, five of them on SessionStart or Stop. Same defect, same two-line fix, and fixing it in place is smaller than recording six more findings.

## Q2 — Scope boundary: what stays out
**Q:** Is the CDPATH-relative `cd` in non-test production scripts in scope?
**A (auto):** No. The R4 prologue clears CDPATH for a test and everything it starts. A developer running a production script by hand with a CDPATH set is recorded as a finding.

## Q3 — Primary actor and trigger
**Q:** Who reaches the changed paths?
**A (auto):** Three actors. The Claude Code harness (SessionStart, Stop, PreToolUse hooks that walk to a root), a self-test run by the developer, the suite runner or a hook, and the sandbox gate run by its own test and by maintenance.

## Q4 — Happy path
**Q:** What does an ordinary session look like after 084?
**A (auto):** Identical. An absolute `CLAUDE_PROJECT_DIR` walks as before; an undeclared sync pushes and refreshes as before. Only relative start directories, declared sandboxes and test environments behave differently.

## Q5 — Data model
**Q:** Does 084 add persisted state?
**A (auto):** No. R2 and R3 are decided per run from the declared sandbox and `origin`'s URL; R4 is one line per test file.

## Q6 — Validation: what is "inside the sandbox" for a remote?
**Q:** How is `origin` judged against the sandbox?
**A (auto):** A plain path or `file://` URL, resolved physically (relative to the project root when relative) and compared by segment with spec 010's `_within`. Anything with a host (`https://`, `ssh://`, `git@host:`), and anything that does not resolve to an existing directory, is outside. Unknown means outside.

## Q7 — Validation: what makes a start directory absolute?
**Q:** `cd -P` or lexical?
**A (auto):** Physical for a relative value that exists (`CDPATH='' cd -P`, so CDPATH cannot steer it and `..` resolves correctly: amended after the adversarial review), lexical `$PWD/` prefix for one that does not. An absolute value is untouched. A fixed-point check (`dirname` returns its input) stops the loop as a second line of defence.

## Q8 — Four states: success
**Q:** What does success look like for each requirement?
**A (auto):** R1: the walk finds the same root as the absolute spelling, or reports "not inside a git repository". R2: a sandboxed commit with an in-sandbox bare remote is pushed as before. R3: a sandboxed run with `CLAUDE_TEMPLATE_DIR` inside the sandbox refreshes it as before. R4: every test is green with and without decoys.

## Q9 — Four states: error
**Q:** What does a visible error look like?
**A (auto):** R2: `committed <sha>, not pushed — origin is outside the declared sandbox` (no URL: one can carry a token). R3: `[note] template clone at <path> is outside the declared sandbox — used as-is, not fetched or fast-forwarded`. R4: the prologue test names the file and which of the seven names is missing or late. R5/R6: the gate's existing violation line, `<file>:<line> — runs template-autosync-hook.sh directly instead of through drive_hook`.

## Q10 — Four states: empty
**Q:** What if there is nothing to act on?
**A (auto):** A relative or absolute directory with no `.git` above it: `[skip] not inside a git repository`, exit 0, as for an absolute one today. A sandboxed run with nothing to commit never reaches the push decision.

## Q11 — Four states: loading
**Q:** Is there a loading state?
**A (auto):** Not visible. The relevant one is the opposite: a SessionStart hook that never returns is the stuck "loading" R1 removes. The test asserts termination within a bound.

## Q12 — Error semantics
**Q:** Does the sandbox push decision fail open or closed?
**A (auto):** Closed, for declared runs only, consistent with spec 010's interlock: an unresolvable remote is not pushed. The commit still exists, so nothing is lost; an undeclared run is untouched.

## Q13 — Authorization
**Q:** Who may run the hook outside `drive_hook` after R5?
**A (auto):** The Claude Code harness through `.claude/settings.json` (not scanned: the gate reads `scripts/`), and the hook's own test arms in `test-pipeline-hooks.sh` once they go through `drive_hook`. The gate's argued exclusion list does not grow.

## Q14 — Concurrency and ordering
**Q:** Any ordering concerns?
**A (auto):** One. The R4 line must come before the first `cd`, `pwd` or `dirname` use, because `CDPATH` acts at that `cd`. The prologue test checks the order, not only the presence.

## Q15 — Integration points
**Q:** What else reads these files?
**A (auto):** `test-validate-sync-sandbox-declarations.sh` greps the literal resolve line `DIR="${CLAUDE_PROJECT_DIR:-$PWD}"` in the sync (keep it verbatim), and pins the census of hand-spelled declarations (drops from one to zero). `CORE_SCRIPTS` gains the new test. `test-hook-channels.sh` lists the hook as an allowed file.

## Q16 — Edge cases: relative paths
**Q:** Which relative spellings must the walk handle?
**A (auto):** `a/b` with no repository above (terminates), `a/b` inside a repository above cwd (finds it, which the old walk missed), `.`, `..`, `./x`, and a name with a space.

## Q17 — Edge cases: remotes
**Q:** Which `origin` shapes are tested for R2?
**A (auto):** A bare repo inside the sandbox (pushed), a bare repo outside it (not pushed, outside bare unchanged), `file://` inside (pushed), an `https://` URL (not pushed, no network attempted), a missing path (not pushed), and a symlink inside the sandbox pointing outside (not pushed, judged physically).

## Q18 — Edge cases: test files
**Q:** What if a test file legitimately needs an inherited value?
**A (auto):** None does at HEAD: the seven files that mention `CLAUDE_PROJECT_DIR` set it per call or read it only to prove it was not leaked. A future test that needs one sets it explicitly after the prologue.

## Q19 — Non-functional limits
**Q:** Cost?
**A (auto):** R1 adds no process. R2 adds one `git remote get-url` and one `cd -P`, only on a declared run that committed. R4 adds one builtin per test. The prologue test's decoy pass runs three fast suites, under 60 s.

## Q20 — Acceptance criteria
**Q:** What is the measurable definition of done?
**A (auto):** Every changed walk terminates under `timeout 5` with a relative start; a sandboxed run leaves a bare remote and a template clone outside the sandbox byte-identical (same refs, same HEAD); every test file carries the prologue in order; the gate flags a hook run outside `drive_hook`; the full template suite is green.

## Q21 — Non-goals and assumptions
**Q:** What does 084 assume?
**A (auto):** Bash 3.2. The adversary is the next honest author of a self-test, as in 010 and 011, not someone obfuscating a call.

## Q22 — Reversibility
**Q:** How is it undone?
**A (auto):** Every change is a revert of this spec's commits. No state, no migration.

## O1 — F017: refuse syncing the repository the script lives in?  (overflow — developer)
**Q:** Should `template-autosync.sh` refuse when the resolved project root is the repository the running script lives in?
**A:** Decline, record why. The production hook runs `<project>/scripts/template-autosync.sh` against `<project>`, which is exactly that shape, so the refusal would stop every project's sync. The route F017 worried about (an undeclared test inheriting `CLAUDE_PROJECT_DIR`) is closed by R4 and R5 instead. F017 closes with this reason.

## O2 — F019: unknown wrappers  (overflow — developer)
**Q:** Invert the run rule (anything not known to be a non-runner counts as a run), or extend the wrapper list and keep the residual named?
**A:** Extend the wrapper list with option arity (chronic, unbuffer, flock, runuser, taskset, chrt, numactl, strace, ltrace, valgrind, firejail, systemd-run; `watch` and `su -c` as code) and keep an unknown wrapper as a named residual. The inverted rule was measured at 130 new hits and no real run on the current tree.

## O3 — Template clone outside a declared sandbox  (overflow — developer, threat surface)
**Q:** When a sandboxed run finds its template in a clone outside the sandbox, should it use it read-only or refuse?
**A:** Use it read-only and say so: no fetch, no fast-forward on a clone outside the sandbox, one `[note]` line. A clone inside the sandbox refreshes as today.

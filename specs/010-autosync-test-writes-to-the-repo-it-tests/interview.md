# Spec interview — 010-autosync-test-writes-to-the-repo-it-tests

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO (base auto-answered with recommended; genuinely-ambiguous escalated; overflow human-answered if flagged).

Hardened row, so overflow is required. The four design questions a hardened spec escalates (fail-closed
reach, the gate's blast radius, scope by measurement, and the shape of the exemption) were answered by
the developer on 2026-09-01 in consultpilot H7bm, for this same change to this same file. They are
carried over below as Q16–Q19 with their original answers instead of being asked a second time. Q20
is the one overflow question this landing raises that H7bm did not have.

## Q1 — Scope boundary
**Q:** Is this a new design or a landing of consultpilot H7bm?
**A (auto):** A landing. The design, the threat model and the adversarial fixes (`/` refused, `exec`/backtick seen) come from `95ba64a`. The template-specific work is re-measuring against this tree.

## Q2 — Scope boundary
**Q:** Does it include the `drive_sync` helper (consultpilot H7bo)?
**A (auto):** No. That is row 011. Porting it here would work two register rows in one spec.

## Q3 — Primary actor & trigger
**Q:** Who is protected, and against what trigger?
**A (auto):** Every project that receives these self-tests. The trigger is a gate run from a hook (Stop, SessionStart, maintenance) with `CLAUDE_PROJECT_DIR` exported to the real repository.

## Q4 — Happy-path outcome
**Q:** What does success look like?
**A (auto):** With the variable exported to a real repo, every driver passes and that repo is byte-identical afterwards. If a driver regresses to `cd`-only, the sync refuses before it writes, and the gate names the file and line.

## Q5 — Data model
**Q:** What carries the declaration?
**A (auto):** One env var, `CLAUDE_TEMPLATE_SYNC_SANDBOX`, holding a directory path. It is the only channel a shell caller and a shell callee already share, and it matches the `CLAUDE_*` family.

## Q6 — Validation rules
**Q:** Which declarations are accepted?
**A (auto):** An existing directory other than `/`, whose physical path contains the physical project root segment-wise. A missing path or `/` is refused. Empty was first auto-answered as "undeclared" (consultpilot's choice) and was changed to a refusal after the adversarial review: a driver whose `mktemp` failed would otherwise run unguarded.

## Q7 — The four observable states
**Q:** Success, error, empty and loading for a shell interlock?
**A (auto):** Success: silent, the run proceeds unchanged. Error: `[refused]` naming the declared and resolved paths, exit 1. Empty (unset): exactly the old behaviour; set-but-empty is a refusal. Loading: N/A (synchronous).

## Q8 — Error semantics
**Q:** Recoverable or fatal?
**A (auto):** Fatal for that run, and the message says how to fix it: pass `CLAUDE_PROJECT_DIR` explicitly. There is no retry and no fallback.

## Q9 — Authorization
**Q:** Who may set the declaration, and does setting it grant anything?
**A (auto):** Anyone who controls the process environment. It can only narrow what the sync touches, so nobody gains a capability by setting it.

## Q10 — Concurrency / ordering
**Q:** Where in the run does the check sit?
**A (auto):** Once, right after `PROJECT_ROOT` is resolved and before the `.claude/` check, the stamp read, and any write. An interrupted run is interrupted inside the sandbox.

## Q11 — Integration points
**Q:** Which production callers are touched?
**A (auto):** `core-owed-tick-guard-hook.sh` gains `CLAUDE_PROJECT_DIR="$ROOT"` on both queries. `template-autosync-hook.sh` already passes it and declares nothing, which is correct because its target is the real repo.

## Q12 — Edge cases
**Q:** Which path edge cases must be covered?
**A (auto):** macOS `/var` vs `/private/var` (compare physical paths), a shared-prefix sibling, root equal to sandbox (accepted), a relative declaration (resolved from cwd), empty, missing, and `/`.

## Q13 — Non-functional limits
**Q:** Cost?
**A (auto):** Two `pwd -P` subshells, only on declared runs. Nothing on undeclared runs, and nothing on `--is-core`, which runs before every edit.

## Q14 — Acceptance criteria
**Q:** What is the load-bearing acceptance test?
**A (auto):** AC-2: all six drivers pass with `CLAUDE_PROJECT_DIR` exported at a throwaway clone of this repo, and the clone stays byte-identical. AC-1 is the contained reproduction flipping from "2 files written" to `[refused]`.

## Q15 — Non-goals & assumptions
**Q:** What is explicitly not done?
**A (auto):** No timeout tuning, no history rewrite, no change to how `PROJECT_ROOT` is resolved, no project `run-gates.sh` registration (row 014).

## Q16 — Reversibility / fail-closed posture  *(overflow — developer answered 2026-09-01, consultpilot H7bm Q16)*
**Q:** The file fails open by design. How far does the interlock's fail-closed exception reach?
**A:** Only when a sandbox is declared. Unset leaves today's fail-open behaviour untouched, byte for byte. A declared sandbox that does not contain the resolved root aborts before any write, stage, commit or push, with exit 1. Heuristic refusals and warn-without-abort were both rejected.

## Q17 — Blast radius of the gate  *(overflow — developer answered 2026-09-01, consultpilot H7bm Q17)*
**Q:** Touch all six drivers, including those that already name their target?
**A:** All six, uniformly. The gate demands both halves of every script, with no grandfather list.

## Q18 — Scope by measurement  *(overflow — developer answered 2026-09-01, consultpilot H7bm Q21)*
**Q:** Census by invocation or by variable name?
**A:** By invocation. `test-template-clone-refresh.sh` is not a driver (it extracts one function and passes the target as an argument). `test-core-owed-tick-guard.sh` is a driver. Record the exemption and the reason for it.

## Q19 — The exemption's shape  *(overflow — developer answered 2026-09-01, consultpilot H7bm Q22)*
**Q:** Must `--is-core`-only callers declare?
**A:** No. They are exempt because `--is-core` returns above the resolution, and a test asserts that ordering. If the ordering changes, the exemption stops applying without anyone editing a list.

## Q20 — Clobber on landing  *(overflow — judged; no developer decision needed)*
**Q:** consultpilot holds a newer local gate (H7bo) under the same two filenames. Once they are CORE, its next sync replaces them with this version. Is that acceptable?
**A (auto):** Yes, recorded as a finding for row 011. consultpilot's six drivers were already clobbered back to the template's bytes, so its local H7bo gate fails today. The landing moves it to a consistent H7bm state, and `drive-sync.sh` stays project-local until 011 ships it.

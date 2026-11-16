# 100 — kill surviving mutants, second pass

Track: spec-only. No hardened trigger: test fixtures and equivalence markers on existing lines, no
new trust boundary, entity, state machine or external surface. No `.allium`, no `/tla`.
Findings: F123 F124 F125 F129 F136 F138 F150 F151 F152 F160, verbatim in `specs/FINDINGS.md`.

## Problem

H4, H5, 090, 091 and 095 each left survivors outside the lines they changed, and every checkpoint
since has re-reported some of them. One cause stands out (F151): the guard suites read a hook's JSON
but not its exit code on allow paths, so an `exit 0`→`exit 1` mutant on any allow or fail-open
notice path survives. Exit 1 is a non-blocking error the CLI shows on stderr, and on a notice path it
throws the additionalContext away.

## Line map (by content, to the tree at 98ab21a)

| Finding | Module | Then | Now |
|---|---|---|---|
| F123 | template-autosync.sh | 364 883 2880 3818 | 367 886 2991 3929 |
| F150 | template-autosync.sh | 453 1875 2085 2951 3790 3983 | same |
| F124, F138 | project-maintenance.sh | 175 (=236 at 092) 639 983 1434, timeout 1091 | 237 703 1051 1523, 1159 |
| F125 | bash-write-guard-hook.sh | 451 530 | same |
| F151, F152, F136 | trust-anchor-guard-hook.sh | 47 87 101, 91 (091) | 56 109 123, 113 |
| F151, F152 | core-owed-tick-guard-hook.sh | 91 220 266 | 94 239 (rewritten by 098 R3) 286 |
| F151 | core-machinery-guard-hook.sh | 74 114 | 78 124 |
| F136 | cloud-maintenance.sh | 152 155 190 196 | same |
| F160 | guard-lib.sh | 86 459 | 90 447 |
| F160, F129 | spec-interview-guard-hook.sh | 68 90; resolver branches 280–353 | 68 82 90 98; 290–365 |
| F129 | destructive-command-guard-hook.sh | 41 86 | same |

Modules outside the default target table (trust-anchor, core-owed-tick, core-machinery,
bash-write-guard, cloud-maintenance) are measured through a `MUTATION_TARGETS` file, as H5 and H6 did.

## Requirements

- **R1 — Allow cases assert exit 0 (F151).** The run helpers of test-core-owed-tick-guard.sh,
  test-core-machinery-guard.sh and test-settings-edit-guard.sh, and the bare `hook_verdict "$OUT"`
  reads in test-trust-anchor-guard.sh, capture the hook's exit code and pass it to `hook_verdict`, so
  every expected `none`/`allow`/`deny` also means exit 0.
- **R2 — Every mapped site is killed or marked.** Each surviving site on the lines above gets a case
  in the suite that already owns the behaviour, labelled `[100]` with its line, or a
  `# mutant-equivalent: <reason>` marker whose reason holds when the mutant is applied by hand.
- **R3 — No production behaviour change** beyond the smallest one that makes a line's intent
  testable, recorded here if it happens.
- **R4 — Re-measured, not assumed.** The same `--lines` run after R1–R2: ≥ 95%, no timeout counted
  as a kill. Any site left alive is a finding with its reason.

### R3 as built

One line changed shape, with the same behaviour: bash-write-guard-hook.sh:451 drops `[ -n "$src" ] &&`,
because `[ -f "" ]` is already false. A marker would have hidden that line's two killable sites. The
same move at trust-anchor-guard-hook.sh:109 was undone in favour of a marker, because there the `-f`
saves a glob walk on every write to a file that does not exist yet (the settings-edit-guard :127
twin is written the same way).

## Non-goals

Fresh sampling; F171 and F195 (open, not on this row; F195 shares trust-anchor :123 and is reported
when that line is killed); widening the nightly target table.

## Clarifications

### Session 2026-11-16 (auto-picked, recommended option)

- Q: The baseline measures every site on a mapped line, not only the cited operator. Kill all of
  them? → A: Yes. A line is re-measured whole; a sibling survivor on the same line is in scope.
- Q: A line whose role was rewritten (core-owed-tick :220 → the 098 R3 block)? → A: Measure the line
  that carries the role now (:239, the exit after the missing-sync branch).
- Q: Seed? → A: `--lines` measures every site, so the seed only labels the run: 20261116.
- Q: Does R1 belong in hook-verdict.sh? → A: No. The helper already takes the rc (092 R2); the gap
  is the callers.

# 109 — mutation tooling

Track: spec-only. No new entity, state machine or external surface. The runner
(`scripts/run-mutation-gate.sh`) is template-only and never ships. The portability check ships to
projects, but it only adds a check. Not hardened: no risk domain, no new trust boundary (the Python
mutants run in the sandbox the bash mutants already use). Findings: F171, F179, F194, F195, F216,
F226, F227, F230, F231, verbatim in `specs/FINDINGS.md`.

## Problem

| Finding | What is wrong today |
|---|---|
| F227 | `# mutant-equivalent:` skips a whole line. `template-autosync.sh` marks two equivalent `&&`→`\|\|` on its `[reverted]` gate line, and that hides three sites the arms suite kills (M47–M49) from the gate. |
| F226 | `--lines M:N` exits 2 ("no mutable site") when line N carries only marked sites, so a re-measure after marking has to drop those lines by hand. |
| F231 | The runner mutates bash operators only. The Python guard modules (`settings_guard.py`, `sensitive_paths.py`, `shell_glob.py`, `bash_write_targets.py`) have no mutation gate. Spec 101 measured them with a hand pass of 11 mutants. |
| F216 | agentcrm's own `scripts/mutation-gate.sh:242` runs `find -newermt "@<epoch>"`, which BSD find cannot parse. The file belongs to agentcrm, not the template, so the template cannot fix it there. What it can do is make the portability gate it ships to every project catch the construct. |
| F171, F179, F194, F195, F230 | Surviving mutants from the 2026-10-03/04 maintenance samples, the H6 checkpoint (seed 6) and the 2026-11-16 sample, in `template-autosync.sh`, `project-freshness.sh`, `project-maintenance.sh`, `validate-scenario-traceability.sh`, `destructive-command-guard-hook.sh`, `hook-notice.sh`, `trust-anchor-guard-hook.sh`, `guard-lib.sh` and `settings-edit-guard-hook.sh`. |

## Requirements

- **R1 — Per-site markers (F227).** `# mutant-equivalent[<sel>,<sel>...]: <reason>` skips only the
  sites on that line that a selector names. A selector is a site's original text as the report
  prints it (`&&`, `-z`, `exit 1`, `return 0`) or a class name (`boolean`, `string_test`, ...), with
  an optional `#<n>` that picks the n-th site with that text on the line, counting from 1 left to
  right. The bare `# mutant-equivalent: <reason>` still skips the whole line. A selector that names
  no site on its line is an error (exit 2, the line is named): a stale marker hides nothing, and the
  runner says so. The `template-autosync.sh` `[reverted]` gate line becomes `[&&]`, which puts
  M47–M49's three sites back in the gate.
- **R2 — `--lines` passes over marked lines (F226).** A requested line whose every site is marked is
  reported on stderr as `<module>:<n>: marked, skipped` and dropped from the request. A line with no
  site at all is still exit 2. When nothing is left to measure after the drop, exit 2
  (`nothing to measure`): an empty run is not a pass (mutation-timeouts.md Trap 4).
- **R3 — Python mutants (F231).** A module ending in `.py` is read with Python's `tokenize`, so
  strings, comments and docstrings are never mutated. Classes: `py_compare` (`==`↔`!=`, `<`↔`>=`,
  `>`↔`<=`, `in`↔`not in`, `is not`→`is`), `py_boolean` (`and`↔`or`), `py_const` (`True`↔`False`).
  Markers work the same way (R1), with a `#` comment on the line. The four guard modules join the
  default target table with the suites that drive them.
- **R4 — BSD find in the portability gate (F216).** `portability_audit.py` flags `-newer[acmB]t`
  with an `@`-epoch operand (`-newermt "@$x"`, `-newermt @123`). That form is GNU only; BSD find
  stops with "Can't parse date/time". The advice is the portable form: a reference file (`touch -t`)
  plus `-newer`. A relative date (`-newermt "-24 hours"`) is not flagged, because both finds read it.
  The status summary tells the developer about agentcrm, and the template does not touch its file.
- **R5 — Kill the cited survivors.** Every survivor named in F171, F179, F194, F195 and F230 is
  re-measured against today's code: with `--lines` where a finding names lines, and with the
  finding's seed where it names only a module. A survivor that still lives is either killed by a
  test or marked equivalent per site with its reason (R1). A finding whose line moved is re-found by
  content. A timeout is re-run on its own before it is counted either way (mutation-timeouts.md
  Trap 2). `hook-notice.sh` and `trust-anchor-guard-hook.sh` join the default table.
- **R6 — Tests.** `test-run-mutation-gate.sh` gains arms for R1 (a per-site marker leaves the other
  sites mutable; a stale selector is exit 2), R2 (a marked line is skipped and named; an all-marked
  request is exit 2) and R3 (a Python module's mutant is killed; text in a string or comment is not
  a site), plus a sabotage mutant per arm that turns it red. `test-portability-audit.sh` gains R4
  cases, both flagged and not flagged.

### As built

- **The Python classes go last in `CLASSES`.** The first live run drew no Python mutant at all,
  because the sampler walked only the bash classes. Appending keeps every old bash seed
  reproducible: shuffling an empty list draws nothing from the RNG.
- **R5 re-measured 56 sites with `--lines`** (the cited lines found by content, plus the 14 survivors
  of the 2026-11-17 sample): 24 killed at HEAD. After the tests, 43 of 45 were killed, and the last
  two (`project-freshness.sh:94,96 return 1`) are equivalent: `ensure_trufflehog`'s one caller
  re-asks `command -v` and never reads the status. Nine sites are newly marked per site with their
  reason (plus the `[reverted]` line converted to `[&&]`). Each is a status nobody reads, or
  `_clone_inside_sandbox`'s unreachable not-a-repo branch.
- **F171 and F179 name modules, not lines.** Their samples cannot be redrawn: the files changed since,
  so seed 20261004 draws other lines today. The full table at that seed (Python included) scored
  153/180 = 85.0%, above the break. Its one survivor on a line this spec had touched
  (`hook-notice.sh:158`, an empty stamp) was killed. The other 26 are a fresh sample, recorded as
  F284 (bash) and F285 (the Python modules' first gated run), not rowed (carve-budget.md).
- **Two findings named the wrong line or cause.** F194's `:159` is the "cannot record" `mkdir`
  branch, not the no-hasher one (both now have a test). The spec-interview survivor at `:121` is the
  no-register exit, not the outside-git one.
- **Two sabotage anchors in `test-run-mutation-gate.sh` (S13, S15) had been stale since spec 098**
  replaced the env denylist with an allowlist. Re-anchored on the `env -i` line, so all 21 now go red.
- **Weak assertions found on the way.** The npm-count and trufflehog-reason checks passed whatever
  the scrape did, because npm's raw table and trufflehog's raw log line already carry the text. K30
  pins the SUMMARY line and a JSON-shaped trufflehog error instead.

## Recorded bounds

- The Python operators are a starter set, sized like the bash ones. Arithmetic, slicing, return
  values and exception mutants stay out until a survivor class asks for them.
- The default sample stays 12 per module. Python modules share it, so the 2000-line
  `settings_guard.py` is sampled as thinly as `template-autosync.sh`.

## Non-goals

- Editing agentcrm's `mutation-gate.sh`. It is that project's own file, so it is reported, not fixed.
- A Stryker-style HTML report for the Python modules. The JSON report already takes them.
- Changing the break (80%) or the sample size.

## Clarifications

### Session 2026-11-17 (auto-picked, recommended option)

- Q: Does a per-site selector count across the whole line or only inside code? → A: Only sites the
  runner would mutate. Text in quotes or comments is never a site, so it is never counted.
- Q: Should a class-name selector be allowed next to operator text? → A: Yes. `[boolean]` reads
  better than `[&&,||]` when every boolean site on a line is equivalent for one reason.
- Q: When a Python module and a bash module share a test, is the baseline run twice? → A: Yes, once
  per (module, test) pair, as today. Merging pairs saves seconds and would change the baseline
  contract.
- Q: Is a re-measure that finds a survivor already dead a finding? → A: No. It is recorded in the
  run log with the line, and the finding is closed against this row.

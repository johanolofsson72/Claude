# 101 — guard parser dedupe

Track: spec-only. No hardened trigger: three guards keep their verdicts while one copy of a rule
replaces two. No new trust boundary, entity, state machine or external surface. No `.allium`, no
`/tla`. Findings: F132 F153 F154, verbatim in `specs/FINDINGS.md`.

## Problem

Three rules exist twice, and a fix to one copy leaves the other behind.

- **F153.** Two parsers decide whether a sed script is "pure". `shell_glob.sed_script_kind` (spec 095)
  serves settings-edit and bash-write. `sensitive_paths._SED_PURE` plus `sensitive_paths.sed_scripts`
  (spec 090) serve sensitive-file. The regex accepts exactly one `s`/`y` with a numeric address, and
  the argument walker is a second reading of sed's options (`-i ''` only, no `-i .bak`, no long-option
  prefixes).
- **F154.** `settings_guard._bash_verdict` sets `by_name` once per line. One `find`, `fd`, `xargs`,
  `rsync`, `tar` or `zip` anywhere turns bare-name matching on for every command on the line, so
  `find . -name x; cp a settings.json` judges the `cp` by name. `pattern_indices` makes up for it by
  special-casing grep/rg patterns.
- **F132.** `scripts/sync-prompt.md` Step -1 decides "is this clone ours to fetch" with the unanchored
  `*johanolofsson72/Claude*`. Spec 091 R1 anchored the same question in `template-identity.sh`
  (`template_url_matches`), and `template-autosync.sh` already uses that.

## Requirements

- **R1 — One sed walker (F153).** `shell_glob` walks sed's words once and exposes the pairs
  `(word, script)`, -e scripts included when -f is also given. `sed_args` is built on that walk with
  its return shape unchanged. `sensitive_paths` drops `_SED_PURE` and its own `sed_scripts`: a script
  is pure when `sed_script_kind` returns a kind (no `r R w W e`, nothing the parser cannot read).
- **R2 — Sensitive-file keeps every deny (F153).** Every case in `test-sensitive-file-guard.sh` keeps
  its verdict. When `shell_glob` cannot be imported, sensitive_paths splits the command plainly, the
  way it already does without `destructive_command.py`: stricter, never looser.
- **R3 — by_name per simple command (F154).** Name matching that comes from a cd or `-C` target
  nobody can follow, or one into a guarded directory, stays line-wide, as before. Name matching that
  comes from a tree command applies only to that command's own words and redirect targets.
  `pattern_indices` handles only `xargs grep|rg`, the one place a tree command carries a grep pattern.
- **R4 — Step -1 uses template_url_matches (F132).** The block sources
  `$TEMPLATE/scripts/template-identity.sh` and compares origin's raw configured URL
  (`git config --local --get remote.origin.url`, before insteadOf). A clone without the library is
  older than spec 091: the block warns that it is not refreshing it and uses it as it is. It never
  fetches a clone whose URL fails the anchored match.
- **R5 — Tests.** `test-sync-prompt-bootstrap.sh` runs the block against a fixture origin spelled
  `https://github.com/johanolofsson72/Claude.git`, redirected with `url.<bare>.insteadOf` in the fake
  HOME, plus an `evil-johanolofsson72` clone and a clone without the library, neither fetched. Each
  R1–R3 behaviour change gets a labelled `[101]` case in the suite that owns it.

### As built

- `shell_glob.sed_walk` was missing one rule the old sensitive walker had: after `--` the first operand
  is still the script. Before, `sed -i -- 's/a/b/' f` gave settings-edit and bash-write the script as a
  file (stricter there, but wrong). Fixed in the shared walk.
- Measured by hand. `run-mutation-gate.sh` mutates bash operators only, and this change is Python
  plus a markdown block. Out of 11 targeted mutants on the changed lines, 10 were killed. One is
  equivalent and marked at `settings_guard.pattern_indices`. The `-f` plus `-e` survivor got a
  settings-edit case. The old Step -1 block fails the new evil-owner and pre-091 cases (measured).

## Non-goals

`find -exec grep PATTERN` (a pattern behind `-exec` is still read by name, as today); the test
harnesses' own `*johanolofsson72/Claude*` self-detection (they ask "am I the template", not "may I
fetch"); widening what sensitive-file treats as a path.

## Clarifications

### Session 2026-11-16 (auto-picked, recommended option)

- Q: Is a sed "print" script (`/re/p`, `$d`) pure for sensitive-file, or only s/y? → A: Pure. It
  opens no file. Its regex address is a pattern, the same as an `s` pattern.
- Q: With `-f prog`, do `-e` scripts still count? → A: Yes. The pairs carry them, so `-f p -e 'r .env'`
  still splits `r .env`. `sed_args` keeps returning None for its two callers.
- Q: Where do redirect targets of a tree command get by_name? → A: In that command only. `find . >
  settings.json` matches by name, `find .; echo > settings.json` does not, unless a cd turned it on.
- Q: Pre-091 clone in Step -1: fetch with the old pattern, or skip? → A: Skip with a warning. That is
  what `template-autosync.sh` does when the library is missing (fail closed).

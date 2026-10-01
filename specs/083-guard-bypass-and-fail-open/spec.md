# 083 — guard bypass and fail-open

Track: full, hardened (register tag; also the risk domain: the PreToolUse guards are the
enforcement boundary between the model and the developer's files, credentials and git remote).
Findings: F029 F035 F038 F039 F040 F041 F042 F044, verbatim in `specs/FINDINGS.md`.

## Problem

The PreToolUse guards are the only enforcement in the harness that the model cannot argue with.
H1's adversarial pass showed that several of them can be walked past without trying very hard:

- **F044.** Every guard reads its payload with `jq`. With `jq` missing, `FILE` comes back empty and
  the guard exits 0, so nearly every guard allows silently. The deny itself is printed by `jq -n`,
  so even a guard that reached a deny prints nothing. `pipeline-state` and `spec-interview` run their
  resolver through `python3` and allow on any exit they did not expect, including 127 (no python3).
  `bash-write-guard` allows on a jq failure (`:103`) and on an extractor failure (`:260`), and
  neither is documented. Nothing tells the developer.
- **F039.** The sensitive-file guard is an inline hook on `Read|Edit|Write` only. `Bash cat`, Grep,
  Glob and NotebookEdit pass. Its regex wants a leading `/`, so a relative `.ssh/config` passes.
  `.netrc`, `.npmrc`, `.kube/` and `.gnupg/` are not listed. Above 4096 bytes it skips the precheck
  and, without jq, fails open.
- **F040.** `core-machinery-guard` computes the project-relative path by string prefix without
  normalising, so `/proj/x/../scripts/<core>.sh` or `/proj//scripts/<core>.sh` is judged not-CORE.
  A relative `file_path` finds no `.git` and allows. The other guards share the walk.
- **F041.** The three pipeline guards exempt any path containing `*/scripts/*`, `*/specs/*` or
  `*/.claude/*`. A web project's `src/scripts/app.js` skips the pipeline gate entirely.
- **F042.** `core-owed-tick-guard` recognises a tick by `- [x]` at line start in the written
  strings. An Edit whose `old_string`/`new_string` begin at `[ ]`/`[x]`, with the `- ` outside them,
  ticks the row unseen.
- **F035.** `cp $TEMPLATE/scripts/x scripts/x` hands `core-machinery-guard` a path and no bytes, so
  a byte-identical install through the shell is denied even though the same Write passes.
- **F038.** The `permissions.deny` list (`Bash(rm -rf *)`, `Bash(git push --force*)`, …) matches
  by prefix. Under `bypassPermissions` + `allow: Bash`, `rm -r -f`, `/bin/rm -rf`, `git push -f`,
  `git clean -fd` and `find … -delete` all pass.
- **F029.** The guard tests read stdout and ignore the exit code. The CLI honours stdout JSON only
  on exit 0, so a guard that prints a well-formed deny and exits 1 passes every suite and blocks
  nothing. `test-hook-channels` §13 pins this for one guard.

## Requirements

- **R1 — One guard library (F044, F040).** `scripts/guard-lib.sh`, sourced by every PreToolUse
  guard this spec touches, provides:
  - `guard_field <dotted-path>`: reads a string field from `$INPUT` with `jq`, else `python3`.
    Exit 0 with the value (possibly empty), 3 when no parser is available, 4 when the payload is
    not a JSON object.
  - `guard_deny <reason>` and `guard_context <text>`: print the PreToolUse JSON with
    `hookEventName`. They work with `jq`, without `jq` (via `python3`), and with neither (a
    bash JSON string escaper). They never print nothing.
  - `guard_canon <path> [cwd]`: absolute path with `.`, `..` and repeated `/` resolved; the deepest
    existing ancestor directory is resolved physically (`cd -P`), the rest lexically. A relative
    path is resolved against `cwd`, else the payload's `.cwd`, else `$PWD`.
  - `guard_parser_state`: `jq`, `python3` or `none`.
- **R2 — Fail-closed class (F044).** `spec-register-guard`, `pipeline-state-guard` and
  `spec-interview-guard` deny when they cannot decide about a payload whose raw text names a
  source-extension path: no parser (R1 exit 3), an unparseable payload (exit 4), `python3` missing
  for the resolver (rc 126/127), or any resolver exit outside the ones the guard defines. Each deny
  names its cause and the repair, and says that `scripts/**`, `specs/**` and `.claude/**` at the
  project root stay editable.
- **R3 — Fail-open class, announced (F044).** `core-machinery-guard`, `core-owed-tick-guard` and
  `bash-write-guard` keep failing open (their rationale stands: they protect template-owned files or
  sit in front of every Bash call). When they cannot decide they now say so with
  `additionalContext` naming the guard and the cause. Never silent. The deny they reach is printed
  through `guard_deny`, so it no longer depends on `jq`.
- **R4 — Canonical paths (F040).** All five Edit-path guards (`spec-register`, `pipeline-state`,
  `spec-interview`, `core-machinery`, `core-owed-tick`) canonicalise `file_path` with
  `guard_canon` before any pattern, walk or prefix test. `x/../scripts/<core>.sh`,
  `//scripts/<core>.sh`, `./scripts/<core>.sh`, a relative path and a path through a symlinked
  directory all reach the same verdict as the plain absolute path.
- **R5 — Anchored exemptions (F041).** The directory exemptions of the three pipeline guards apply
  only at the project root: `<git-root>/{scripts,specs,.specify,.claude}/**` and the same four under
  the directory holding the active register when that differs. Name exemptions (`CLAUDE.md`,
  `README*`, `.env*`, `Dockerfile`, …) match the basename only. `src/scripts/app.js` is judged like
  any other source file.
- **R6 — A tick is a row that becomes `[x]` (F042).** `core-owed-tick-guard` applies the Edit,
  MultiEdit or Write to the current register (same split/join semantics as `core-machinery`) and
  counts a tick when some row id is `[x]` in the result and was not `[x]` before. Rewording an
  already-ticked row is not a tick. When the result cannot be computed (no file, `old_string` absent,
  no `python3`), any `[x]` in the written strings counts as a tick: the conservative reading.
- **R7 — Byte-identical cp passes (F035).** For a `cp` with exactly one source operand that is a
  regular, readable file, `bash-write-guard` hands `core-machinery-guard` the source's bytes as
  `content`, so the byte-identity check of spec 039 applies. Any other `cp`/`mv` shape keeps the
  path-only payload and its deny.
- **R8 — Exit-code discipline (F029).** Every PreToolUse guard wired in `.claude/settings.json`
  exits 0 whenever it prints a decision, and never exits 1. A new test runs every wired guard script
  against deny and allow fixtures and asserts rc 0 plus parseable JSON carrying `hookEventName`
  whenever stdout is non-empty.
- **R9 — Destructive-command guard (F038).** `scripts/destructive-command-guard-hook.sh` on `Bash`
  tokenises the command (quotes honoured, `sh|bash|zsh -c` bodies recursed one level, `$(…)` and
  backtick bodies scanned) and denies:
  - `rm` with a recursive flag (`-r`, `-R`, `--recursive`) and a force flag (`-f`, `--force`) in
    any spelling or order (`-rf`, `-fr`, `-r -f`, `-Rf`), invoked as `rm`, `/bin/rm`, `\rm`,
    `command rm`, or behind `sudo`/`env`/`xargs`/`nohup`/`time`/`exec`;
  - `sudo`, `doas`, `su` or `pkexec` as a command word;
  - `git push` with `-f`, a short-flag cluster containing `f`, `--force`, `--force-with-lease…`,
    `--force-if-includes`, or a `+`-prefixed refspec; `git reset --hard`; `git clean` with `-f` in
    any cluster or `--force`. Git global options (`-C`, `-c`, `--git-dir=`, `--work-tree=`,
    `--no-pager`) are skipped before the subcommand;
  - `find` with `-delete`, or `-exec`/`-execdir`/`-ok` running `rm`.

  Text inside a quoted argument to a non-shell command (`git commit -m "rm -rf x"`) is not a
  command. The settings deny list stays as the first layer. The declared bound (variables, `eval`,
  aliases, scripts, interpreters) is written in the hook and in `.claude/docs/security.md`. There is
  no override variable, matching the deny list; the reason tells the model to ask the developer to
  run the command with `!`.
- **R10 — Sensitive-file guard as a script (F039).** `scripts/sensitive-file-guard-hook.sh` replaces
  the inline hook, on `Read|Edit|Write|MultiEdit|NotebookEdit|Grep|Glob|Bash`. It checks
  `file_path`, `notebook_path`, Grep/Glob `path`, Glob `pattern`, and each shell token of a Bash
  command (split on `=` and redirections). A path is sensitive when a segment is `.ssh`, `.aws`,
  `.azure`, `.kube` or `.gnupg`; when it ends in `.docker/config.json` or contains `.config/gh/`;
  or when its basename is `.git-credentials`, `.netrc`, `.npmrc`, `.env` or `.env.<suffix>`, except
  `.env.example`, `.env.sample` and `.env.template` (O1). Also `.envrc`, `.pgpass`, `.pypirc` and
  `.config/gcloud/` (review #15). Names are case-folded, brace and dot-glob segments count, and the
  Bash scan reads executed bodies (`sh -c`, `eval`, `$(…)`, a heredoc or pipe into a shell). With or
  without a leading `/`, at any payload size. A payload that names a sensitive token but cannot be
  parsed is denied. `sync-core-hooks.py` retires the template's two exact past texts of the inline
  hook in a project that has the script.
- **R11 — Missing parser announced once per session (F044).** The SessionStart orientation hook
  reports, before any early exit, when `jq` or `python3` is missing: which guards fall back, and
  that with neither the pipeline guards deny every source edit. Silent when both are present.
- **R12 — Docs.** `.claude/docs/security.md` says the deny list is a prefix match and names the
  guard as the floor with its bound. The guard rationale sections (fail-closed vs fail-open, the
  library) live in the hook headers. Humanizer pass on prose.

## Non-goals

- A shell parser. R9 recognises spellings, it does not evaluate. Variables, `eval`, aliases, a
  script that deletes, `python -c "shutil.rmtree(…)"` and `git -c alias.x=…` are outside it, as is
  every other destructive command not on the deny list (`dd`, `mkfs`, `git branch -D`).
- Read-side secrecy for the whole tree. `grep -r foo .` reads `.env` implicitly; R10 only sees
  paths that are named.
- Changing which guards fail open. R3 announces; it does not flip them.
- The mutation runner for the template (row 085). The hard mutation gate is met with sabotage arms,
  as 082 did.

## Threat model

Trust boundary: **model-issued tool call → developer machine**, crossed by every PreToolUse payload.
The attacker is a prompt-injected or careless model choosing a spelling the guard does not know.

### TB1 — tool payload → pipeline guards (R2, R4, R5)

- **Elevation (gate bypass).** A source edit skips the pipeline through `src/scripts/`, a `..`
  path, a relative path, or a machine without `jq`. *Mitigation:* R2, R4, R5. *Residual:* a source
  file deliberately placed under the root `scripts/` is exempt by design (the repair path).

### TB2 — tool payload → template-owned files (R3, R4, R6, R7)

- **Tampering.** A CORE file is edited through an unnormalised path, or a tick lands through a
  split Edit while CORE work is owed. *Mitigation:* R4, R6. *Residual:* both guards fail open when
  the sync machinery cannot answer, and now say so (R3).

### TB3 — Bash → filesystem and remote (R9)

- **Denial of service / data loss.** `rm -r -f`, `git push -f`, `git clean -fd`, `find -delete`.
  *Mitigation:* R9. *Residual:* the declared bound. The guard raises the cost of a careless or
  injected destructive command, and a determined program can still compose one.

### TB4 — tool payload → credentials (R10)

- **Information disclosure.** `cat ~/.ssh/id_rsa`, Grep over `~/.aws`, `Read .netrc`.
  *Mitigation:* R10. *Residual:* implicit reads by recursive tools, and paths built at runtime.

### TB5 — the harness → its own enforcement (R8, R11)

- **Repudiation / silent failure.** A guard that exits 1, or a machine with no `jq`, enforces
  nothing while every test is green. *Mitigation:* R8, R11.

### Adversarial review (2026-10-01)

`security-scanner` in assume-exploitable mode raised 15 findings by reading the code; every high one
was confirmed with a PoC before deciding. Fixed inside this spec: 1 and 2 (the cp source's bytes go
along only when the whole command is one plain `cp` with harmless flags), 3 (the outermost register
wins, so a planted nested one cannot stand in), 4 to 7 and 14 (comments only at word start, shell
keywords skipped, heredocs only outside quotes and fed to a shell anywhere on the line, text piped or
here-stringed into a shell is read, `$'…'` and backslash-newline normalised, quote-split words reach
the parser, `doas`/`su`/`pkexec`, more wrappers and shells, long-option prefixes, `find -exec sh -c`,
`git clean -n` allowed), 8 (executed bodies scanned for credential names, split names reach the
parser), 9 (the tick guard uses the resolver's `ROW_RE`), 10 (`.git` as a file is a root), 11 (final
symlink followed, `ln` judged as its target), 12 (`/bin/cp`, wrappers and `-t` detected), 13 for
the two floor guards (case folded), 15 in part (exact-name exemptions, `mts|cts|vb|ps1|groovy`, four
credential names, `grep "\.env"` no longer denied).

Recorded rather than fixed: F081 (no guard covers `.claude/settings.json`, a decision for the
developer), F082 (case folding for the five Edit-path guards), F083 (a symlink that already exists in
the tree and hides its target from a raw-text precheck), F084 (`git push --mirror/--delete`,
NotebookEdit on the pipeline guards, `.sql`/`.bat`), F085 (`sed 's/.env//'` false positive). F086
is unrelated: `test-stryker-guard.sh` S1 fails at HEAD on this machine.

### /security-review (2026-10-01)

Two findings, both 9/10 and verified against the hooks. 1: `guard_canon` walked `..` through a
symlinked directory physically, while the CLI's Write applies `..` as text, so `<proj>/lnk/../src/App.cs`
(lnk -> /var/empty) was judged outside the repo and allowed by all three pipeline guards. `..` is now
resolved as text before the physical walk. 2: the sensitive precheck sent `.s*` and `.n?trc` to no
parser; `?` and `*` now count. Both have regression arms.

### /tla (2026-10-01)

`GuardVerdict.tla` models guard class × parser × payload × path × resolver outcome and the CLI's
exit-code rule. TLC: 192 distinct states, `NoSilentAllow`, `FailClosedHolds` and `CliHonoursDeny`
hold; with `MODEL_EXIT_ONE = TRUE` (a guard that exits 1 after printing, F029) `CliHonoursDeny` is
violated, as it should be. GAP-1: the fail-open guards stayed silent when the sync's classifier
could not answer (exit 2 or timeout). The developer chose to fix it: both guards now announce.

## Clarifications

### Session 2026-10-01 (auto-pick, recommended answers)

- Q: Does `guard_canon` resolve a symlink in the final path component? → A: Yes (amended after the adversarial review, #11). A write through a link changes its target, so the target is judged, up to 8 hops. `ln` through the shell is judged as a write to its target, since the raw-text prechecks never see an existing link's target.
- Q: Does R9 look inside `bash -c '…'`? → A: Yes, one level. A `-c` body is tokenised as a command. Deeper nesting is in the declared bound.
- Q: Does R7 cover `cp -r`, several sources, or `mv`? → A: No. One source operand that is a regular file, and an optional set of flags without `-r`/`-R`/`-a`. Anything else keeps the path-only payload.
- Q: Where does R11 print? → A: At the top of `spec-register-orientation-hook.sh`, before its register lookup, so a project without a register still hears it.
- Q: Which fail-closed deny applies when a payload is over 4096 bytes and there is no parser? → A: The same R2 deny, decided by the source-extension regex on the raw payload. It is slower than the bounded precheck, but the case is rare.
- Q: Does R10 retire a project's own variant of the inline hook? → A: No. Only the template's two exact past texts. A project's edited copy stays, and it is harmless next to the script.

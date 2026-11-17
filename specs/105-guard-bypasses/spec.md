# 105 — guard bypasses

Track: full, hardened. Triggers: a security domain (the guards are the trust boundary between the agent
and the developer's decisions), the answer store behind the acceptance gate, and about twelve files.
Findings verbatim in `specs/FINDINGS.md`: F173, F174, F175, F176, F177, F178, F184, F186, F187, F188,
F189, F190.

Specs 098 and H6 found each of these. Most are a guard that lets a call through because the call takes
a shape the guard never parsed: a verb it does not list, a runner under a version suffix, a name handed
on through `$_`, a path whose `.git` is spelled by git itself. The rest are the oracles the guards trust
(PATH, git, the notice stamp, the answer store, the hook wiring), which the agent can reach or which do
not say when they are wrong.

## Problem

| Finding | Where | What goes wrong today |
|---|---|---|
| F184 | `trust-anchor-guard-hook.sh` `GIT_META`; `guard-lib.sh` walk | `rm -r .git` and `rmdir .git/x` pass every guard (only `rm -rf` and `find -delete` are denied). With `.git` gone the walk finds no root, and spec-register, core-machinery and core-owed-tick exit 0 in silence. Reproduced in H6 |
| F187 | `trust-anchor-guard-hook.sh` `shell_verdict` | `touch` and `mkdir` under `.git/claude-hook-notices/` pass. The stamp name is sha256 of fixed text plus the session id, so a literal path pre-plants the once-per-session stamp and silences the 098 notice and the 096 toast. Reproduced in H6 |
| F177 | same | A one-liner writing under `"$(git rev-parse --git-dir)"` names no `.git`, so the text rules miss it |
| F188 | `guard-lib.sh` `_guard_notice_base`, `harness-state-gc.sh` | The notice base follows an ancestor `.git` file into its git dir. trust-anchor protects only `CLAUDE_PROJECT_DIR/.git`'s target and paths with a `.git` component, and the gc sweeps only `<root>/.git/claude-hook-notices`. A package under a worktree or submodule whose git dir has no `.git` component keeps unguarded, unswept stamps |
| F176 | `guard-lib.sh` `_guard_git`, every guard | git, timeout, gtimeout, perl, python3 and jq resolve through PATH. A shim the agent writes into a user-writable PATH directory (`~/.local/bin`, `/opt/homebrew/bin`) answers for git, and no guard covers writes there |
| F189 | `template-identity.sh:38,41` | `git config` and `git rev-list` run with no timeout and no `GIT_*` scrub. core-machinery, core-owed-tick and guard-lib call it, so a hanging git stalls the guard |
| F174 | no check | An Edit that leaves a live PreToolUse guard unparseable (098: an unpaired backtick in trust-anchor's python heredoc) makes the hook exit 2 on every matched call. The agent is locked out of Edit/Write/Bash until the developer repairs it with `!` |
| F175 | `settings_guard.py` `runs_text`, `split_commands` | Runner detection misses `</dev/null bash f` (the input redirect's target is read as the command word), `python3.12`, `gawk`, `tcsh`, `rbash`, `flock`, `find -exec`, `make -f`, and a name handed on with no runner: `cat S; sed -i x "$_"`, `echo S >f; sed -i x $(cat f)` |
| F186 | `settings_guard.py` mod installer rule; `install-guard-notice-mod.sh` | The installer is recognised only as a whole word ending in `install-*-mod.sh`, so `bash -c 'scripts/install-guard-notice-mod.sh --target x'` passes: the nested re-judge runs only for program strings that name git or claude. The installer copies agent-editable mod source with no pin |
| F173 | `acceptance_cases.py` answer store | The store binds an answer to a digest only. Cases copied verbatim from a confirmed spec digest the same, so `--confirm` and the gate accept the new spec with no new question |
| F178 | `acceptance_cases.py` `check`, `_grandfathered` | `check` returns 0 for a Confirmed line no recorded answer backs. `_grandfathered` takes the newest commit adding `interview.md` in date order, so a backdated committer date on a re-created spec picks the old add |
| F190 | `hook_audit.py` | The matcher check (098 R8) reports a wrong matcher but not a guard that is never wired. A covering group in `settings.local.json` (one machine) hides an uncovered committed one. Wiring is detected by substring |

## Requirements

### The git dir

- **R1 (F184).** trust-anchor's git-dir verb rule (098's `bash-gitmeta`) also covers `rm`, `rmdir`,
  `unlink`, `shred` and `truncate`, and the verbs that create or link a path: `touch`, `mkdir`, `ln`,
  `install`, `cp`, `dd` (`of=`). Each is refused when a word names a path with a `.git` component.
  Defence in depth for the walk: when the walk finds no git boundary and `CLAUDE_PROJECT_DIR` holds the
  file, has no `.git` entry, and shows it is a project (`specs/INDEX.md` or `.claude/.template-sync`),
  `GUARD_GIT_UNSURE` is set to "the project root has no .git". The pipeline guards deny on it (098 R4).
  The CORE guards take `CLAUDE_PROJECT_DIR` as both roots, go on judging, and announce.
- **R2 (F187, F177).** trust-anchor refuses a shell command whose text names `claude-hook-notices`, and
  a command substitution (`$(…)` or backticks) that runs `git rev-parse` with `--git-dir`,
  `--git-common-dir`, `--absolute-git-dir` or `--git-path`: its value is the git dir's path, spelled
  without `.git`. Printing it (`git rev-parse --git-dir` alone) stays allowed.
- **R3 (F188).** `_guard_notice_base` keeps a stamp only in a git dir trust-anchor protects: a `.git`
  directory, the target of `CLAUDE_PROJECT_DIR/.git` when that is a file, or a `gitdir:` target whose
  resolved path has a `.git` component. Any other ancestor `.git` file means no stamp, so the notice is
  said every time. `harness-state-gc.sh` sweeps the base `_guard_notice_base` returns, not a fixed
  `<root>/.git/claude-hook-notices`.

### The guards' own tools

- **R4 (F176, developer O2).** trust-anchor refuses a write whose target's directory is on PATH, outside
  or inside the project: Edit, Write, MultiEdit, NotebookEdit and MCP paths, the shell writes
  bash-write-guard delegates (`>`, `tee`, `cp`, `mv`, `sed -i`), and the text forms `ln`, `install`, `rm`, `unlink`,
  `touch`, `chmod`, `cp`, `mv`, `rsync`, `ditto`, `dd of=` naming such a path (`~` and `$HOME`
  expanded, a relative path joined to the payload's cwd). A PATH directory is compared as spelled and
  as resolved, and one that does not exist yet still counts.
- **R5 (F189).** `template-identity.sh` runs git through one helper: `GIT_*` dropped (`GIT_GRAFT_FILE`
  set back to `/dev/null` for the root query), bounded by `GUARD_GIT_TIMEOUT` (default 5 s) with
  timeout, gtimeout or perl. No answer means `project` from `template_identity` (never an exemption)
  and `upstream` from `self_test_subject` (nothing skipped), as a missing library already does.
- **R6 (F174).** trust-anchor refuses an Edit, MultiEdit or Write of a `*.sh` or `*.py` under a
  `scripts/` directory when the bytes it would leave do not parse (`bash -n`, python `compile`) and the
  current bytes do. A file that is already broken, or new, can always be written. No bash or a check
  that times out is no verdict (allowed). The shell route carries no bytes and is the bound.

### Settings guard

- **R7 (F175).** In `settings_guard.py`:
  (a) an input redirect's operand (`< f`, `0< f`) is not a word of the command;
  (b) a runner name is compared with a trailing version stripped (`python3.12`, `perl5.30`, `bash5`)
  and the list gains `gawk mawk nawk tcsh csh rbash mksh ash yash lua tclsh expect pwsh make gmake`;
  `flock` and `watch` are wrappers; `find` with `-exec`, `-execdir`, `-ok` or `-okdir` runs text;
  (c) on a line where a command names a guarded file, a later command that does not read and carries
  a handed-on name (`$_`, `${_}`, outside single quotes) is a write of that file; so is one that
  carries a command substitution when the line also writes a file (a redirect to anything but
  `/dev/null|stdout|stderr|tty`). History expansion (`!$`, `!!`) is off in a non-interactive shell and
  is not counted (threat model #28). A simple `$( )` no longer makes the line unplain (098 R7), so
  `bash scripts/x.sh "$(pwd)"` next to a read is allowed; backticks stay unplain.
- **R8 (F186, developer O3).** Every program string handed to a shell (the operand of `-c` or a `-lc`
  cluster, `eval`'s arguments, a heredoc body) is judged as a command of its own, past run wrappers,
  not only one naming git or claude (depth cap 3 kept). There the installer is a word of its own, so
  098's whole-name match on a word's basename finds `bash -c 'scripts/install-x-mod.sh --target y'`;
  a script's own arguments are data (threat model #31: prose naming an installer is not refused).
  `install-guard-notice-mod.sh` pins its source: it hashes a private staged copy of the files, refuses
  (exit 4, naming the digest and the command) to install a digest the developer has not accepted with
  `--accept <digest>`, records accepted digests in the git dir (`claude-mod-accepted`, never the
  target folder, threat model #30), and installs from that same staged copy. A recorded digest
  reinstalls with no `--accept`.

### Acceptance gate

- **R9 (F173, developer O4).** `record_answers` binds a Confirm to `<digest>@<spec-name>`, the name its
  question shows. `--confirm` requires the token for this spec. A bare `<digest>` token from before
  this change keeps an existing Confirmed line valid (the gate and `check`) only while exactly one
  acceptance.md on disk carries that digest; with two (a copy), neither is backed by it, and both
  re-ask. A bare token never writes a new line (tla/AnswerBinding.tla found the route where it would).
  No digest changes.
- **R10 (F178).** `check` prints `confirmed line not backed by a recorded answer` and exits 3 when the
  Confirmed line's digest matches but `answer_bound` does not. `_grandfathered` no longer compares
  "the newest add" from a path-limited log: that log simplifies a merge to one TREESAME parent, so a
  crafted merge carrying an old spec's `interview.md` bytes walked only the old add (reproduced while
  building). A spec is begun before 080 when its `interview.md` is in the arrival commit's first
  parent's tree and no commit in `arrival..HEAD` adds it again (`--full-history`). A git that fails is
  no exemption.

### Hook wiring

- **R11 (F190).** `hook_audit.py` checks each guard present in the project's `scripts/` against the
  tool names it must see (the template's own matchers: Edit, Write, MultiEdit, NotebookEdit, Bash,
  AskUserQuestion, `mcp__x__write_file`, Read as applicable). Only `.claude/settings.json` (committed)
  counts, so `settings.local.json` cannot mask it. A guard is wired by a hook whose resolved script is
  `<root>/scripts/<guard>`, never by substring. No covering group at all is `UNWIRED`; some tools
  missed is `MATCHER` as before.

### Found while specifying

- **R13 (F258).** `guard_precheck_link` ends its ancestor walk by depth and always at the empty path.
  Before, its stop was a case-sensitive string compare after a case-insensitive "inside the project"
  test, so a `file_path` spelled `.../Claude/x` under `CLAUDE_PROJECT_DIR=.../claude` looped forever;
  the hook was timed out by the harness and the call ran (reproduced: a shell write to an
  acceptance.md went through on this repository). Fixed in place, since it blocks this spec. F259 (a
  hung guard is an allow) is recorded, not built.

### Docs and verification

- **R12.** Guard and library headers state the new rules and bounds; the mod's install doc states the
  pin. The row's findings are closed with `finding.sh`. Every R has a fixture in the owning self-test,
  and a sabotage arm where a mutant could pass unnoticed. The mutation gate covers `settings_guard.py`
  (R7, R8), `acceptance_cases.py` (R9, R10) and `hook_audit.py` (R11).

## Out of scope

- A script the agent writes and runs (the 088 bound): it can write `.git`, a PATH directory, or a mod
  location without naming any of them. This row closes the one-liner forms.
- A name assembled at runtime from parts that spell nothing (`x=claude-hook; … ${x}-notices`), the
  declared bound of every text guard.
- Shell writes to a guard script (R6): `sed -i` on `scripts/x.sh` carries no bytes to check.
- A PATH directory reached through a `cd` the text cannot follow (R4): bash-write-guard's resolver
  handles `cd` for the delegated forms; the text forms judge words only.

## Threat model

Trust boundary: **the agent's tool calls → the guards' oracles** (the git dir, the notice stamps, PATH,
git, the hook wiring, the answer store, the mod source). The attacker is the gated agent (same OS user).
Out of model: another OS user, a malicious template, the developer, an MCP server lying about tool
names. STRIDE pass by the `security-scanner` agent in "assume exploitable" mode on the draft,
2026-11-17 (35 items). Each is adopted (built here), a recorded bound, or a finding.

### TB1 — git dir and notice stamps (R1–R3)
- *Adopted (#1, #2, #4):* verbs are judged per simple command by basename (`/bin/rm`, a backtick before
  the verb, `.git;`), a glob that can match `.git` counts (`.g[i]t`, `.gi?`, `.*`), and `cp`, `ln`,
  `install`, `dd` are judged on the destination only, so copying out of `.git` stays a read.
- *Adopted (#5):* the no-`.git` deny names the developer's route (re-clone, restore, `git init`, `!`).
- *Adopted (#7):* the notice-dir and git-dir-substitution rules apply only to a line that writes, so
  `grep -r claude-hook-notices` and `cat "$(git rev-parse --git-dir)/HEAD"` are allowed.
- *Adopted (#9, #11):* the ancestor `gitdir:` target is judged resolved; the gc refuses a symlinked base.
- *Bound (#3):* an interpreter one-liner naming `.git` is bash-write-guard's opaque pass, already denied.
- *Bound (#6, #8):* a git-dir path piped or read (`| xargs`, `read d < <(…)`) and a glob spelling the
  stamp dir's name are runtime-assembled names (the declared bound). *Finding (#2 residue):* `cd .git`
  then a write (F267). *Bound (#10):* a separate git dir is noise (said every time), not a hole.

### TB2 — guards to host tools (R4, R5)
- *Adopted (#14):* `rm` and `unlink` in a PATH directory count (a missing jq or perl fails a guard open).
- *Adopted (#15):* PATH dirs compared case-folded on folding systems and resolved, the leaf's parent too.
- *Finding (#12):* empty or relative PATH entries (F261). *Finding (#19):* the global git config (F260).
- *Bound (#13):* a PATH dir inside the project (`$PWD/scripts`, `.venv/bin`) is refused too; the
  developer installs there with `!`. The hook's PATH is the one the guards resolve through, and it is
  what R4 compares.
- *Bound (#16):* `cp -l` and `rsync --link-dest` are covered by their verbs. *Bound (#17, #18):* template
  identity makes two bounded calls (10 s worst case, under the harness timeout); a timeout reads as
  `project`, so the template maintainer is judged like a project until git answers.

### TB3 — guard availability (R6, R13)
- *Adopted (#21, #22, #23):* `scripts/` judged case-folded and resolved; only a regular file under 2 MB
  is read; the shebang's shell (`sh`, `zsh`, `dash`, `ksh`) does the `-n` check.
- *Adopted (#24):* the pre-check walk also stops when the path cannot shrink (a relative cwd `.`).
- *Finding (#20):* R6 parses but does not run the edited guard (F268). *Finding (F259):* a hung hook is
  an allow, for any guard.

### TB4 — settings guard parsing (R7, R8)
- *Adopted (#28):* `$_` outside single quotes only; history expansion is off in a non-interactive shell.
- *Adopted (#31):* the installer is a whole word's basename, found inside program strings by the nested
  re-judge; a script's own arguments (prose) are data.
- *Adopted (#30):* accepted digests live in the git dir, never the agent-writable target; the installer
  hashes and installs one private staged copy.
- *Finding (#25):* `<>` through a descriptor (F263). *Finding (#26):* invert the runner deny list (F262).
  *Finding (#29):* a renamed installer copy (F265). *Bound (#27):* a name carried across two tool calls
  is outside any one call's text.

### TB5 — answer store (R9, R10)
- *Adopted (O4):* a bare token backs an existing line only while its digest is unique on disk.
  *Adopted (#32, F264 resolved):* the window after the original is moved or edited is closed, since a
  bare token never writes a new line (see TLA+ below). *Bound:* the token binds the spec's basename, as the
  question shows it; two packages with the same spec name in one monorepo share it.
- *Adopted (found while building R10):* the path-limited log's merge simplification is replaced by the
  tree-and-range test.
- *Bound (#33):* `check` exits 3 in a clone with no recorded answer, as the 098 R2 gate already denies
  there; the message names the route.

### TB6 — hook wiring (R11)
- *Adopted (#34):* an `async` guard is a finding (`ASYNC`).
- *Bound (#35):* a guard wired through `cd x && bash scripts/g.sh` reads as UNWIRED next to the existing
  UNRESOLVED finding for that command; plugin and user wirings are one machine's by design.
- *Finding:* bash-write-guard's opaque pass refuses a PATH path named in an interpreter program (F266).

### Adversarial review (security-scanner, "assume exploitable", on the built diff, 2026-11-17)

Eleven items, all read from code (the agent had no shell); each was reproduced or refuted with the
owning self-test before it was decided.
- *Fixed (#1, #2, #9):* destination options read bare, attached and clustered (`-t.git/hooks`, `-at d`,
  `--target-directory=`); `rsync`, `ditto`, `tar -C`, `unzip -d`, `patch`, `curl -o`, `wget -O` are
  writers for R1 and R4. Fixtures in `test-trust-anchor-guard.sh` [105 review].
- *Fixed (#3):* the git-dir rule matches `rev-parse … --git-dir` anywhere on a line that writes, so a
  nested `$(:)` no longer hides it.
- *Fixed (#4, a regression of R8 as first built):* `-c`'s program is the first operand after it, past
  `--` and options. *Fixed (#5):* the runner is found past `env`, `xargs`, a signal name and `find -exec`.
- *Fixed (#6, #7):* the R6 pre-check is case-folded; a `ValueError` from `compile` is a parse error.
- *Dismissed (#8):* `rm .git/index.lock`, and `rm -r` or `touch` on a `.git` below the project, stay
  refused. Any `.git` is a root the walk can anchor at, and removing a lock is the developer's step.
- *No bypass found (#10, #11):* the relaxed `plain` rule and the R13 loop.
- *Found while testing #6:* under bash 3.2 a `)` in single quotes inside `"$( )"` ends the substitution.
  A literal jq filter in a test therefore sent the guard an empty payload; the arm uses `edit_p`.

### /security-review (on the built diff, after the adversarial review)

Three findings, each measured against HEAD with the real hooks; all fixed.
- *Fixed (vuln 2, a regression of R1's first build):* `verb_of` returned a wrapper's option (`nice -n`,
  `sudo -u`) or the wrapper itself (`timeout`, `xargs`, `busybox`), so `timeout 60 rm -r .git` passed.
  It now skips wrappers, their options, option values, a duration, a signal name, and `flock`'s or
  `chroot`'s operand; a here-string operand is a word (`xargs chmod 000 <<< .git`).
- *Fixed (vuln 3):* `claude-mod-accepted`, the R8 pin store, is a named store: any shell text naming it
  and any path to it is refused, like the two 088 stores.
- *Fixed (vuln 1, a regression of R8's narrowing):* a here-string fills a shell's stdin, so
  `bash <<< '<git restore that rewrites settings>'` is judged as a program, as a heredoc was.

### TLA+ (`tla/AnswerBinding.tla`)

R9 as first built (a bare token binds while its digest is unique) failed `ConfirmedMeansAsked`: copy a
legacy-confirmed spec's cases into a new spec, edit the original's, and the copy's digest is unique.
Fix: a bare token keeps an existing Confirmed line valid at the gate and `check`, and never writes a new
one (`--confirm` needs `<digest>@<spec>`). That also closes the delete window first recorded as F264.
The `v1` configuration (pre-105, digest-only) fails; `v2` and `v2del` (with deletes) check clean.

## Success criteria

- SC-1: each reproduced bypass in the Problem table is denied (or announced, where a guard fails open)
  by the owning self-test.
- SC-2: a guarded project with git on PATH and a normal checkout pays no extra process on the common
  path of any guard (`bench-hooks.sh`).
- SC-3: no false positive on the template's own work: the full suite runs green under the live guards,
  `git rev-parse --git-dir`, `cat .git/HEAD`, `grep x <settings> ; bash scripts/test-x.sh "$(pwd)"` and
  an Edit of a guard script that parses are allowed.
- SC-4: the full template suite is green, and the mutation gate meets the hardened bar on the changed
  modules.

## Functional coverage

| Function | Test |
|---|---|
| R1 git-dir verbs, no-.git walk | `test-trust-anchor-guard.sh` [105-R1], `test-guard-lib.sh` [105-R1] |
| R2 notice dir, git-dir substitution | `test-trust-anchor-guard.sh` [105-R2] |
| R3 notice base, gc sweep | `test-guard-lib.sh` [105-R3], `test-harness-state-gc.sh` [105-R3] |
| R4 PATH writes | `test-trust-anchor-guard.sh` [105-R4] |
| R5 bounded template identity | `test-template-identity.sh` [105-R5] |
| R6 parse check | `test-trust-anchor-guard.sh` [105-R6] |
| R7 runners, handed-on names | `test-settings-edit-guard.sh` [105-R7] |
| R8 installer word, pin | `test-settings-edit-guard.sh`, `test-guard-notice-mod.sh` [105-R8] |
| R9 spec-bound answers | `test-acceptance-cases.sh` [105-R9] |
| R10 check, topo order | `test-acceptance-cases.sh` [105-R10] |
| R11 wiring audit | `test-validate-hooks.sh` [105-R11] |
| R13 precheck walk ends | `test-guard-canonical-paths.sh` [105-R13] |

There is no UI. The four states read as: allow with no output (success), deny with a reason that
names the cause and the developer's route (error), a call with nothing to judge (empty, exits 0), and
a guard that cannot decide (fail-closed deny, or an announcement where the guard fails open).

## Clarifications

### Session 2026-11-17

- Q: R1, does `cp x .git/hooks/pre-commit` need the new verb rule, given bash-write-guard already delegates
  `cp` targets? → A: Yes, both. The delegation judges the resolved target; the text rule also catches a
  `cp -t .git/hooks x` form the extractor does not read. Two layers, one verdict word.
- Q: R1, does the no-`.git` fallback apply inside the template? → A: No. The template carries a register,
  and it is exempt from the CORE guards by `template_identity`, which needs git; with `.git` gone the
  identity reads `project`, so the CORE guards judge. That is the intended direction (never exempt on
  a guess).
- Q: R4, is `/dev/null` or `/dev/stdout` a write into a PATH directory if `/dev` is on PATH? → A: No.
  `/dev/*` targets are never PATH writes.
- Q: R6, which bash parses the new bytes? → A: `bash` from PATH, the one the hooks run with (`bash
  "$CLAUDE_PROJECT_DIR/scripts/…"`), with a 5 s bound.
- Q: R7(c), does `$_` inside single quotes count? → A: No; it is judged on the words after quote
  removal only where the shell would expand it. The check reads the raw text with single-quoted runs
  blanked.
- Q: R11, are `user` and plugin hook files audited for UNWIRED? → A: No. Only the committed project file
  decides coverage; the other files keep their existing UNRESOLVED and CHANNEL checks.

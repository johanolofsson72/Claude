# 090 — guard canonical paths, round 2

Track: full, hardened. Trigger 1: the change is the path-resolution layer under every Edit-path gate.
Trigger 3: the row is tagged. Trigger 4: well over 6 files.
Findings: F082 F083 F084 F085 F096 F105 F106 F112, verbatim in `specs/FINDINGS.md`. F122 (H4, open)
shares F106's code path and is folded in (carve-budget rule 1: fixing it here is smaller than
recording it).

## Problem

Spec 083 made the guards judge a canonical path instead of the raw text, and 088 anchored the root
walk. Both still judge the file the agent spelled, not the file the write lands on. Every case below
was reproduced on 2026-10-02 against the guards at 149eda0, with `CLAUDE_PROJECT_DIR` set:

| Finding | Payload | Guard | Today |
|---|---|---|---|
| F082 | Edit `<proj>/SCRIPTS/guarded.sh` (CORE) on macOS | core-machinery | allowed |
| F082 | Edit `<proj>/scripts/GUARDED.SH` | core-machinery | allowed |
| F082 | tick through `<proj>/specs/index.md` or `SPECS/INDEX.md` | core-owed-tick | allowed |
| F083 | Edit `docs/notes.txt`, a symlink to `../src/App.cs` | spec-interview, pipeline-state | allowed |
| F083 | Edit `docs/tools/guarded.sh`, `docs/tools` a symlink to `../scripts` | core-machinery | allowed |
| F096 | Edit `src/App.cs.` (NTFS: the same file as App.cs) | pipeline guards | allowed |
| F084, F096 | Edit `src/q.sql`, `.bat`, `.ipynb`, `.tf`, … | pipeline guards | allowed |
| F084 | NotebookEdit `src/n.ipynb` | pipeline guards | never asked |
| F084 | `git push --mirror`, `--delete`, `-d`, `origin :main`, `--prune` | destructive-command | allowed |
| F105 | `CLAUDE_PROJECT_DIR` spelled NFD, file spelled NFC, `src/.git` planted | spec-interview | allowed (NFC anchor: denied) |
| F106 | Edit in a `git worktree add --no-checkout .claude/worktrees/nc` | spec-interview | allowed |
| F085 | `sed 's/.env//' f.txt` | sensitive-file | **denied** (false positive) |
| F112 | heredoc fixture holding `{/* c */}` | trust-anchor (via bash-write) | **denied** (false positive) |

`src/APP.CS` is already denied by the pipeline guards, because they lower-case the extension. F082's
real exposure is the two CORE guards, whose `case` patterns and `--is-core` lookup compare spelling.

The root cause of the first seven rows is one sentence: a path is compared as text before it is
resolved to the name the file system stores. On macOS and Windows the file system folds case and
Unicode normalisation, on NTFS it drops trailing dots and spaces, and a symlink anywhere in the path
moves the write. The raw-text prechecks in front of each guard compare even earlier than the
canonicaliser, so a name that hides the extension or `scripts/` never reaches it.

## Requirements

- **R1 — The canonical path is the stored name (F082, F105).** On a case-folding system
  (`OSTYPE` darwin, msys, cygwin, win), `guard_canon` returns the name the file system stores for
  every component that exists. Directories come from the physical working directory (`/bin/pwd -P`,
  which is getcwd: the stored case and the stored Unicode form; bash's builtin `pwd -P` returns the
  typed spelling, measured). The final component, when it exists, is matched case-insensitively in
  its directory. `_guard_realdir`, which resolves the anchor, does the same. Components that do not
  exist keep their typed spelling. On other systems nothing changes.
- **R2 — The prechecks pass what the parser would judge (F082, F083, F096).** Each raw-text precheck
  in the five Edit-path guards:
  - (a) folds case: core-machinery's `scripts/` and `rules/`, core-owed-tick's `INDEX.md`;
  - (b) passes a payload on to the parser when its `file_path` (or `notebook_path`), taken against
    the payload's `cwd` when relative, is a symlink, or has a symlink as any existing ancestor below
    `/`. Builtin `[ -L ]` per component, no process. An escaped path (a `\` in the JSON string) also
    goes to the parser;
  - (c) admits trailing dots, trailing spaces and a `::$DATA` suffix after a source extension.
- **R3 — The extension is the file's (F096, F084).** The three pipeline guards strip trailing `.` and
  ` ` and a `::$DATA` suffix from the basename before taking the extension, on every platform (WSL on
  NTFS reports linux). `SOURCE_EXTS` gains `sql bat cmd psm1 aspx jsp ejs coffee mm sol tf ipynb`,
  byte-identical in the three guards (`test-spec-dir-absent.sh`).
- **R4 — NotebookEdit is judged (F084).** The three pipeline guards (spec-register, pipeline-state,
  spec-interview) read `tool_input.notebook_path` when `file_path` is empty. The two CORE guards do
  not: NotebookEdit writes only `.ipynb`, and no CORE file is one. The template wiring for the five-guard block becomes `Edit|Write|MultiEdit|NotebookEdit`.
  `.claude/settings.json` is the developer's to change (089), so the spec ends with the exact command
  for them to run with `!`, and `sync-core-hooks.py` carries the matcher into every project.
- **R5 — The push deny list covers deletion (F084).** `destructive_command.py` adds
  `git-push-delete` (`--delete` or its unambiguous prefix, `-d` in a short cluster, a refspec
  `:<ref>` with an empty source, `--prune`) and `git-push-mirror` (`--mirror`). `git push origin :`
  (the matching refspec) stays allowed. No override, as for the rest of the list.
- **R6 — A planted .git at the anchor counts only when it is a repository (F105, developer O1).**
  When the walk reaches the anchor itself, the anchor holds a `.git`, and some ancestor of the anchor
  also holds one, the anchor's `.git` is a boundary only when `git -C <anchor> rev-parse --verify -q
  HEAD` succeeds and `--show-toplevel` names the anchor. An empty file, an empty directory and a fresh
  `git init` with no commit are not boundaries; the walk goes on to the outer project. A real nested
  repository the developer started a session in is still its own root. When no ancestor holds a
  `.git`, nothing changes and no git process runs.
- **R7 — A worktree without its own state inherits the project's (F106, F122).** When the walk stops
  at a linked worktree below the anchor, and the walk so far found no register or no language marker,
  it goes on upward to the project's real boundary and takes the missing one from there. Exemptions
  (`scripts/`, `specs/`, `.specify/`, `.claude/`) stay anchored at the worktree root, never at the
  project root above it, so `.claude/worktrees/<w>/src/x.cs` is not exempt as a `.claude/**` path.
  A worktree that has its own register and marker resolves exactly as in 088.
- **R8 — Two false positives (F085, F112).**
  - (a) `sensitive_paths.py` treats the script argument of `sed` as data: the word after `-e` or
    `--expression`, and, when neither is given, the first operand. A file operand (`sed … .env`) and
    `-f <file>` are still paths.
  - (b) `trust-anchor-guard`'s acceptance test judges a glob by what it expands to: braces expanded
    the way bash expands them (a comma is required), each glob component matched case-insensitively
    against what is on disk. A glob counts only when an expansion is an existing `acceptance.md`, or
    when its literal basename is `acceptance.md`. `{/*` in a heredoc is no longer an acceptance.md.
  - (c) found in this session, same class: `settings_guard.glob_hit` matched a glob with `fnmatch`
    over the whole path, where `*` crosses `/`. Every `*` in an interpreter heredoc (`python3 - <<X`
    with `a * b` or `*args`) "matched" `<proj>/.claude/settings.json` and the command was denied; it
    blocked this spec's own edit scripts four times. The match now keeps each glob character inside
    one component, and a dot component needs a literal dot, as the shell does.
- **R9 — Docs and tests.** The `guard-lib.sh` header (stored names, the worktree inheritance), the
  destructive guard header and `.claude/docs/security.md` (the new forms), the precheck comments in
  each guard. A test per requirement, each with a sabotage arm, and tests named `090-AC-<n>`.

## Out of scope

- Hard links that already exist. A pre-existing hard link to `src/App.cs` under `docs/notes.txt` is
  the same inode. Detecting it needs `stat` per Edit; creating one through the shell is already judged
  as its target (083). Named residual.
- NTFS alternate data streams other than `::$DATA` (`App.cs:x` writes a different stream, not the
  file's content), 8.3 short names (`APPCS~1.CS`), and Windows reserved device names.
- Normalisation of a component that does not exist yet. There is no stored form to look up.

## Clarifications

### Session 2026-10-02 (auto-picked, recommended option; measured where it could be)

- Q: Does bash's builtin `pwd -P` return the stored case? → A: No. Measured with bash 3.2 on APFS:
  `cd /USERS/JOOL/REPOS/CLAUDE/SCRIPTS && pwd -P` prints the typed spelling; `/bin/pwd -P` prints
  `/Users/jool/repos/Claude/scripts`. Under an NFD-typed path `/bin/pwd -P` prints the stored NFC
  name. R1 uses `/bin/pwd -P` on case-folding systems and falls back to the builtin.
- Q: Does R1 change what a deny message names? → A: Yes, the canonical path in a reason is now the
  stored spelling. That is the file the write lands on, so it is the more accurate text.
- Q: The final component on a case-sensitive APFS volume where `App.cs` and `APP.CS` both exist? →
  A: An exact match wins (Q6). Only when no exact match exists and one case-insensitive match does
  is the stored name substituted.
- Q: Which guards get R2(b)'s symlink precheck? → A: All five Edit-path guards. The pipeline guards
  test the final component and its ancestors (a symlinked file hides the extension); core-machinery
  and core-owed-tick the same (a symlinked directory hides `scripts/` or `specs/`).
- Q: Does R3's `ipynb` in `SOURCE_EXTS` change the Write tool's verdict on a notebook? → A: Yes. A
  Write of `src/n.ipynb` is gated like any source file, which is the point of F096.
- Q: R5, does `git push --delete` count in a `-c` or `sh -c` body? → A: Yes, the classifier already
  reads executed bodies; the new forms ride on `judge_git`.
- Q: R7, which register applies when the worktree has none? → A: The outermost one above it, by the
  same "outermost wins" rule the walk already uses, collected only while the worktree lacked one.
- Q: R8(a), what about `perl -pe 's/.env//'` or `awk`? → A: Out of scope. Their script is a program
  that can open files, so it stays a path candidate. Only sed's script is a pattern language.
- Q: R6, what if `git` is not on PATH? → A: The check fails, so the anchor's `.git` is not a
  boundary and the walk goes on to the outer project: the stricter reading, as everywhere in 088.

## Threat model

The attacker is the gated agent (Claude, same OS user, Edit/Write/MultiEdit/NotebookEdit/Bash),
careless or prompt-injected, trying to make a guard judge a different file than the one a write lands
on, or to run a destructive command. Out of model: another OS user, a malicious template. The
`security-scanner` ran in assume-exploitable mode on the plan before implementation (10 points); its
dispositions are folded in below.

### TB1 — the payload's path spelling → the canonical path (R1, R3)

- **Spoofing.** `SCRIPTS/x.sh`, `scripts/X.SH`, an NFD spelling, `App.cs.`, `scripts./x.sh`,
  `C:\proj\scripts\x.sh`. *Mitigation:* stored names (getcwd plus a folded lookup of the final
  name) where the system folds; NTFS trimming of every component on msys/cygwin/win, and of the
  extension everywhere (O2); drive paths through `cygpath -u`; a `.git`/`.GIT` probe turns folding on
  for a Linux mount that folds (WSL on /mnt/c, casefold ext4). *Residual:* a name that does not exist
  yet keeps its spelling, so a new `scripts/Tlc-Cleanup.sh` beside no CORE file of that name is not
  CORE; NTFS short names (`APPCS~1.CS`) and named streams other than `::$DATA`; trailing dots in a
  directory on WSL's NTFS mount, where the walk does not trim.
- **Denial of service.** O2's trim gives `x.sh.` on Linux a source verdict. Accepted.

### TB2 — the raw-text precheck → the parser (R2)

- **Tampering.** A symlink that already exists, a JSON `\u` escape, a case variant of `scripts/`.
  *Mitigation:* builtin `[ -L ]` on the final component and every ancestor below the anchor, a
  backslash in the path sends it to the parser, `nocasematch`. *Residual:* a hard link that already
  exists (no link count without `stat`); a symlink created by a parallel tool call in the same
  message, after this hook ran (TOCTOU, Q11); a link above the anchor, which is ordinary (/tmp, /var,
  a symlinked ~/repos) and not tested so the fast exit holds.

### TB3 — the root walk at the anchor and at a linked worktree (R6, R7)

- **Spoofing.** An empty `.git` file or directory, a fresh `git init`, or a `.git` file reading
  `gitdir: ../.git` at a subdirectory anchor; a `--no-checkout` worktree or one at a pre-register
  commit. *Mitigation:* at the anchor, with a `.git` above, only a directory-form repository with a
  commit whose top level is the anchor counts (O1); a `.git` file there must be a linked worktree of
  this project. A worktree lacking a register or marker inherits the project's; exemptions stay at the
  worktree. The CORE guards judge an empty worktree by the project's sync (scanner #1). *Residual:*
  `git init && git commit --allow-empty` at a subdirectory anchor passes R6, which the developer
  accepted with O1; the command text names no `.git`, so no guard sees it.
- **Denial of service.** R6 runs up to two git processes per Edit when an ancestor of the anchor holds
  a `.git` (a dotfiles repository in `~`). Not cached.

### TB4 — Bash text → the destructive and sensitive classifiers (R5, R8a)

- **Elevation.** `--mirror`, `--m`, `--delete`, `--del`, `-d` in a cluster, `:ref`, `--prune`,
  `send-pack --mirror`, `git config remote.<x>.mirror|push`, `-c remote.<x>.mirror=…`. *Mitigation:*
  `judge_push` and the config judge; the bash precheck now also passes `send-pack`, `mirror` and
  `remote`. *Residual (the declared bound of spellings, not semantics):* an alias
  (`git -c alias.p='push --mirror' p`), `GIT_CONFIG_COUNT/KEY/VALUE` in the environment, `gh api -X
  DELETE`, a refspec assembled at runtime.
- **Information disclosure.** sed's own file commands: `r`, `R`, `w`, `W`, `e`, the `w` and `e` flags.
  *Mitigation:* only a single pure `s///` or `y///` with no `w`/`e` flag is data; every other script
  is split into words, and `rFILE`/`wFILE` without a space are read too. *Residual:* sed reading a
  file named only through a variable.

### TB5 — a delegated glob target → "is this an acceptance.md" (R8b, R8c)

- **Tampering.** `{a..a}cceptance.md`, `a[[=c=]]ceptance.md`, an upper-case glob, a glob expanding to
  a symlink or hard link to one. *Mitigation:* bash brace expansion (comma and sequence forms), a
  case-folded listing per glob component, bracket expressions widened to `*`, and every expansion
  judged as a file (realpath, inode). *Residual:* `extglob` patterns (`@(a|b)`), which bash only
  expands with the option on.
- **Denial of service (the false positives).** `{/*` in a fixture and `*` in an interpreter heredoc
  denied ordinary work. Fixed by R8(b) and R8(c).

### Adversarial review (2026-10-02)

Two passes. The `security-scanner` went first, on the plan, before any code (10 points, folded into
the threat model above). The second pass ran on the implementation in assume-exploitable mode, with
a shell, and reproduced 10 issues. Nine are fixed and pinned by an arm named `review #<n>`:

1. A `--no-checkout` worktree nested inside another escaped R7, because the walk stopped at the
   outer one. The walk and `guard_core_root` now pass through every worktree that lacks its own state.
2. `brace_alts` truncated at 64/256 expansions, so `{q0,…,q299,acceptance}.m?` and `{100..001}` were
   allowed. Expansion is now complete up to 512 and fails closed above that.
3. `{1..99999999}` took 14 s. Each range is sized before it is built.
4. sed's `1r.env`, `/r/r.env` and `s/r/b/w.env` were missed. Every `r`/`R`/`w`/`W` position in a
   non-pure script is now tried.
5. `--config-env=remote.<x>.mirror=…`, `git remote add --mirror=push`, and `git config --type bool`
   or `-f <file>` slipped past the config judge.
6. `$'\x3amain'` hid a delete refspec. ANSI-C escapes are now decoded before tokenising.
7. Regression: a session in a submodule, or in a repository whose git dir lives elsewhere, lost its
   own root. A `.git` file at the anchor now counts when its gitdir is not an outer repository's own.
8. Regression: `shopt -s dotglob; rm -r *` passed the narrower settings glob. A command naming
   `dotglob`, `globstar` or `GLOBIGNORE` now gets the old whole-path match, and `**/` may match no
   directory at all.
9. A `.git` symlinked to the outer one at the anchor counted as a repository. It no longer does.

Accepted: #10, where `git push --dry-run origin :x` is denied. A dry run of a deletion is rare, and
the developer can run it with `!`.

While writing the arms we found a bash 3.2 defect: a `{…}` inside `"$( … "…" … )"` is
brace-expanded. A test that builds a brace payload inline therefore sends a different payload, and
`{1..99999999}` hangs. Those arms build the payload in a variable first.

### /tla (2026-10-02)

`RootWalk.tla` checks the walk over every layout the spec names (a worktree level, seven `.git`
forms at the anchor, an outer repository, registers and markers): 224 distinct states.
RegisterNeverDropped holds with R6 and R7 in place. Without R7 there is a 1-step counterexample (a
session in an empty linked worktree), and without R6 there is one too (an empty `.git` file at a
subdirectory anchor). The one exception the invariant allows is the developer's O1 choice: a real
nested repository with a commit at the anchor.

### /security-review (2026-10-02)

One high-confidence finding, fixed. The settings guard's switch back to the loose glob match was a
regex on the raw command, so `shopt -s dot''glob` or `$'\x64otglob'` turned dotglob on in bash
without turning the loose match on, and `cp e.json */settings.json` passed. The option names are
now read with quotes, backslashes and `$'…'` removed, and any `shopt` or `-O` counts. One note below
the bar was fixed too: with `-f` or an attached `-e…`, sed's first operand is a file, not the
script. The review found no new bypass in the walk, the anchor check, the precheck or cygpath.
Running git in a repository the agent made adds nothing the agent cannot run itself.

### Mutation gate (2026-10-02)

`run-mutation-gate.sh` on `guard-lib.sh`, `guard-precheck.sh`, `spec-interview-guard-hook.sh` and
`destructive-command-guard-hook.sh` (seed 20261002, 20 per module). The first run scored 59.2 %. Most
survivors were `exit 0 → exit 1`, which no test noticed because the tests read only the verdict, and
platform branches that never run on macOS. The tests now fail on a non-zero exit, and unit arms
force the Linux probe, a stand-in `cygpath` and the fold layer. Two loops were rebuilt so that a mutant fails instead of hanging (a timeout is not a kill). Final run, same seed: **83.8 % (62/74)**. guard-lib 90 %, guard-precheck 100 %, destructive-command 90 %, spec-interview 60 %. The 10 survivors are in code 090 did not change: spec-interview's register-resolver error branches and two destructive-guard lines. They are recorded as a finding for row 092.

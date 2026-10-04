# 098 — guard hole sweep 2

Track: full, hardened. Triggers: a security domain (the guards are the trust boundary between the agent
and the developer's decisions), the trust stores and the acceptance gate's shortcut, and about ten
files. Findings verbatim in `specs/FINDINGS.md`: F139, F140, F141, F142, F143, F144, F155, F159.

H5 and spec 095 found each of these. Six are a guard that allows when its header says it refuses, or
that allows without saying so. F143 is the mutation sandbox leaking the developer's environment into
mutant tests. F155 is a guard refusing a harmless command.

## Problem

| Finding | Where | What goes wrong today |
|---|---|---|
| F139 | `trust-anchor-guard-hook.sh` pre-check, L84-89 | Only the last path component is tested with `[ -L ]`. With `gd -> .git` already in the tree, a Write to `gd/info/exclude` names no trigger word and exits before the parser, which would resolve it. Reproduced 2026-10-04 |
| F140 | `acceptance_cases.py` `_committed_unchanged` | The shortcut trusts the upstream remote-tracking ref as "R2 keeps the agent from moving it". A plain `git push` moves it as a side effect and is allowed, so a Confirmed line that reached disk by an unguarded route and was pushed passes |
| F141 | `core-machinery-guard-hook.sh` L114-133, `core-owed-tick-guard-hook.sh` L206-220 | Both exit 0 with no word when the sync root has no `.claude/` or no `scripts/template-autosync.sh`. Deleting one file turns both guards off |
| F142 | `guard-lib.sh` `_guard_linked_worktree`, `_guard_anchor_git_counts` | git runs with no timeout. A missing or failing git reads as "not a worktree" or "the anchor does not count", and the root moves without a word |
| F143 | `run-mutation-gate.sh` `run_test` | A denylist of nine variables. `GIT_SSH_COMMAND`, `GIT_CONFIG_COUNT/KEY/VALUE/PARAMETERS`, `GIT_CONFIG_SYSTEM` and cloud tokens reach mutant tests. A local-path remote is not blocked by the transport refusal. rc 137 under the limit (OOM, an external kill) counts as a kill |
| F144 | `hook-notice.sh` `hn_first_time`, used by `guard_announce` | The once-per-session stamp lives under `$TMPDIR/claude-hook-notices/<sid>/<cksum of the key>`. Both parts are predictable, so a stamp the agent creates first silences the fail-open notice for the model and, since 096, the developer's toast |
| F155 | `settings_guard.py` `_bash_verdict` L1613-1616 | "A read whose output can reach a command that runs text" counts every command on the line. `grep hooks <settings> ; bash scripts/test-x.sh` is refused. Reproduced 2026-10-04 (the live guard refused this spec's own repro command) |
| F159 | no check | A project that never syncs keeps PreToolUse matchers without `mcp__.*`, so MCP writes skip settings-edit-guard and trust-anchor-guard with no signal |

## Requirements

### Trust anchors

- **R1 (F139).** trust-anchor-guard's pre-check sends a `file_path`/`notebook_path` to the parser when
  the path runs through a symlink at any component: `guard_precheck_link` (spec 090 R2(b)), the
  ancestor walk the five Edit-path guards already share. When `guard-precheck.sh` cannot be loaded,
  the pre-check sends the call to the parser (look, never skip). The parser already judges the resolved
  path (`path_hits` takes `realpath`); a fixture proves it denies `gd/info/exclude` and
  `gd/description` through a link to the git dir.
- **R2 (F140, developer O1).** `_committed_unchanged` is removed. A Confirmed line unlocks code only
  when this clone's answer store backs it (`answer_bound`), whether or not it is committed or pushed.
  A fresh clone, or the other lane picking up an in-flight spec, gets a deny that says why and how:
  ask the confirm question again, then `--confirm` re-records the answer. The deny text no longer
  mentions committing or pushing as a way through.

### CORE guards

- **R3 (F141, developer O2).** When the sync root shows that the project is synced (the stamp
  `.claude/.template-sync`, or a register `specs/INDEX.md`) and `scripts/template-autosync.sh` is
  missing, both CORE guards deny (core-machinery: the CORE-path edit; core-owed-tick: the register
  tick). The reason names the missing file and the route: restore it with `git checkout HEAD --
  scripts/template-autosync.sh`, or have the developer rerun the sync. The template-identity check
  still runs first, so the template stays exempt. No `.claude/`, or neither stamp nor register, is a
  project this guard has no opinion on, and stays silent.

### Root walk

- **R4 (F142, developer O3).** Every git call in `guard-lib.sh` goes through one helper, `_guard_git`:
  `GIT_*` dropped, bounded by `GUARD_GIT_TIMEOUT` seconds (default 5) through `timeout`, `gtimeout` or
  `perl -e alarm`, whichever exists first. A missing git, a timeout, or no way to bound the call sets
  `GUARD_GIT_UNSURE` to the cause, which is different from git answering "no". The walk functions
  (`guard_walk`, `guard_core_root`) leave it set for the caller. Developer O3: the three pipeline
  guards (spec-interview, pipeline-state, spec-register) deny, naming the cause. The two CORE guards
  (fail-open by design) call `guard_announce` and go on with the root the walk found.

### Mutation sandbox

- **R5 (F143).** `run_test` starts each test with `env -i` and an allowlist: `PATH`, `TMPDIR`, `LANG`,
  `LC_ALL`, `LC_CTYPE`, `TERM`, `USER`, `LOGNAME`, `SHELL`, plus `HOME=<copy>.home` and
  `GIT_CONFIG_NOSYSTEM=1` (the system config is where macOS keeps `credential.helper=osxkeychain`).
  The copy's `.gitconfig` gains `url.<blocked>.pushInsteadOf` for the real repository root and its git
  common dir, with a longer identity rule for the run directory, so a push to the developer's repository
  by path fails and a push to a fixture inside the run does not. rc 137 under the limit is
  infrastructure (no verdict, the run is unmeasured), not a kill.

### Notices

- **R6 (F144).** `guard_announce` keeps its once-per-session stamp only where the agent's tools cannot
  write: under the project's git dir (`<git dir>/claude-hook-notices/<sid>/`), which trust-anchor-guard
  denies by its rule (a). The git dir is found upward from the project dir and through a `.git` file's
  `gitdir:` line, so a linked worktree dedupes in its own git dir (threat model #8; Allium drift
  decision 2026-10-04). When no git dir is found, the announcement is said every time. Other `notice_once` reminders
  keep the TMPDIR stamp: a lost reminder there costs a nudge, not a guard. `harness-state-gc.sh` sweeps
  the new directory too (stamp directories older than two days).

### Shell reads

- **R7 (F155).** A pipe mate of the read that is not a bare stdout filter always counts. A runner
  (`EXEC_COMMANDS`) in another list element (`;`, `&&`, `||`, `&`, newline) counts only when the line
  is unplain, or when the read's own pipeline writes a file: a redirect to anything but
  `/dev/null|stdout|stderr|tty` (a dup like `>&2` is no file, `> 2` is), or an output option
  (`--output=f`). Unplain is judged on the raw text: a group, a subshell, `coproc`, `exec`, a
  here-string, a descriptor above 2, or any `$`, backtick or backslash. Verified by `tla/ReadFlow.tla`
  (adversarial review and Allium drift decision, 2026-10-04).

### Hook wiring

- **R8 (F159).** `hook_audit.py` reports a `[HOOKS]` finding when the project's
  `.claude/settings.json` wires `settings-edit-guard-hook.sh` or `trust-anchor-guard-hook.sh` on
  PreToolUse under a matcher that does not match `mcp__x__write_file`. The finding names the hook, the
  matcher, and the fix (`|mcp__.*`, applied by the developer or by the next template sync). The project
  maintenance pass already runs `validate-hooks.sh`, so the finding reaches the maintenance report.

### Docs and verification

- **R9.** Guard and library headers state the new rules and bounds. The row's findings are closed with
  `finding.sh`.
- **R10.** Every R has a fixture in the owning self-test, and a sabotage arm where a mutant could pass
  unnoticed. The mutation gate covers the changed modules: `settings_guard.py` (R7), the changed part
  of `acceptance_cases.py` (R2), `hook_audit.py` (R8).

## Out of scope

- A script the agent writes and runs that writes into `.git` (the trust-anchor bound since 088). R6
  moves the stamp behind the same line, not past it.
- A mutant test that writes the developer's files directly. The sandbox prevents accidental reach
  (environment, credentials, transports, a push by path), not deliberate filesystem writes by code that
  runs as the developer's user (R5 bound).
- The `notice_once` reminders other than `guard_announce` (R6).
- F151 (allow paths asserted to exit 0) belongs to row 100.

## Success criteria

- SC-1: each reproduced bypass in the Problem table is denied (or announced, where the interview keeps
  fail-open) by the owning self-test, and F155's false positive is allowed.
- SC-2: a guarded project with git on PATH and a normal checkout pays nothing new: no extra process
  on the common path of any guard (measured with `bench-hooks.sh`).
- SC-3: the template repository's own edits stay unguarded by the CORE guards.
- SC-4: the full template suite is green, and the mutation gate meets the hardened bar on the changed
  modules.

## Functional coverage

| Function | Test |
|---|---|
| R1 ancestor symlink | `test-trust-anchor-guard.sh` [098-R1] |
| R2 shortcut trust | `test-acceptance-cases.sh` [098-R2] |
| R3 missing sync | `test-core-machinery-guard.sh`, `test-core-owed-tick-guard.sh` [098-R3] |
| R4 git helper | `test-guard-lib.sh` [098-R4] (PATH without git, a git that sleeps) |
| R5 sandbox env | `test-run-mutation-gate.sh` [098-R5] |
| R6 stamp location | `test-guard-lib.sh` [098-R6] |
| R7 pipeline flow | `test-settings-edit-guard.sh` [098-R7] |
| R8 matcher audit | `test-validate-hooks.sh` [098-R8] |

There is no UI. The four states read as: allow with no output (success), deny with a reason that
names the cause and the developer's route (error), a call with nothing to judge (empty, exits 0), and
a guard that cannot decide (fail-closed deny, or an announcement where the guard fails open).

## Clarifications

### Session 2026-10-04

- Q: R4, where does a pipeline guard deny on `GUARD_GIT_UNSURE`: before or after its exemptions? → A:
  Before. The exemptions (`scripts/`, `specs/`, `.claude/`, `.specify/`) are anchored at the git root,
  and the walk could not establish that root. The repair (git on PATH, a git that answers) is not an
  edit, so nothing the deny blocks is the way out.
- Q: R4, does `template_identity` (template-identity.sh, called by the 095 R6 stand-in) go through
  `_guard_git`? → A: No. It is its own library, shared with the sync. When git cannot answer it
  reports `project`, the strict reading, so the template is guarded rather than a project being
  exempted.
- Q: R2, does removing the shortcut change `--confirm`? → A: No. `--confirm` already requires a
  recorded answer for the digest. Only the gate's fallback goes.
- Q: R3, the deny is reached in a linked worktree with no sync of its own. → A: `guard_core_root`
  already defers such a worktree to the project's sync root. R3 judges that root.
- Q: R5, does the allowlist keep `CLAUDE_*`, `MUTATION_*` or `TEMPLATE_*` variables? → A: None. The
  runner passes the limit as an argument, and the self-tests set their own fixtures. A test that needs
  a variable sets it itself.
- Q: R6, a session without `CLAUDE_PROJECT_DIR` (a test, an old harness)? → A: Said every time, as
  without a session id today.
- Q: R8, a matcher on the user's `~/.claude/settings.json` or a plugin? → A: Not judged. Only the
  project's `.claude/settings.json` wires these two CORE guards.

## Threat model

Trust boundary: **the agent's tool calls → the guards' oracles** (the git dir, the answer store, the sync
script, git itself, the notice stamp) and **mutant code → the developer's environment**. The attacker is
the gated agent (same OS user). Out of model: another OS user, a malicious template, the developer, an
MCP server lying about tool names. STRIDE pass by the `security-scanner` agent on the draft,
2026-10-04 (15 threats). Each is adopted (built here), a recorded bound, or a finding.

### TB1 — trust-anchor pre-check (R1)
- *Adopted (#9):* the pre-check hands `guard_precheck_link` the whole payload, so the payload's `cwd`
  resolves a relative path. A project whose `.git` is a file naming a git dir kept elsewhere has that
  dir guarded too: the pre-check wakes on a path under it, and the parser denies a resolved path under
  it, with or without a link.

### TB2 — answer store (R2)
- *Adopted (#11):* the gate reads the store of the project root, not of the spec directory, and denies a
  spec directory whose real path leaves the root (a symlink into another repository's confirmed spec).
- *Finding (#10):* the digest does not bind a spec id, so cases copied verbatim from a confirmed spec
  confirm a new spec without a new question. Binding it changes every confirmed digest in every
  project; recorded with `finding.sh`, not built here.

### TB3 — CORE guards' evidence (R3)
- *Adopted (#4):* the stamp and the register can be deleted along with the sync script. A third piece
  of evidence cannot be removed without disabling the guard itself: the running hook lives in the sync
  root's `scripts/` (`-ef`). Any one of the three makes a missing sync script a deny.
- *Bound (#5):* a sync script replaced by a stub that answers "nothing is CORE". Writing it is a CORE
  edit this guard refuses; a route that does not reach the guard (a script the agent writes and runs)
  is the 088 bound.

### TB4 — git in the root walk (R4)
- *Adopted (#7):* a CORE guard's R4 announcement is keyed by cause and file, so a slow git that lasts
  the session is heard per file, not once.
- *Bound (#6):* a `.git` git cannot read (exit 128 in milliseconds) reads as an answer. Making the git
  dir unreadable is a write to it, which trust-anchor refuses (fixture: `chmod 000 .git` is denied),
  and a planted bogus `.git` that git rejects is the 091 R6 design, which moves the root up.

### TB5 — mutation sandbox (R5)
- *Adopted (#12):* PATH keeps absolute entries outside the repository and the run directory only.
  `TMPDIR` is the copy's own. The copies are made with `git init --template=` (no developer template).
- *Adopted (#13):* `pushInsteadOf` covers the repository root as given, as resolved, and as a `file://`
  URL. Other spellings (`../repo`, a symlink alias, case variants) are the R5 bound: the sandbox stops
  accidents, not a test written to escape it.
- *Bound (#15):* a test that kills itself with SIGKILL makes the run unmeasured (exit 2). That is the
  safe direction.

### TB6 — notice stamp (R6)
- *Adopted (#8):* the git dir is found from `CLAUDE_PROJECT_DIR` upward (a monorepo package directory),
  through a `.git` file's `gitdir:` line, with builtins. No git dir: said every time, never a TMPDIR
  stamp (sabotage arm).
- *Bound (#8):* `hn_session_id` takes the leftmost `session_id`, the top-level key the harness writes
  first (the adversarial review showed the last one was an MCP input's to choose); a forced empty or
  rotating id makes the guard speak every time, which is noise, not silence.

### TB7 — shell text to a runner (R7)
- *Adopted (#1–#3):* the narrower rule applies only to a plain line: no `(`, `)`, `{`, `}`, `coproc`,
  `exec`, `<(`, `>(`, `<<<` or a descriptor above 2. Any other line keeps today's rule (a runner anywhere
  counts). A pipe joins a pipeline, `|&` included. On a plain line the read's pipeline may hold only
  stdout filters (`grep`, `egrep`, `fgrep`, `wc`, `head`, `tail`, `cut`, `tr`, `nl`, `column`, `jq`,
  `cat`); anything else piped to it (`dd`, `sponge`, `pbcopy`, `command sh`) counts. A runner in
  another list element counts when the read's pipeline writes to a file. Runner detection skips the
  wrappers `! time command builtin nice nohup stdbuf setsid timeout gtimeout caffeinate sudo doas`
  and their options, and `EXEC_COMMANDS` gains `at batch crontab busybox`.

### TB8 — matcher audit (R8)
- *Adopted (#14):* a matcher "matches" only when it is `*`, empty, or fully matches both probe names
  (`mcp__x__write_file`, `mcp__y__edit`) as an anchored regular expression; one that does not compile
  is reported as such. A pass in any PreToolUse group wiring the hook, in `settings.json` or
  `settings.local.json`, is enough.

## Adversarial review (2026-10-04)

`security-scanner` (assume exploitable) and `/security-review` on commit 95b25ee. Each flag, decided:

- *Fixed:* R7-1, a redirect to a file named `2` or `-` read as a descriptor (`grep -l hooks <S> > 7 ;
  xargs rm < 7` allowed, a regression from the old rule). `split_commands` now drops only a dup target
  (`>&2`, `>&-`). An output option (`--output=f`) counts as a spill too.
- *Fixed:* R7-2/R7-3, `$_`, a quote pair hiding `exec`, `e\xec`. The plain test reads the raw text,
  and `$`, a backtick or a backslash makes the line unplain.
- *Fixed:* R7-4 in part. `runs_text` is never weaker than the pre-098 test, and after a wrapper any
  runner name counts (`sudo -u root bash`). R7-6: a pipeline filter must be a bare name.
- *Fixed:* R4-1. Only rev-parse's own codes (0, 1, 128, 129) are answers, so a git killed by SIGTERM
  is unsure.
- *Fixed:* R6-1, a SHA-256 stamp name instead of CRC32. R6-2, the leftmost `session_id`.
- *Fixed:* R1-1, a project whose `.git` is a file sends every path to the parser. R1-2, the pre-check
  reads `notebook_path`.
- *Dismissed:* R1-3. `bash-write-guard` already refuses `ln -s .git gd` in every spelling tried.
- *Recorded:* F175 (pre-098 runner gaps), F176 (PATH shims), F177 (`$(git rev-parse --git-dir)`
  one-liner), F178 (`check` subcommand, `_grandfathered`).

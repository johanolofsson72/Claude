# 095 — guard fail-open sweep

Track: full, hardened. Triggers: a security domain (the guards are the trust boundary between the agent
and the developer's decisions), a new input surface (MCP tool payloads, git revisions read by a guard)
and about ten files. Findings verbatim in `specs/FINDINGS.md`: F114, F115, F116, F118, F120, F121, F135,
plus F145's false positives, which F121 already lists.

Each finding is a guard that allows where its header says it refuses, or a guard that refuses a
harmless call. The second kind matters too: a guard that cries wolf on `sed -n` teaches the agent to
route around it.

## Problem

| Finding | Where | What goes wrong today (reproduced 2026-10-03) |
|---|---|---|
| F114 | `settings_guard.py` `bash_verdict` | A command that names no guarded path is `none` whatever its verb. `git checkout HEAD -- .`, `git restore --source=REV .`, `git stash pop` and `git apply p.diff` rewrite `.claude/settings.json` unjudged |
| F115 | `settings_guard.py:43` | `GUARDED_KEYS` is hooks, disableAllHooks, env. An Edit adding `apiKeyHelper`, `statusLine`, `enabledMcpjsonServers` or `enabledPlugins` passes, and each runs a command or adds tools next session |
| F116 | `.claude/settings.json` matchers (lines 61, 70) | They list built-in tools only. `mcp__*__write_file` reaches the settings files and the trust stores without either guard running |
| F118 | `acceptance_cases.py` | A git timeout fails open with no word (the Confirmed-line backing check and the coverage scan). `_git` inherits `GIT_DIR`, `GIT_WORK_TREE`, `GIT_COMMON_DIR`, `GIT_INDEX_FILE` |
| F120 | `guard-lib.sh` walk, three guards | spec-interview, pipeline-state and spec-register exit 0 when no language marker is found. Deleting or renaming the only marker turns all three off |
| F121 | `settings_guard.py` `reads()` | Env is judged only as a prefix on the same simple command. `export GIT_EXTERNAL_DIFF=…; git diff <settings>` and a function named `cat` defined earlier on the line make a "read" run arbitrary code. False positives: `sed -n 1,5p <settings>` is refused; trust-anchor refuses `--trust` inside a `finding.sh` prose argument |
| F135 | `destructive_command.py` `_TRUST_KEY`; `update-template.sh` REVIEW | `git config core.hooksPath`, `core.fsmonitor`, `core.sshCommand`, `filter.*`, `credential.helper` writes pass. The REVIEW scan does not name changes to `.claude/rules`, `.claude/docs` or `CLAUDE.md`, prompt text that syncs into every project |
| F145 | `bash_write_targets.py` sed; `settings_guard.py` by-name globs | `sed -i '' 's#\.git/config#x#' <scratch>` is denied as a write to `.git/config`: the sed script word is kept as a target. `find … \| xargs grep -o '[a-z]*'` is denied as a settings write: grep's pattern is matched as a file name |

## Requirements

### Settings guard

- **R1 (F114, developer O3).** A git command that rewrites the working tree is judged by what it would
  write. Verbs: `checkout`, `switch`, `restore`, `reset --hard|--keep|--merge`, `stash` (bare, push,
  save, pop, apply, branch), `clean`, `apply`, `am`, `merge`, `rebase`, `cherry-pick`, `revert`,
  `read-tree -u`, `checkout-index`. For each guarded file inside the repository and inside the verb's
  pathspec, the guard reads the content the verb would leave (a revision's blob, the index, nothing for
  a removal) and denies (`settings-git`) when that content differs from the current file on a guarded
  key (R2) or is not a JSON object. For history verbs (`merge`, `rebase`, `cherry-pick`, `revert`) the
  compared pair is the change the verb applies: merge-base → revision, parent → commit, commit →
  parent. A patch (`apply`, `am`) that touches a file named `settings.json` or `settings.local.json`,
  or that the guard cannot read (stdin, a missing file), is denied. Any git call that fails or times out
  denies. `--abort`, `--quit`, `--continue`, `--skip`, `--dry-run`/`-n`, `--check`, `--stat`,
  `--cached` (index only) and `restore --staged` alone are not tree writes. `git pull` from a configured
  remote, or bare, is allowed: what it brings is on origin, in the shared history the developer reads
  (recorded bound). `git pull .` is judged as a merge, a pull from a path or URL denies. Git runs with
  every `GIT_*` variable removed and replace refs and grafts off, as in R5. The threat model adds the
  conflict rule, aliases, same-line ref movers and `--git-dir`/`--work-tree` (see Threat model, TB1).
- **R2 (F115, developer O1).** The guarded keys are inverted: every top-level key is guarded except a
  safe list: `$schema`, `outputStyle`, `language`, `model`, `attribution`, `includeCoAuthoredBy`,
  `cleanupPeriodDays`, and inside `permissions` the keys `allow`, `ask`, `additionalDirectories`.
  `permissions.deny`, `permissions.defaultMode` and any other `permissions` key are guarded. A key
  Claude Code adds later is guarded until someone puts it on the safe list.
- **R3 (F116).** An `mcp__*` tool call is judged by every string in its `tool_input` (nested, capped at
  depth 8 and 512 strings). A string that names a guarded file or directory, as a path or a glob, is
  denied as `settings-shell` (no bytes the guard can replay). The same scan runs in trust-anchor-guard
  for the `.git` stores, acceptance.md and the placement table. The pre-check of both hooks sends every
  `mcp__*` call to the verdict.
- **R4 (F116, the developer's edit).** The template's `.claude/settings.json` matchers for
  trust-anchor-guard and settings-edit-guard gain `|mcp__.*`. The settings guard refuses that edit to the
  agent by design (089 O3), so the developer applies it; `sync-core-hooks.py` carries it into projects.
  `test-hook-channels.sh` gains a fixture: both matchers match `mcp__x__write_file`.

### Acceptance gate

- **R5 (F118, developer O2).** `_git` and the coverage scan's git call drop every `GIT_*` variable
  (`GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE`, `GIT_CONFIG_*` among them; threat model TB4). A timeout in the Confirmed-line backing check denies,
  naming the cause. A timeout in the coverage scan still allows (080 O6), and the hook says so once per
  session through `guard_announce`.

### Language marker

- **R6 (F120).** When the walk finds a register (`specs/INDEX.md`), or the git root holds the sync stamp
  `.claude/.template-sync`, and no language marker, that stands in as the marker, unless
  `template_identity` of the git root says `template`. A missing `template-identity.sh`
  means `project`. The three guards then judge the edit as in any code project. The template repository
  itself stays silent; an impostor clone does not.

### Shell reads

- **R7 (F121).** A read of a guarded file is not trusted when the command text also: exports or
  declares a variable (`export`, `declare`, `typeset`, `readonly`, `local`, `set -a`, `set -o
  allexport`), assigns one as a command of its own (`X=…;`), defines a function or an alias, changes
  how a name resolves (`hash`, `enable`, `shopt`), or sources a file (`source`, `.`). The command naming
  the file is then judged as a write.
- **R8 (F121, F145 false positives).** `sed` is a read when it has no `-i`/`-I`/`--in-place` and every
  script is print-only (addresses with `p`, `=`, `l`, `q`, `Q`, `n`, `d`). grep's and rg's pattern
  argument (the first non-option word, or the value of `-e`/`--regexp`) is not a file name in the
  by-name check. In trust-anchor-guard `--trust` counts as its own shell word, or inside a program
  string handed to a shell, `eval` or an interpreter's `-c`/`-e`, or on a line piped into a shell. Prose
  in a quoted argument does not count.
- **R9 (F145).** `bash_write_targets.py` does not take a `sed -i` script word as a write target when the
  script is made of `s`, `y` and print-only commands with no `w`/`W`/`e` flag or command. A script with
  any of those, or one the parser cannot read, stays a target (today's behaviour). `-e`/`--expression`
  values are script words.

### Git configuration

- **R10 (F135).** trust-anchor-guard denies a persistent `git config` write (any scope: `--local`,
  `--global`, `--system`, `--worktree`, `--file`) to a key that runs a program: `core.fsmonitor`,
  `core.hooksPath`, `core.sshCommand`, `core.pager`, `core.editor`, `core.askPass`, `core.gitProxy`,
  `core.alternateRefsCommand`, `sequence.editor`, `diff.external`, `gpg.program`, `gpg.*.program`,
  `uploadpack.packObjectsHook`, `filter.*`, `credential.*`, `pager.*`, `diff.*.textconv`,
  `diff.*.command`, `merge.*.driver`. A one-shot `git -c` of these stays allowed: it reaches only the
  command it prefixes, which the agent could run anyway (`git -c core.fsmonitor=false status` is in
  update-template itself).
- **R11 (F135).** `update-template.sh`'s REVIEW scan also names every changed or new file under
  `.claude/rules`, `.claude/docs` and `CLAUDE.md`: prompt text that syncs into every project.

### Docs and verification

- **R12.** Guard headers state the new rules and bounds. The register row's findings are closed with
  `finding.sh`. F145 is closed by R8/R9.
- **R13.** Every R has a fixture in the guard's self-test and a sabotage arm where a mutant could pass
  unnoticed. The mutation gate covers `settings_guard.py`, the changed part of `acceptance_cases.py`,
  `destructive_command.py`'s trust judge and `bash_write_targets.py`'s sed rule.

## Out of scope

- `git pull` (R1 bound). The developer reads origin; a crafted commit pushed there is in the shared
  history.
- A program that writes a settings file it was not handed on the command line (the 089 bound), and
  names assembled at runtime.
- MCP read tools against secrets (sensitive-file-guard's matcher). F116 is about writes to the settings
  files and the trust stores.
- `.mcp.json` as a file the agent may write. Project MCP servers in it still need the developer's
  approval in the client, or `enableAllProjectMcpServers`/`enabledMcpjsonServers`, which R2 now guards.
- The developer's own git aliases. `alias.*` writes are already trust-anchor's (091).
- F144 (the announce stamp under TMPDIR) belongs to row 096.

## Success criteria

- SC-1: each reproduced bypass in the Problem table is denied, and each reproduced false positive is
  allowed, by the guard's self-test.
- SC-2: `git checkout HEAD -- .` with an unmodified settings file, and `git stash pop` of a stash that
  does not touch it, are allowed.
- SC-3: the template repository's own edits stay unguarded by the three pipeline guards (R6), and a
  copy of it with a different root commit is guarded.
- SC-4: the full template suite is green; the mutation gate meets the hardened bar on the changed
  modules.

## Functional coverage

| Function | Test |
|---|---|
| R1 git tree verbs | `test-settings-edit-guard.sh` section 095-R1 (fixture repo, one case per verb, allow and deny) |
| R2 safe list | `test-settings-edit-guard.sh` section 095-R2 |
| R3 MCP scan | `test-settings-edit-guard.sh` 095-R3, `test-trust-anchor-guard.sh` 095-R3 |
| R4 matchers | `test-hook-channels.sh` matcher-coverage section |
| R5 git env, timeout split | `test-acceptance-cases.sh` 095-R5 |
| R6 register as marker | `test-guard-lib.sh` 095-R6, plus one end-to-end case in `test-pipeline-state-merge.sh` |
| R7 prelude distrust | `test-settings-edit-guard.sh` 095-R7 |
| R8 read false positives | `test-settings-edit-guard.sh` 095-R8, `test-trust-anchor-guard.sh` 095-R8 |
| R9 sed script word | `test-bash-write-guard.sh` 095-R9 |
| R10 exec keys | `test-trust-anchor-guard.sh` 095-R10 |
| R11 REVIEW scan | `test-update-template.sh` 095-R11 |

There is no UI. The "four states" read as: allow with no output (success), deny with a reason that
names the cause and the developer's route (error), a call with nothing to judge (empty, exits 0), and a
guard that cannot decide (fail-closed deny, or announce where O2/O6 keep fail-open).

## Clarifications

### Session 2026-10-03

- Q: Does the R2 safe list differ between the three files? → A: No. One list for all three. The
  local and config-dir files load the same keys.
- Q: R3 hits its cap (depth 8, 512 strings) on a huge MCP payload. Deny? → A: Only if the payload's
  raw text still says `sett` or `.cla` (case folded). Past the cap the guard has not looked at every
  string, and that is the same pre-check every other call gets.
- Q: R1 `git checkout <branch>` with an uncommitted settings change. → A: Compared like any other
  source: current file against the branch's blob. Git may refuse the switch itself; the guard does
  not rely on it.
- Q: R6 cost in the template repo. → A: `template_identity` runs only when a register was found and
  no marker was, so a code project pays nothing. The template pays one `git config` and one
  `rev-list` (about 22 ms) per guarded edit.
- Q: R7 assignment inside `$( … )` or a subshell. → A: Counts. The text is scanned whole; the
  guard does not track which shell a variable lives in.
- Q: R10 `git config --unset core.hooksPath`. → A: Denied too. An unset can switch a developer-set
  value back to git's default, and only the developer decides that.

## Threat model

Trust boundary: **the agent's tool calls → the hook wiring, the trust stores and the pipeline guards'
own inputs.** The attacker is the gated agent (same OS user). Out of model: another OS user, a
malicious template, the developer, an MCP server lying about its own tool names (the developer
configured it). STRIDE pass by the `security-scanner` agent on the draft, 2026-10-03; each design gap
it found is either adopted below (built in this spec) or an open question for the developer.

### TB1 — git verbs → settings files (R1)
- **Tampering by merge.** Both sides change the file, git leaves conflict markers, and Claude Code drops
  every hook. *Adopted:* a history verb whose base→target change meets a current file that differs from
  both is denied (`conflict markers`).
- **Tampering through pull.** `git pull . evil`, `git pull /tmp/forge main` are not origin. *Adopted:*
  a pull is allowed only from a configured remote name or bare; `.` is judged as a merge; anything else
  denies.
- **Other trees.** `--git-dir`, `--work-tree`, a `GIT_*` prefix, `-C`. *Adopted:* the first three deny on
  a tree verb; `-C` is followed.
- **Closed verb list.** Aliases are resolved once through `git config --get alias.*` (a `!` alias is a
  shell command, judged by the other guards); `sparse-checkout`, `submodule`, `filter-branch`, `bisect`
  deny when a guarded file is in the repository. `git rm`/`git mv` name the file and are not reads.
- **TOCTOU on one line.** `git update-ref … && git checkout x -- .` *Adopted:* a tree verb on a line with
  any git command outside a still-list (status, diff, log, show, add, …) denies.
- **Patch names.** *Adopted:* `git apply --numstat -z` names the paths as git reads them, together with
  the hand-read headers.
- **Open (bound):** the window between the check and the call when the developer edits the file
  (interview Q12).

### TB2 — settings keys (R2)
- **Repudiation and widening through the safe list.** `cleanupPeriodDays: 0` purges transcripts,
  `attribution`/`includeCoAuthoredBy` strip authorship, `outputStyle` names a file the agent can write,
  and a wildcard `permissions.allow` widens what runs without asking. *Open:* developer decision (O1 set
  the list).

### TB3 — MCP payloads (R3, R4)
- *Adopted:* object keys are scanned; runs of 2–4 neighbouring strings are joined with `""` and `/`;
  `file://` and `~` are expanded; a command-shaped string is judged as Bash by both guards. A tool whose
  last name segment says it reads is left to the read rules.
- **R4 not applied** in projects that never sync. *Open:* a maintenance check for a missing `mcp__`
  matcher.

### TB4 — acceptance gate (R5)
- *Adopted:* every `GIT_*` variable is dropped, not a list of them.
- **Forced coverage timeout** still allows (O2 keeps 080 O6), now announced. *Open:* developer decision
  on allowing once per digest.

### TB5 — marker walk (R6)
- *Adopted:* the sync stamp `.claude/.template-sync` stands in as well as the register, and identity is
  asked of the git root, not the file's directory.

### TB6 — shell reads (R7, R8)
- *Adopted:* a read command runs only by bare name or from a system bin directory; `sed` long options
  are resolved by GNU's prefix rule and an unknown option is a write; `--trust` as an assignment value
  counts.

### TB7 — git config (R10)
- *Adopted:* `init.templateDir`, `core.worktree`, `core.attributesFile`, `interactive.diffFilter`,
  `gpg.ssh.defaultKeyCommand`, `submodule.*.update`, `difftool.*.cmd`, `mergetool.*.cmd`,
  `trailer.*.cmd`, `sendemail.*` commands, and any key spelled at runtime.
- *Open:* inverting to an allowlist of benign keys (developer decision).

### Adversarial review (hardening step 4), 2026-10-03

`security-scanner` in assume-exploitable mode found ten more shapes on the built code; all are fixed,
each with a fixture named `#n` in the guard's self-test: dry-run flags judged per verb (`merge --stat`
and `cherry-pick -n` write), git behind `env`/`timeout`/`xargs`/`bash -c`/a heredoc to a shell and
through a one-shot `-c alias.*`, any `GIT_*` on a tree-verb line, `checkout-index --stdin`, `git am`
(not modelled, denies), bash comments stripped before lexing (a `# '` pair hid a command), `git rm`,
`git grep -O` and `git --git-dir` on a read, dotted config subsections and `.path` tool keys, a sed `w`
without `-i`, read-named MCP tools that also write (`find_and_replace`), percent-encoded file URLs, and
`--trust` behind `-xc`, a here-string or in a list literal. A ref mover counts only before the tree
verb it would feed, so `git rm x && git commit` stays allowed.

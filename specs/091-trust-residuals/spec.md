# 091 — trust residuals

Track: full, hardened. Trigger 1: the change is the trust layer under the template sync, the nightly
and the acceptance gate (a new external API surface: GitHub's compare endpoint). Trigger 3: the row is
tagged. Trigger 4: well over 6 files.
Findings: F079 F080 F092 F095 F097 F104 F107, verbatim in `specs/FINDINGS.md`.

## Problem

Specs 082, 088 and 090 moved most trust decisions off state the agent can write. Seven places still
rest on it. Each was traced on 2026-10-02 against 982cf1e:

| Finding | What decides | Who can write it | Effect |
|---|---|---|---|
| F097 | `remote get-url origin` matching `*johanolofsson72/Claude*` | the agent (`git remote set-url`, `git config remote.origin.url`, `url.*.insteadOf`) | core-machinery-guard and core-owed-tick-guard exit 0 (the template exemption); autosync treats the project as the template and never syncs it |
| F097 | the same pattern, unanchored | anyone naming a repo `evil-johanolofsson72/Claude` or `Claude-x` | the same exemptions |
| F079 | `CLAUDE_TEMPLATE_PIN` = any 40-hex SHA | whoever sets the project env | codeload serves a commit from any fork in the template's network under the template's URL; the tarball's commit id matches, so it syncs |
| F079 | `git status --porcelain` is clean | a template clone with `skip-worktree` / `assume-unchanged` bits, or ignored files under `.claude/skills/` | bytes that are not the commit's ship into every project, stamped with the clean SHA |
| F080 | `--disallowedTools` path rules, repo-relative | an injected `claude -p` in update-template.sh | it can still Write `~/.claude/settings.json`, `~/.zshrc`, `.mcp.json`, or add a `hooks:` key to a skill or agent's frontmatter |
| F092 | sha256 of the `.suite-command` line | the agent edits or adds `scripts/test-*.sh` | the line is unchanged, so the trusted hash is unchanged, and the new test body runs at 02:30 |
| F095 | any well-formed `stamp` line on `claude/maintenance-results` | anyone who can push a `claude/*` branch, including the agent | `--pull` stamps `secrets` done; the scan never runs |
| F095 | `.claude/workload-placement.tsv` | the agent | routes `secrets` (or anything) to cloud, so the local pass skips it |
| F104 | the answer store binds an answer's hash to a digest the question showed | the agent writes the question | an unrelated question that shows the digest, answered "No", lets `--confirm --quote "No"` through |
| F107 | a Confirmed line equal to the one at `HEAD` is trusted | the agent commits | a forged line that reached disk by a route no guard reads (a script file) is laundered by one local commit |

The common root: a check compares against something in the working tree, the git dir or the env that
the agent's own tools can change. Each fix below moves the check to something the agent cannot
cheaply produce (the template's root commit, the template's `main` on GitHub, the developer's click on
a fixed option, the upstream ref) or narrows what the writer can reach.

## Requirements

- **R1 — The template is its history, not its URL (F097).** One function, `template_identity DIR`
  in a new `scripts/template-identity.sh` (sourced, CORE), answers `template`, `impostor` or
  `project`:
  - `template`: origin's URL matches, anchored, one of `https://github.com/johanolofsson72/Claude`,
    `git@github.com:johanolofsson72/Claude`, `ssh://git@github.com/johanolofsson72/Claude`, each with
    an optional `.git` and an optional trailing `/`; AND the root commits of `HEAD`, read with
    `--no-replace-objects` and `GIT_GRAFT_FILE` pointing at a file that does not exist, are exactly
    `d3cf8238372ce7a37d5d66b115cbcbf9d57bb2b9`.
  - `impostor`: the URL matches and the history does not (a shallow clone of the template lands
    here too).
  - `project`: anything else, including no git, no origin, or a missing library.
  core-machinery-guard and core-owed-tick-guard exempt only `template`. template-autosync.sh and
  template-autosync-hook.sh skip only `template`; on `impostor` they write nothing and warn once
  (`[warn] origin names the template but HEAD's history is not the template's — not syncing`).
  `--owed` is the exception: it reads only the project's manifest, and core-owed-tick-guard fails
  open on "cannot answer", so an impostor answers it as a project (found while testing 091-AC-1).
  `refresh_local_template` uses the anchored URL match only (it asks "is this clone ours to fetch",
  not "is this the template").
- **R2 — Changing what origin points at is the developer's step (F097).** trust-anchor-guard denies
  a Bash command that writes a remote's URL: `git remote add|set-url|rename|remove|rm`, and
  `git config` (any scope) setting `remote.<name>.url`, `remote.<name>.pushurl`,
  `url.<base>.insteadOf` or `url.<base>.pushInsteadOf`. Reading (`git remote -v`, `get-url`,
  `git config --get`) is allowed. It also denies a local rewrite of a remote-tracking ref, which
  R9 trusts (Allium finding 3, fixed now): `git update-ref` in any form, and a `git fetch` or
  `git push` whose explicit refspec writes `refs/remotes/`.
- **R3 — A pin must be on the template's main (F079).** With `CLAUDE_TEMPLATE_PIN` set:
  - a local clone is used only when its HEAD is the pin, it is clean (R4), and
    `git merge-base --is-ancestor PIN refs/remotes/origin/main` holds in the clone (no fetch);
  - otherwise, before any download, GitHub's compare API
    (`https://api.github.com/repos/johanolofsson72/Claude/compare/<pin>...main?per_page=1`, https
    only, 30 s) must answer `status` `ahead` or `identical` and `merge_base_commit.sha` equal to the
    pin, parsed as JSON by python3. Any other answer, no answer, or no python3: nothing is
    downloaded or written, and the run warns
    `[pin] cannot show CLAUDE_TEMPLATE_PIN <12> is on the template's main (<reason>) — not synced`.
- **R4 — A clean clone ships its committed bytes (F079).** When the template comes from a local
  clone (pinned or not):
  - every path `git ls-files -v` marks skip-worktree (`S`) or assume-unchanged (a lower-case tag)
    joins the committed-bytes list that spec 007bi stages from the index, with one warning naming
    them;
  - the skills copy enumerates `git ls-files -- .claude/skills` instead of `find`, so an ignored
    file under `.claude/skills/` is never shipped. A tarball (no `.git`) keeps `find`.
- **R5 — update-template.sh confines the model to the repository (F080).** `claude -p` runs with
  `--restricted` (file tools confined to the working directory, user/project/local settings ignored,
  bypassPermissions refused, settings/git/tool-config writes need a person),
  `--permission-mode dontAsk`, and `--tools` naming exactly the allowed list (restricted mode drops
  WebFetch unless `--tools` names it). The existing allow and deny lists stay, plus
  `Edit(.mcp.json) Write(.mcp.json)`. Before starting, the script checks `claude --help` mentions
  `--restricted`; when it does not, it refuses (exit 2, "update Claude Code"). After the run, any
  changed or new file under `.claude/skills/` or `.claude/agents/` whose YAML frontmatter holds a
  `hooks:` key is named with `[REVIEW]` and the script exits 4, after printing the diff.
- **R6 — The suite's identity includes the files it runs (F092).** `suite_identity` appends, after
  the command text (and, for `npm test`, after the script string), one line per file reached by a
  path-like token of that text: `<git blob hash>  <path>`, sorted by path. A path-like token holds a
  `/` and is expanded as a bash glob from the repository root; a match that is a directory adds every
  regular file under it, `.git` excluded. A token that matches nothing adds nothing. Hashing is one
  `git hash-object --stdin-paths` process. The `--trust` display shows the same text, so the person
  sees each file.
- **R7 — A cloud stamp counts only for a job placed in the cloud; secrets never are (F095).**
  - `workload-placement.sh --place secrets` prints `local` whatever either table says; a table line
    placing it in `cloud` warns once on stderr (`secrets is always local: ...`).
  - `cloud-maintenance.sh --pull` imports a `stamp` for job J only when
    `workload-placement.sh --place J` answers `cloud` on this machine; otherwise it skips the line
    (`skipped <file> stamp J — J runs locally here`) and counts it. Ledger lines still import (they
    are history, not a stamp).
  - trust-anchor-guard denies an Edit/Write/MultiEdit/NotebookEdit of
    `.claude/workload-placement.tsv` and a Bash write naming it (the bash-write-guard delegation).
    The developer edits it in their own editor or with `!`.
- **R8 — Only a click on Confirm, to a question that showed the cases, binds a digest (F104).**
  `record_answers` records a digest for an answer only when (a) the digest is on disk (as today),
  (b) the question text, whitespace-collapsed, equals what `--question` prints for the acceptance.md
  with that digest (every case in full; /simplify replaced a substring match with equality, which is
  stricter and one definition instead of two), and (c) the answer, collapsed, equals `Confirm`
  ignoring case.
  Any other answer is recorded without a digest. `acceptance-cases.sh --question <spec-dir>` prints
  the question text (digest, every case in full) and the option label to use. HOW_TO_CONFIRM,
  NOT_BOUND and the docs teach `--question` and `--quote "Confirm"`.
- **R9 — A committed Confirmed line is trusted only once it is upstream (F107).** The gate's
  "already committed" shortcut compares the working-tree Confirmed line with the one at
  `@{upstream}`, not `HEAD`. No upstream configured: no shortcut, the answer store must back it.
  The gate's failure rules are unchanged (timeout fails open, any other git error denies).
- **R10 — CORE and docs.** `template-identity.sh` and its test join `CORE_SCRIPTS`. The docs that
  describe each changed behaviour say what it does now: `.claude/docs/security.md`,
  `.claude/docs/spec-interview-rationale.md` (confirm flow), `.claude/rules/spec-interview.md` (one
  word: `--question` for `--digest`), `.claude/docs/workload-placement.md`,
  `.claude/docs/template-autosync.md` (pin).

## Out of scope

- A signature check on `claude/maintenance-results` commits. A cloud routine's commit carries no key
  the Mac can verify, and author fields are free text. R7 shrinks what a forged stamp can mark to
  the jobs the developer placed in the cloud; the residual is recorded.
- Hashing what a test script sources (`guard-lib.sh` under `test-guard-lib.sh`). R6 covers the files
  the command names; the transitive closure of `source` is a parser of its own.
- Proving meaning. R8 binds the developer's click on a fixed label to a question that showed every
  case; a question that shows the cases and then misdescribes them is the residual 088 already named.
- Pushing a forged Confirmed line for real (R9). It is visible in the shared history and is the
  developer's own push route; R2 closes the local ref rewrites.

## Clarifications

### Session 2026-10-02 (auto-picked, recommended option; measured where it could be)

- Q: Does `--no-replace-objects` alone defeat a faked root? → A: No. Measured with git 2.53: a
  `.git/info/grafts` naming HEAD as parentless still makes HEAD the root under
  `--no-replace-objects`; `GIT_GRAFT_FILE=<missing file>` restores the true root. R1 sets both.
- Q: What exit code does autosync give on `impostor`? → A: 0. It runs from SessionStart and fails open
  for the session; the warning is the signal. Nothing is written, staged or pushed.
- Q: R2, is `git remote add upstream …` denied too? → A: Yes (O1: all remote writes). So is
  `git remote rename` and `remove`, which can move another remote's URL onto `origin`.
- Q: R2, does `git config --unset remote.origin.url` count? → A: Yes; any `git config` write whose key
  is one of the four. `--get`, `--get-all`, `--list` and `-l` are reads.
- Q: R3, what if `python3` exists but the API answers 403 (rate limit) with a JSON body? → A: The
  status field is absent, so the proof fails and the reason names the HTTP answer's `message`.
- Q: R5, which exit code wins when claude itself fails and a `hooks:` key also appears? → A: claude's.
  Exit 4 is only for a run claude finished with 0, so a failed run is never misreported as a review.
- Q: R6, is a token like `$HOME/x` or `"scripts/test-*.sh"` path-like? → A: Quotes are stripped first;
  a token holding `$`, a backtick or `..` adds nothing (it cannot be expanded honestly from here).
- Q: R6, is a directory token's file list bounded? → A: At 2000 files; past that the identity carries
  a `… truncated` line, which still changes when any listed file does.
- Q: R7, a ledger line for `secrets` from the cloud? → A: Imported. The ledger is a record of what ran
  where; only a stamp marks a job done.
- Q: R8, how exact is "showed the cases"? → A: The whole question equals the `--question` text,
  whitespace collapsed. Any other wording, an added sentence included, binds nothing.
- Q: R9, which ref is `@{upstream}` in a detached HEAD? → A: There is none, so no shortcut; the store
  must back the line.

## Threat model

`security-scanner`, pre-implementation STRIDE pass, 2026-10-02 (32 items over TB1–TB9). Each item is
adopted as an amendment below (it binds the implementation like the R it names) or recorded as a
residual. The numbers are the scanner's.

### Amendments (adopted)

- **A1 (TB1 #1, #2, #3, #5).** R1 reads the raw `git config --local --get remote.origin.url` (never
  `get-url`, which applies `insteadOf`), compares it lower-cased, and runs the root walk with
  `-c core.commitGraph=false`. R2 is defence in depth: the root commit is the control.
- **A2 (TB2 #7–#11).** R2's precheck gains the trigger words `remote`, `config`, `update-ref`,
  `insteadof`, `refs/remotes`, `symbolic-ref`, `workload-placement`. The verdict tokenises each command
  segment, takes the first word's basename (through `command`, `env`, `exec`, `xargs`), skips git's
  global options (`-C x`, `-c k=v`, `--git-dir=`, `--work-tree=`, `--no-pager`, `-p`), and denies:
  `remote add|set-url|rename|remove|rm|set-head` (any flags); `config` writes (anything but
  `--get*`, `--list`, `-l`, `get`, `list`, or a lone key) on a key, folded, under `remote.`, `url.`,
  `branch.`, `include`, `alias.`, and `--rename-section`/`--remove-section` on those;
  `update-ref`, `symbolic-ref`; `fetch`/`push` with a refspec whose destination is under
  `refs/remotes/` or `remotes/`, or `refs/*`. `bash -c`/`sh -c` bodies are read the way
  destructive_command.py already reads them.
- **A3 (TB3 #13, #14).** curl gets `-q` (no `~/.curlrc`) and a 2 MB cap; the JSON check requires
  `status` and `merge_base_commit.sha` to be strings at the top level.
- **A4 (TB4 #16–#18).** R4's flag list takes `S`, `s` and every lower-case tag from
  `git -c core.fsmonitor=false ls-files -v -z`. The skills list comes from `ls-files -s -z` and keeps
  modes 100644/100755 only, so a tracked symlink or gitlink is never copied.
- **A5 (TB5 #19–#21).** The help probe matches `^[[:space:]]*--restricted\b`. The review scan covers
  changed and new files under `.claude/skills/`, `.claude/agents/` and `.claude/commands/`: a
  frontmatter key `hooks`, `allowed-tools`, `permissionMode` or `mcpServers` (quoted or not), and any
  changed file that is not markdown. `[REVIEW]` lines print whatever claude's exit; exit 4 only
  replaces a 0.
- **A6 (TB6 #22–#25).** R6 also hashes a token without `/` that names a regular file at the root. A
  token holding `/` together with `$`, a backtick or `..` makes the identity unreadable, so the suite
  is never trusted (a new finding line says why). Past 2000 files the identity is unreadable too. A
  path with a newline is unreadable. Hashing uses `--no-filters`; sorting `LC_ALL=C`.
- **A7 (TB7 #28).** A stamp whose `--place` answer is anything but `cloud` (including exit 3) is
  skipped.
- **A8 (TB8 #29, #30).** R8(b) requires every case's full text, not only its title: the question must
  be exactly the `--question` text, which carries the heading and the Given, When and Then lines of
  every case. Answers come from `tool_response` only.
- **A9 (TB9 #31, #32).** R9 first asks `rev-parse --symbolic-full-name @{upstream}`; no upstream, or
  one not under `refs/remotes/`, means no shortcut (not a git error). The read is
  `git --no-replace-objects show <upstream>:<path from the root>`.

### Residuals (recorded with finding.sh)

- TB1 #4: an agent can make a project the template honestly (fetch the template, reset onto it, set
  the URL with `!`-free spellings R2 misses). It then has the template's files, not the project's.
- TB2 #12 / TB7 #27: `.claude/workload-placement.tsv` is tracked, so `git checkout`, `stash pop` or a
  script file change it with no command naming it. Only `secrets` is unconditionally protected; the
  other cloud stamps rest on placement staying a human decision.
- TB5 #19: Read plus WebFetch inside the repository (a `.env` the deny list does not name) is still an
  exfiltration channel for update-template's model.
- TB6 #26: the suite files are hashed at trust time and read again at 02:30 (the 082 private copy
  covers only the runner script).
- TB2 #10: `git branch -u`/`push -u` can set an upstream; A9's `refs/remotes/` check plus R2's
  `remote add` deny keep it on a real remote's tracking ref.

### Adversarial review (2026-10-02)

`security-scanner` in "assume it's exploitable" mode traced 11 bypasses by reading (its shell was
off, so nothing was executed); each fixed one is now a test arm that runs the real hook:

- B1 `git -c remote.origin.url=… fetch`, `--config-env`, and `GIT_CONFIG_COUNT/KEY/VALUE/PARAMETERS`
  (prefix, `env`, `export`) moved what a fetch writes into `refs/remotes`: denied.
- B2 a refspec destination with `*` or `remotes` anywhere (`refs/rem*`): denied.
- B3 `fast-import`, `fetch-pack`, `receive-pack`, and `send-pack` with a tracking refspec: denied.
- B4 git-core's dashed binaries (`git-update-ref`, `git-remote`, `git-config`): judged as git.
- B5 `find -exec git …`: the judge is carried into the exec body.
- B6 `--attr-source`, `--super-prefix`, `--list-cmds` take a value: skipped correctly.
- B7 a clean clone at the pin whose origin is a fork: the local shortcut also requires the
  template's URL, else the compare API decides.
- B10 (part) a first frontmatter line of `--- ` (trailing space) still opens the frontmatter.
- Recorded: B8 (other copy loops still glob the clone, F133), B9 (suite tokens after `cd`, glued to
  flags, in braces, or behind a runner that names none, F134), B10/B11 (rules/docs/CLAUDE.md not in
  the review scan; core.fsmonitor and friends not in the config denylist, F135).

### /simplify (2026-10-02)

Four reviewers (reuse, simplification, efficiency, altitude). Applied: one recursion path in
`judge_words` (it also stopped `sudo git remote …` slipping past), a flatter `git config` decision, a
3-pattern URL check after normalising, `pin_on_main` without its dead clone branch, one
`checkout-index` helper, the EOL report inside `stage_clone_divergence`, `paste` pairing in
`suite_identity`, a narrower guard precheck (the colon trigger sent most git commands to python), a
lazy import, a shared `path_hits`, and R8's exact match. Skipped as wider redesigns: a `local-only`
placement kind, a python tokenizer for suite tokens, `ls-remote` in a PreToolUse gate, an identity
cache. `sync-prompt.md` keeps the unanchored match (F132).

### /tla (2026-10-02)

`ConfirmTrust.tla`: the agent edits cases, forges a line by script, commits; the developer answers
Confirm to the `--question` text or No to anything, and pushes only what they confirmed.
`NoUnconfirmedCode` (the gate opens only on cases the developer confirmed) holds under the 091 rules,
88 distinct states (`ConfirmTrust_NEW.cfg`). Each pre-091 rule alone breaks it:
`ConfirmTrust_OLDRECORD.cfg` (Forge, then No to a digest-bearing question: F104) and
`ConfirmTrust_OLDSHORTCUT.cfg` (Forge, edit, local commit: F107). Template identity is a pure
three-way function and passed the triviality gate. Findings: Allium drift (A5, A6, A9 and the
`--owed` exception were built but not in `spec.allium`), resolved by updating the spec; GAP-1 (no
gate-level arm for the OLDRECORD trace), fixed with a test.

### /security-review (2026-10-02)

No finding at confidence 8 or above. Below the bar and fixed anyway: R9's shortcut resolved the
upstream path through a symlink, so an acceptance.md linked to another spec's pushed file could
match; a linked acceptance.md now gets no shortcut.

### Mutation gate (2026-10-02)

`run-mutation-gate.sh`, seed 20261002, with a 091 target table (each module's own tests). First
pass: 64.7 % on the five small modules and 66.7 % on the changed lines of template-autosync.sh and
project-maintenance.sh. Most survivors were `exit 0 → exit 1` in hooks whose tests read only the JSON,
and error branches nothing drove (no curl, no python3, no temp file, a flagged path that cannot be
staged, a tarball's skills, a directory token, the 2000-file cap, a newline in a name). The
trust-anchor harness now reports a non-zero hook exit as its verdict, unit arms extract the new
functions, and two unreachable checks carry `# mutant-equivalent` with the reason. Final, same seed:
**86.3 % (44/51)** over template-identity (100 %), update-template (100 %), workload-placement
(91.7 %), cloud-maintenance (66.7 %) and trust-anchor-guard (83.3 %), and **94.0 % (79/84)** on the
changed autosync (96.5 %) and maintenance (88.9 %) lines. cloud-maintenance's four survivors and
trust-anchor's line 91 are in code 091 did not change (F136). The other survivors are a `mktemp`
fallback, `return 3 → return 0` after a refused clone (nothing is written either way), and three
suite_identity exits that the caller's untrusted path also reaches.

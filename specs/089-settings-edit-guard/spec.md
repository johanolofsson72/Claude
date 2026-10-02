# 089 — settings edit guard

Track: full, hardened (trigger 1: the change is the authorization layer under every hook; trigger 3:
the row is tagged; trigger 4: a new hook script, a new verdict module and wiring across ≥ 6 files).
Findings: F081 and F103, verbatim in `specs/FINDINGS.md`. Folded into this row at the 2026-10-02
findings review.

## Problem

Every gate this template has is a PreToolUse hook wired in a settings file, and a settings file is
plain JSON that the agent being gated can write:

- **F081 (083 adversarial #15).** One Edit of `.claude/settings.json`, or a `sed -i`, removes every
  PreToolUse hook. Nothing guards the file. The finding asked for a decision: guard it like CORE, or
  accept it as the developer's kill switch.
- **F103 (088 adversarial #11).** The same holds for `.claude/settings.local.json`, which is
  gitignored, so the change does not even show in a diff. An `env` entry there sets
  `SPEC_ACCEPTANCE=off` or `ALLOW_CORE_MACHINERY_EDIT=1` for the next session, and an unwired
  `trust-anchor-guard` reopens everything 088 closed. `core-machinery-guard` exempts the template
  repository itself, so here not even the CORE scripts are covered.

`~/.claude/settings.json` belongs on the same list. It also carries `hooks` and `env`, and
`"disableAllHooks": true` in any of the three files switches every hook off at once.

The developer decided (2026-10-02, O1–O4): guard the three files this session and the next one load,
judge only the keys that decide which hooks run and what environment they see, offer no override
variable, and apply the guard in the template repository too.

## Requirements

- **R1 — The guarded files (O1).** A path is guarded when, after resolving symlinks, folding case
  where the file system does (macOS, Windows) and normalising Unicode to NFC, it is one of:
  - `<project>/.claude/settings.json`
  - `<project>/.claude/settings.local.json`
  - `<config>/settings.json`

  `<project>` is `CLAUDE_PROJECT_DIR` when set, otherwise the payload's `cwd`. `<config>` is
  `CLAUDE_CONFIG_DIR` when set, otherwise `~/.claude`. A file that does not exist yet is guarded by
  its path, and a hard link to an existing guarded file is guarded by its inode. Another project's
  settings (the wizard writing a new repository's) are not guarded.
- **R2 — The guarded keys (O2).** `hooks`, `disableAllHooks` and `env`, at the top level of the
  JSON object. A write is a **guarded change** when the value of any of the three (deep equality,
  absent counts as a value) differs between the file's current content and the content after the
  write. A missing or empty file reads as `{}`. Everything else (`permissions`, `outputStyle`,
  `statusLine`, `enabledPlugins`, formatting) stays writable by the agent.
- **R3 — The Edit route is judged on the bytes.** A new `scripts/settings-edit-guard-hook.sh` on
  PreToolUse, matcher `Edit|Write|MultiEdit|NotebookEdit|Bash`, with its verdict in
  `scripts/settings_guard.py`. For a Write, Edit or MultiEdit of a guarded file it applies the call to
  the current bytes, as the tool would (an `old_string` that is missing, or not unique without
  `replace_all`, fails the tool and changes nothing), and denies when:
  - the result is a guarded change (`settings-key`);
  - the result is not a JSON object as `JSON.parse` reads it (`settings-invalid`): Claude Code drops
    a settings file it cannot parse, which takes every hook in it along. `NaN` and `Infinity`, which
    Python's `json` accepts and `JSON.parse` does not, count as unparseable (/tla D4);
  - the current content is not a JSON object (`settings-unreadable`): there is nothing to compare
    against, and the developer repairs the file;
  - the call carries no bytes it can simulate: a NotebookEdit, a path with a glob character, or a
    payload with only a `file_path`, which is how `bash-write-guard` delegates a shell write
    (`settings-shell`).

  A write that leaves all three keys equal is allowed and says nothing.
- **R4 — The shell route is judged on the command text.** For Bash, the command is decoded (`$'…'`
  escapes), heredoc bodies are attached to the command that opens them, and it is split into words
  and simple commands (`;`, `&&`, `||`, `|`, `&`, newlines, parentheses, backticks, and the
  `$(`, `>(` and `<(` that open a substitution, /tla D2). A word **names a guarded
  file** when:
  - resolved against the payload's `cwd`, or against any `cd`/`pushd` argument or `-C`,
    `--work-tree`, `--directory`, `--git-dir` value joined to it (after `~`, `$HOME`, `${HOME}`, `$CLAUDE_PROJECT_DIR` and
    `$CLAUDE_CONFIG_DIR` are expanded, and after `NAME=` is cut from an assignment), it is a guarded
    file or the `.claude` / config directory that holds one;
  - it carries a glob character and matches a guarded file or such a directory, absolutely or
    relative to `cwd`;
  - the command moves into a guarded directory, or into one it cannot resolve (a `$`, a backtick or a
    glob in the target), and the word's last component matches `settings.json` or
    `settings.local.json` (case folded, globs honoured), or the word is made only of dots and
    slashes. After `find`, `fd`, `xargs`, `rsync`, `tar` or `zip` the name rule applies without the
    dots rule. A `cd` into an ordinary directory changes neither (/tla D3: `cd x && cp y .` passes);
  - its last component still holds a `$`, a backtick or `$(` after expansion and its directory part is
    a `.claude` / config directory that holds a guarded file.

  A simple command that names a guarded file is allowed only when it reads: it has no leading
  `NAME=value` assignment (`LESSOPEN=… less`, `GIT_EXTERNAL_DIFF=… git diff` run a program on the
  file, /tla D1), and its command word is one of `cat head tail less more grep egrep fgrep rg jq wc diff
  cmp ls stat file shasum sha1sum sha256sum md5 md5sum test [ realpath readlink basename dirname echo
  printf`, or `python3 -m json.tool` with exactly one operand, or `git` with the subcommand `diff log
  show status blame add commit ls-files grep check-ignore rev-parse cat-file` and no `-c`,
  `--config-env` or `--exec-path` (D1). `rg --pre` is not a read (D1). Inside a read, a naming word
  that is itself an option (`--output=<file>`) or follows `-o`, `--output`, `--output-file` or
  `--output-directory` is a write (/tla D5). Three data-flow rules close the route from a read's
  output into a command (/security-review): an assignment alone that names a guarded file is a
  write (`p=<file>; sed -i … "$p"`); a read inside `$(…)`, backticks, `>(…)` or `<(…)` is a write;
  and a read in a command line that also runs `sh bash zsh dash ksh fish eval source . exec xargs
  env python python3 perl ruby node php awk osascript parallel` is a write. A heredoc delimiter is
  read by bash's rule (any word, quotes and backslashes removed, so `<<\EOF` and `<<E\OF` count),
  and an opener with no delimiter attaches the rest of the text. A word that follows
  a redirection operator (`>`, `>>`, `>|`, `&>`, `&>>`, `<>`) and names a guarded file is a write
  whatever the command word. Anything else is denied (`settings-bash`), and the deny never echoes
  the command (`bash-write-guard` FR-015). Text that cannot be split (an unbalanced quote) is denied
  when it holds `settings` or `.claude`, case folded.
- **R5 — Every shell write that bash-write-guard extracts reaches it.** `settings-edit-guard-hook.sh`
  joins `BASENAME_GUARDS` in `bash-write-guard-hook.sh`, with its own lead line, so a target the
  extractor finds (also in the opaque pass) is judged by R3's `settings-shell` arm. Defence in depth
  for a spelling R4 misses.
- **R6 — Fail closed, with a repair path.** A cheap bash pre-check sends a call to the verdict only
  when its `tool_input` names `sett` or `.cla` (quotes and backslashes removed, case folded), holds
  `$'`, holds a glob character, or has a `file_path` that is a symlink or the same inode as an
  existing guarded file. When the verdict crashes or python3 is missing, the call is denied, except
  an Edit or Write of the guard's own files (`settings-edit-guard-hook.sh`, `settings_guard.py`,
  `guard-lib.sh`), which is allowed with a note. A guard that cannot run must not block its own
  repair.
- **R7 — No override (O3), the template included (O4).** There is no environment variable that lets
  the agent through. The deny text names the developer's routes: edit the file by hand, or run a
  command with the `!` prefix (it runs outside the agent's tools, so no PreToolUse hook sees it). It
  also asks the agent to show the developer the exact change it wanted. The guard has no
  template-repository exemption.
- **R8 — Wiring, registration, docs.** The hook goes into the template `settings.json` (so
  `sync-core-hooks.py` wires it into projects that have the script), into `CORE_SCRIPTS` with its
  module and test, and into `run-mutation-gate.sh`'s default table. Docs: the hook header, the
  `bash-write-guard` delegate note, `.claude/docs/security.md` (who may change hook wiring), and
  `.claude/docs/workflows.md` (how a spec that adds a hook gets it wired: the developer applies
  the JSON).

## Out of scope

- A script file the agent writes and runs, an interpreter or tool that writes a settings file it
  does not name in the command text (`python3 scripts/sync-core-hooks.py`, `fix-hook-paths.py` run
  without its argument), and names assembled at runtime from parts that spell neither word. That is
  the same bound `bash-write-guard` and `trust-anchor-guard` declare. `sync-core-hooks.py` only adds
  template hooks, and the SessionStart autosync runs it as a hook, not as an agent tool.
- Editing a hook script itself into a no-op. In a project, `core-machinery-guard` covers CORE
  scripts. In the template, it is the named residual of every guard here.
- `permissions`, `defaultMode`, `apiKeyHelper`, `statusLine` and other command-running keys (O2).
- Managed (enterprise) settings, plugin hooks and agent or skill frontmatter hooks: none of them can
  remove a project hook.
- `git stash`, `git checkout <branch>` and other moves between authored states: they can revert the
  developer's uncommitted hand edit, but they never author a new state. Committed settings are the
  developer's.

## Clarifications

### Session 2026-10-02 (auto-picked, recommended option)

- Q: Does a re-ordered hooks array count as a change? → A: Yes. Array order is the order the hooks
  run in, and deep equality keeps it. Object key order does not count.
- Q: What does the guard do when `CLAUDE_PROJECT_DIR` and the payload `cwd` are both missing? →
  A: It uses the process working directory, as the other guards do. `<config>` is still guarded.
- Q: Does a Bash read through an interpreter (`python3 -c "json.load(open('.claude/settings.json'))"`)
  pass? → A: No. Only the read-only list in R4 passes; the deny names the Read tool and `jq`.
- Q: A word like `HEAD:.claude/settings.json` (git show)? → A: It does not resolve to a guarded
  path, and `git show` is on the read list either way.
- Q: Does a heredoc body count against the command that opens it? → A: Yes. `git commit -F - <<EOF`
  whose message names the file is a `git commit`; `python3 - <<PY` whose body names it is a
  `python3` and is denied.
- Q: Which `git` subcommands write the working file? → A: `checkout`, `restore`, `reset`, `stash`,
  `rm`, `mv`, `apply`, `clean`, `merge`, `pull`, `rebase`, `cherry-pick`, `revert`, `am`. None of them
  is on the read list, so naming a guarded file with one of them is denied.

## Threat model

Trust boundary: **the agent's tool calls → the files that decide which hooks run and what
environment they see.** The attacker is the gated agent (same OS user). Out of model: another OS
user, a malicious template, the developer.

### TB1 — Edit/Write/MultiEdit/NotebookEdit → a settings file (R1–R3)

- **Tampering.** Remove a hook entry, add `disableAllHooks`, add an `env` entry
  (`SPEC_ACCEPTANCE=off`, `ALLOW_CORE_MACHINERY_EDIT=1`, `CLAUDE_TEMPLATE_AUTOSYNC=0`).
  *Mitigation:* R3 simulates the write and compares the three keys.
- **Tampering by breakage.** Leave the JSON invalid so the harness drops the file. *Mitigation:*
  `settings-invalid`.
- **Spoofing the path.** A symlink, a hard link, a different case, an NFD spelling, a `..` path, a
  relative path. *Mitigation:* realpath, inode, case fold, NFC (R1).
- **Repudiation.** settings.local.json is gitignored, so a change leaves no diff. *Mitigation:* the
  write is refused before it happens.
- **Denial of service.** A crash that denies every call. *Mitigation:* the pre-check sends only
  settings-shaped calls to the verdict, and the guard's own files stay editable (R6).

### TB2 — Bash → a settings file (R4, R5)

- **Tampering.** `sed -i`, `>`, `tee`, `cp`, `mv`, `rm`, `ln -sf`, `touch`, `truncate`, `git checkout --`,
  `python3 -c`, `cd .claude && …`, globs (`.c*/s*.json`), `$'…'` escapes, a variable in the last
  component. *Mitigation:* R4 judges every simple command that names a guarded file, allows only
  reads, and R5 adds bash-write-guard's extractor as a second reader.
- **Residual.** A script file the agent writes and runs; a tool that writes a settings file it is not
  given (`sync-core-hooks.py`); a directory part assembled at runtime (`$D/settings.json` with `D`
  set in an earlier call). Same bound as bash-write-guard and trust-anchor-guard. Named in the hook
  header and in `.claude/docs/security.md`.

### TB4 — check time → apply time (/tla GAP-1)

- **Tampering by race.** The guard judges a Write against the bytes on disk when the call is
  checked. If the developer hand-edits the file before the Write lands, a Write the guard allowed
  (keys equal to the old bytes) puts the old keys back and undoes the developer's change.
  `SettingsGuard.tla` with `SettingsGuard_NOSTALE.cfg` finds it in 4 steps. *Mitigation:* Claude
  Code refuses a Write or Edit to a file that changed since it was read; with that check
  (`SettingsGuard_STALE.cfg`) the invariant holds over 6 distinct states. That check is the
  harness's, not this guard's, and is a stated assumption (developer: document it, 2026-10-02).

### TB3 — the agent → "the developer switched it off" (R7)

- **Elevation.** An override variable the agent can set. *Mitigation:* none exists (O3). The routes
  are the developer's own editor and `!` commands, which never pass through PreToolUse.

### /tla (2026-10-02)

`SettingsGuard.tla` models a Write judged at check time and applied later, with the developer able
to hand-edit in between. With the harness's stale-file refusal (`SettingsGuard_STALE.cfg`) the
invariant holds, 6 distinct states. Without it (`SettingsGuard_NOSTALE.cfg`) TLC finds the 4-step
race in TB4 (GAP-1, developer: document it). Five drift items (D1 to D5), where the code was stricter
than the text after the adversarial pass, were written back into R3 and R4 (developer: fix now).

### Adversarial review (2026-10-02)

`security-scanner` declined to write bypass payloads, so the adversarial pass was done in-session
against the parser: process substitution `> >(tee …)`, backticks, `LESSOPEN=`/`GIT_EXTERNAL_DIFF=`
prefixes, `git -c`, `rg --pre`, and `NaN`/`Infinity` (accepted by Python, rejected by JSON.parse).
All were reproduced and fixed. /security-review then reproduced two more, both fixed:

1. An assignment-only command naming the file, followed by `"$p"` in a write. Assignment-only is now a
   write, and so is any read whose output can reach a command (substitution, or a command line that
   also runs a shell, interpreter or `xargs`).
2. `<<\EOF` and `<<E\OF` delimiters, which hid a `python3` heredoc body. Delimiters now follow bash's
   rule, and an unparsed opener attaches the rest of the text.

Its low-confidence note (Python's `True == 1` hid an `env` change from `1` to `true`) was fixed too:
values compare as JSON text. Mutation gate: `run-mutation-gate.sh --module
scripts/settings-edit-guard-hook.sh`, 24 of 26 sites killed (92.3 %), the two survivors marked
`mutant-equivalent` with their reasons.

## Functional coverage

No UI: the browser and destructive E2E phases do not apply. Each function has its arm in
`scripts/test-settings-edit-guard.sh`:

| Function | Arm |
|---|---|
| `Guarded` (R1: three files, case, symlink, hard link, `..`, `CLAUDE_CONFIG_DIR`) | `[R1]` |
| `edit_verdict` + `apply_edit` (R2, R3: key change, invalid, unreadable, no bytes, failing edit) | `[R3]`, `[R2]` |
| `bash_verdict` + `split_commands` + `word_hit` + `reads` (R4) | `[R4]`, 58 deny and 21 allow spellings |
| bash-write-guard delegate (R5) | `[R5]` |
| pre-check, crash, repair path, exit 0 (R6) | `[R6]` |
| sabotage: key comparison, read list, redirect, cd bases | `[sabotage]` |

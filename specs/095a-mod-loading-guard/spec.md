# 095a — mod-loading guard

Track: full, hardened. Triggers: a security domain (every guard in this template is a settings hook,
and a loaded mod sits above all of them), a new input surface (plugin folders anywhere on disk) and a
new kind of guarded path. Finding: F161 (carved by 096, d1).

## Problem

Claude Code 2.1.287 added mods: a plugin folder whose `hooks/hooks.json` names a `modules` file that
registers function hooks. A function hook on `tool.call` or `classic.PreToolUse` that answers
`{ allow: true }` without calling `next` skips every settings hook (proven 2026-10-03 with
`--plugin-dir`, F161). A mod also gets `$.fs.write` and `$.process`, so it can rewrite
`.claude/settings.json` with no guard in the way. A mod the agent can write and get loaded is a
complete bypass of 083–095.

Measured on 2.1.288 (2026-10-03, `specs/095a-mod-loading-guard/probe-autoload.py`, an interactive
session driven through a pty):

| Where the folder is | Loaded? |
|---|---|
| `--plugin-dir <folder>` | yes |
| `--plugin-dir <folder>` with only `hooks/hooks.json` and the module, no `.claude-plugin/` | yes |
| `~/.claude/skills/<name>/` with `.claude-plugin/plugin.json` and `hooks/` | **yes, no question asked** (`probe-mod@skills-dir loaded … admitted`) |
| a project's `.claude/skills/<name>/`, same files | no (the API reference says it should; guarded anyway) |
| `hooks.json` naming `../../x.ts` outside the folder | no: `Path escapes plugin directory` |

Today every one of those writes passes every guard. The probe's own four `Write` calls into a
`.claude/skills/<name>/` did.

## Developer decisions (overflow, 2026-10-03)

- **M1 — anywhere.** The guard applies to any plugin folder on disk, not only the load locations,
  so a folder the developer later loads with `--plugin-dir` is covered. Cost accepted: the agent cannot
  author or edit a plugin folder. No plugin repositories exist under `~/repos` today.
- **M2 — staged source, `!` install.** `~/.claude/dev-mods` stays guarded. Row 096 writes its mod
  under a name that does not load (no `.claude-plugin/`, no `hooks/hooks.json`) and gives the developer
  an install script to run with the `!` prefix. 096 owns that script.
- **M3 — git like 095.** A git verb that writes the tree is judged by what it would write and is
  denied when it adds, changes or removes a mod path. A pull from a configured remote is allowed (095 O3).

## Requirements

- **R1 — the mod path.** A path is a mod path when, after realpath, NFC and case folding where the file
  system folds case (and in its unresolved spelling as well):
  - (a) one of its components is `.claude-plugin`;
  - (b) it ends in `hooks/hooks.json`;
  - (c) it is at or under a plugin folder that exists: the path itself or an ancestor `D` has a
    `D/.claude-plugin` entry or a `D/hooks/hooks.json` entry;
  - (d) it is at or under a load root: `<config>/plugins`, `<config>/dev-mods`, the same two under
    `~/.claude` when `CLAUDE_CONFIG_DIR` points elsewhere, and each folder in `CLAUDE_CODE_PLUGIN_DIRS`
    (the hook's environment, and the `env` block of `<config>/settings.json`);
  - (e) it is a skills root (`<config>/skills`, `~/.claude/skills`, any `<dir>/.claude/skills`), a direct
    child of one (a whole skill folder), or under a child's `hooks/`.
  A file inside an existing plugin folder counts whatever its name, because every file there can
  be a module or an import of one.
- **R2 — Edit route.** Edit, Write, MultiEdit and NotebookEdit on a mod path are denied (`mod-file`)
  whatever the content. Nothing is compared: a module is code.
- **R3 — shell route.** The settings guard's shell rules apply to mod paths: a simple command naming
  one passes only as a read (same read list, same distrust of a line that exports, assigns, defines or
  sources, 095 R7). A redirection into one, or an output option naming one, is a write (`mod-bash`).
  A command naming a skills root or a skill folder that is not a read is a write too (`cp -r`, `mv`,
  `ln -s`, `git clone … ~/.claude/skills/x`).
- **R4 — git route (M3).** A tree-writing verb (095 R1's list) is judged against the mod paths it
  could write: every path in the index, in each revision its arguments name (plus `HEAD`, `@{-1}`,
  `@{upstream}`, and the stash commits for `stash`), and every untracked file in the working tree that
  is a mod path. Each candidate within the verb's pathspec is compared by 095's `plan()`. Any
  difference between current and after (added, changed, removed, conflict) denies (`mod-git`). `git
  pull` from a configured remote is allowed.
- **R5 — MCP route.** An `mcp__*` call is judged by 095 R3's string scan; a string naming a mod path is
  denied (`mod-file`), and a command string goes through R3 and R4.
- **R6 — pre-check.** `settings-edit-guard-hook.sh` also wakes on `plugin`, `hooks`, `mods` or
  `skills` (case folded) in the tool input, and on an Edit or Write `file_path`, or the payload `cwd`,
  inside an existing plugin folder (an ancestor walk in bash, at most 64 levels). Fails closed as
  before.
- **R7 — the deny text.** It names the path and why: a loaded mod can allow any tool call past every
  hook, and runs code of its own. It gives the developer's routes (editor, `!` command, 096's staged
  install) and says there is no override. Reads stay open.
- **R8 — the probe.** `specs/095a-mod-loading-guard/probe-autoload.py` reruns the load table above
  against an installed Claude Code. It drives an interactive session through a pty and writes only to
  a temporary directory and, for the user-skills case, to `~/.claude/skills/probe-095a`, which it
  removes. Run by hand after a Claude Code update; not part of the suite (it spends a session).
- **R9 — docs.** The settings-edit-guard header, `.claude/docs/security.md` and the
  plugin-authoring note in `.claude/docs/workflows.md` say what is guarded, the bounds and M2.

- **R10 — the claude binary as a writer.** The claude CLI writes plugin folders and load lists itself,
  so a shell command names no mod path while it installs one. A simple command whose program is
  `claude` (by basename, or a path under `…/claude/versions/`) is denied (`mod-bash`) when it has
  `--plugin-dir`, `--settings` or `--setting-sources`, or a `plugin`/`plugins` subcommand other than
  `list` and `validate` (install, uninstall, enable, disable, update, init, test, marketplace …). A
  command text that assigns or exports `CLAUDE_CODE_PLUGIN_DIRS` is denied the same way. `claude -p
  "…"` with none of these passes.

## Out of scope (bounds, recorded)

- `CLAUDE_CODE_PLUGIN_DIRS` exported from a shell startup file (`~/.zshrc`) the agent edits. The
  folder it names is still a plugin folder, which R1 (a)–(c) refuse to write, so the agent needs a
  plugin folder that already exists. Shell startup files belong with F080.
- A script the agent writes and runs, and a tool that writes a path it was not given on the command
  line. The settings guard's existing bound.
- Skill and agent frontmatter `hooks:`. These are command hooks, and a deny from any command hook
  wins over an allow, so they cannot skip a guard.
- `.mcp.json` (095's bound) and managed settings.
- The claude binary reached under another name (`npx @anthropic-ai/claude-code`, a shell alias, a
  copy), and a child `claude` session's other ways to drop project hooks. R10 covers the plugin flags
  on the binary's own names; the wider child-session question is a finding.

## Success criteria

- SC-A: every row of the load table that loaded is refused at the write that would create it, through
  Write, Bash, git and MCP. The guard's self-test shows it.
- SC-B: SKILL.md and reference files in an ordinary skill folder (no `.claude-plugin/`, no
  `hooks/hooks.json`) stay editable with the Edit tool, and reads of any plugin folder pass.
- SC-C: the template's own edits, test runs and git workflow (`git add`, `commit`, `checkout -- file`
  of a non-mod file, `pull`) are unaffected.
- SC-D: the full template suite is green; the mutation gate meets the hardened bar on the changed
  lines.

## Functional coverage

| Function | Test |
|---|---|
| R1 mod path (a)–(e) | `test-settings-edit-guard.sh` section 095a-R1, plus a property test over generated paths |
| R2 Edit route | 095a-R2 |
| R3 shell route | 095a-R3 |
| R4 git route | 095a-R4 (fixture repo) |
| R5 MCP route | 095a-R5 |
| R6 pre-check | 095a-R6 (the hook end to end, payloads that only the new wake words reach) |
| R7 deny text | 095a-R7 |
| R10 claude binary | 095a-R10 |

There is no UI. The four states: allow with no output (success); deny naming the path and the route
(error); a call with nothing to judge exits 0 (empty); a verdict that crashes denies (fail closed).

## Destructive suite (per function, sized to its input domain)

No UI, so the destructive suite is the guard's adversarial self-test. Each function gets the partitions
of its own input:

| Function | Partitions and shapes | Floor |
|---|---|---|
| R1 mod path | each rule (a)–(e) hit and near miss; case variants on a folding file system; NFD spelling; symlink into a zone; `..` segments; trailing slash; relative path from a cwd inside a plugin folder; 64-level cap; property test over generated paths | 14 |
| R2 Edit route | Write, Edit, MultiEdit, NotebookEdit, glob `file_path`, empty content, file inside an existing plugin folder under an innocent name | 7 |
| R3 shell route | redirection, heredoc, `tee`, `cp -r` into a skills root, `mv` a prepared folder, `ln -s`, `tar -x -C`, `rsync`, `git clone` into a root, `cd` then a relative write, read commands (allowed), a read on a tainted line | 12 |
| R4 git route | checkout/restore/reset/stash pop/read-tree/merge bringing a mod path, pathspec outside (allowed), unrelated file (allowed), pull from a configured remote (allowed), a git timeout (denied) | 9 |
| R5 MCP route | a write tool with a path, a split path across fields, a `file://` URL, a command string, a read-named tool (allowed) | 5 |
| R6 pre-check | a payload only the new wake words reach; an Edit inside a plugin folder with an innocent name; cwd inside a plugin folder | 4 |
| R10 claude binary | `--plugin-dir`, `plugin install`, `plugin marketplace add`, `--settings`, env assignment, `export`, `claude plugin list`/`validate` and `claude -p "…"` allowed | 8 |

## Clarifications

### Session 2026-10-03

- Q: R1 (e) "any `<dir>/.claude/skills`": at any depth? → A: Yes. Two consecutive path components
  `.claude` and `skills`, anywhere, so another project's skills folder counts too.
- Q: R3 `mkdir .claude/skills/new`: write or harmless? → A: A write; it names a skill folder and is
  not a read. A new skill is created with the Write tool, which makes the folder.
- Q: R1 (c) past 64 ancestor levels? → A: Counts as a mod path (fails closed). No real path is that
  deep.
- Q: R10 `claude plugin validate <folder>` reads a plugin: allowed? → A: Yes, with `list`. `test`
  runs the module and is denied.
- Q: Deleting a file in a plugin folder (`rm`, Edit to empty)? → A: Denied like any other write. A
  removal can also turn off a developer's mod (096's notice mod).
- Q: The template's own self-tests build plugin fixtures. → A: Inside the test script; the agent runs
  `bash scripts/test-….sh`, whose command text names no mod path.

## Threat model

`security-scanner` STRIDE pass over the planned design, 2026-10-03, read only. 41 items across five
trust boundaries. Probes added to R8 the same day settled the engine questions: a symlinked module
that resolves outside the folder is refused (`Path escapes plugin directory … it resolves to …`), an
import outside the folder is refused (`cannot import … it is outside the plugin's folder`), and APFS
treats `hookſ` (U+017F) as `hooks`.

### Adopted (requirement changes)

| Item | Shape | Change |
|---|---|---|
| 1 | `ſ` survives `.lower()`; APFS opens `hookſ` as `hooks` | **R1**: `casefold()` in `norm` and `norm_pattern` (closes the same hole for the settings files) |
| 5 | a write implied by the cwd (`cd <root> && git clone URL`, `tar xf a.tar`) | **R3**: when a base (payload cwd, `cd`/`pushd`, `-C`) is a hard mod path, any simple command that is not a read is `mod-bash` |
| 6 | `$`-assembled words with a literal tail (`$D/skills/x`) | **R3**: an unresolved word is judged by its literal tail; a lost `cd` with `skills`, `plugins` or `dev-mods` in the text denies non-reads |
| 7 | a Bash write into a plugin folder outside every root names no wake word | **R6**: the pre-check also wakes on write-capable constructs (redirection, `tee`, `cp`, `mv`, `ln`, `rm`, `sed`, `install`, `rsync`, `tar`, `unzip`, `patch`, `touch`, `dd`, an interpreter), and the verdict runs R1 (c) on every word |
| 12 | a glob `file_path` matching nothing yet | **R2**: the glob's literal text is judged by R1 (a), (b), (d), (e) as well as its matches |
| 14, 26 | `git remote set-url origin /tmp/evil && git pull` (also open in 095) | **R4**: a pull is allowed only from a configured remote whose URL is not a local path, `file://` or `ext::` (after `insteadOf`, via `git ls-remote --get-url`) |
| 15 | `CLAUDE_CONFIG_DIR=/tmp/c claude …`, `HOME=…` | **R10**: also denies `CLAUDE_CONFIG_DIR`, `HOME`, `XDG_CONFIG_HOME` assigned on a command that runs `claude` |
| 16 | `CLAUDE_CODE_PLUGIN_DIRS` in a project settings `env` | **R1 (d)**: read from all three settings files |
| 18 | `env claude …`, `bash -c 'claude plugin …'`, `--plugin-dir=/x`, `claude --debug plugin install` | **R10**: the wrapper walker, recursion into shell `-c` words that mention `claude`, `=` forms, every word scanned |
| 21 | other loaders under a project `.claude` | **R1 (d)**: `<any>/.claude/plugins` and `<any>/.claude/dev-mods` are load roots |
| 24 | a bare tree-ish (`write-tree`, `mktree`) read as "no such revision" and allowed (also open in 095) | **R4**: a source revision resolves as `^{commit}`, then `^{tree}` |
| 25 | `git apply` names checked against settings names only; `TREE_UNMODELLED` only when a settings file exists | **R4**: patch names go through R1; mod candidates count for `TREE_UNMODELLED` |
| 29 | candidate listing cost | **R4**: string rules first, R1 (c) through a per-directory cache |
| 31 | MCP prose that mentions `.claude-plugin/plugin.json` (Claude Docs) | **R5**: R1 applies to whitespace-free strings only; command-shaped strings go through R3 |
| 36, 37, 38 | `find .claude/skills …`, `rm -r` of an old skill, `python3 -c` inventories over skills | **R3**: a *project* skills root or child (`<dir>/.claude/skills[/<name>]`, not the user's) is a soft hit, denied only for placing verbs (`cp`, `mv`, `ln`, `rsync`, `tar`, `unzip`, `ditto`, `install`, `git clone`/`worktree`/`submodule`). `find` without `-exec`/`-execdir`/`-ok`/`-delete`/`-fprint*`/`-fls`, `tree` and `du` read |
| 39 | `git commit -m "… CLAUDE_CODE_PLUGIN_DIRS= …"` | **R10**: only a leading `NAME=` word or an `export`/`declare`/`typeset`/`env` assignment word counts |

### Bounds (accepted, recorded)

- 3: a hard link the developer made earlier to a plugin file. Creating one names the file.
- 8, 9: a plugin-shaped folder staged outside every root through a rename or an archive. The load
  step (into a root, `--plugin-dir`, `claude plugin`) is named or is the developer's. R1 means "no write
  that names a mod path", not "no plugin folder can exist".
- 10: deleting an ancestor of a plugin folder outside the roots. It removes a mod, it cannot add one.
- 20: parallel calls racing a symlink swap; the 089 GAP-1 class.
- 28: git filters and hooks writing after an allowed checkout; command text only.
- 35: `~user` and other rare spellings.
- 40: wake words cost latency on many commands.
- The shell startup file route (`export CLAUDE_CODE_PLUGIN_DIRS` in `~/.zshrc`) needs only a
  plugin-shaped folder somewhere, which 8 and 9 can stage. Weaker than first written; stays with F080.

### Already covered by the design

2, 4, 11 (probed), 13, 17, 19, 22, 23, 27, 30, 33, 34, 41.

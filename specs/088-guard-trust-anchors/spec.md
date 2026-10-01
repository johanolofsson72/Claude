# 088 — guard trust anchors

Track: full, hardened (trigger 1: the change is the authorization layer of every gate; trigger 4:
well over 6 files and two new hook scripts).
Findings: F090 F091 F093 F094, verbatim in `specs/FINDINGS.md`. Proposal F098 approved the row.

## Problem

The H3 adversarial pass found four gates that decide on state Claude can write itself. Each one
reduces "a human approved this" or "this is the project root" to a file or a field the agent being
gated can produce.

- **F090 (reproduced at H3).** The five Edit-path guards (`spec-register`, `pipeline-state`,
  `spec-interview`, `core-machinery`, `core-owed-tick`) find the project root by walking up from the
  edited file to the first `.git`. A `.git` is a plain file write, and `.git` has no source extension,
  so no guard stops it. An empty `src/app/.git` makes `src/app` the root: no register and no language
  marker sit there, so `src/app/main.py` is allowed. `scripts/.git` turns a CORE script into a
  non-CORE one, and `specs/.git` hides a register tick from the CORE-owed guard.
- **F091.** The 082 nightly runs a suite, a mutation runner and ratchets only when a human trusted
  their bytes, but Claude can grant that trust three ways: `project-maintenance.sh --trust --yes`,
  `MAINTENANCE_TTY=<a file holding yes>`, or writing `.git/claude-trusted-commands` directly. No guard
  covers any of the three.
- **F093.** `acceptance_cases.py` exempts a spec begun before 080 when its `interview.md` was first
  committed before 2026-10-02 by `%ci`, the committer date. `GIT_COMMITTER_DATE` sets that date to
  anything.
- **F094.** `acceptance-cases.sh --confirm --quote <anything>` writes the Confirmed line. Nothing ties
  the quote to the developer, and the line is plain markdown that an Edit can write without the
  helper. "Never confirm on the developer's behalf" is prose only.

## Requirements

- **R1 — The root walk is anchored (F090, developer O1).** `guard-lib.sh` gains
  `guard_anchor_for <file>` and `guard_git_boundary <dir>`. The anchor is `CLAUDE_PROJECT_DIR`,
  resolved physically, when it is set, names an existing directory, and the canonical file is inside
  it. A `.git` in a directory strictly below the anchor is not a boundary. The walk goes on to the
  anchor and above it as before. The five guards replace `[ -e "$DIR/.git" ]` with
  `guard_git_boundary "$DIR"`. A file outside the anchor, and any run with no usable
  `CLAUDE_PROJECT_DIR` (a test, an older harness), walks exactly as before. Language markers and the
  outermost register are still collected on every level from the file up to the root. A nested repo
  or submodule below the anchor is gated by the project's register (O1).
- **R2 — The trust prompt needs a person (F091, developer O2).** In `project-maintenance.sh --trust`:
  `--yes` is refused (exit 2, nothing recorded) when `CLAUDECODE` is set, which Claude Code sets in
  every shell it runs. The message tells the developer to run it in a terminal of their own. The
  prompt's input (`MAINTENANCE_TTY`, default `/dev/tty`) is opened on a file descriptor and must be
  a terminal (`[ -t ]`). A regular file, a pipe, `/dev/null` or a missing path is refused as "no
  terminal" (exit 2, nothing recorded). A `--trust` without `CLAUDECODE` and with `--yes` behaves as
  before.
- **R3 — A guard keeps human-only state out of the agent's tools (F091, F094).** A new
  `scripts/trust-anchor-guard-hook.sh` on PreToolUse, matcher `Edit|Write|MultiEdit|NotebookEdit|Bash`,
  denies:
  - (a) a `file_path` whose basename is `claude-trusted-commands` or `claude-developer-words`,
    wherever it is;
  - (b) for `acceptance.md` inside a `specs/` tree: an Edit or MultiEdit whose `old_string` or
    `new_string` holds `**Confirmed:**`; a Write whose Confirmed lines differ from the file's current
    ones; and a payload that names the file with no content at all (a shell write that
    `bash-write-guard` delegates);
  - (c) a Bash command whose text, after removing `'`, `"` and `\`, names either store,
    `MAINTENANCE_TTY` or `Confirmed:**`, or names `project-maintenance` together with `--trust`;
  - (d) an AskUserQuestion whose `tool_input.answers` is a non-empty object (the agent answering
    its own question). The matcher therefore also includes `AskUserQuestion`.

  It is the sixth delegate of `bash-write-guard-hook.sh` (basename class), so a shell write to either
  store or to an acceptance.md is judged by (a) and (b). It fails closed: a payload it cannot parse
  is denied when its raw text holds a trigger word. The deny text never echoes the command (FR-015 of
  bash-write-guard).
- **R4 — Developer answers are recorded where the agent cannot write them (F094, developer O3).** A
  new `scripts/developer-answers-hook.sh` on PostToolUse, matcher `AskUserQuestion`, appends one line
  per answered question to `<git-common-dir>/claude-developer-words`:
  `<epoch> <sha256 of the whitespace-collapsed answer> <digest> …`, where the digests are the 12-hex
  tokens in that question's text that equal the digest of a `specs/*/acceptance.md` on disk when the
  developer answers (/tla GAP-1: a digest precomputed for text not yet on disk binds nothing). No plaintext is stored. The file keeps its last 500 lines. A
  payload it cannot read records nothing and says nothing (PostToolUse cannot block, and the cost
  of a missed line is a refused `--confirm`, which names the fix).
- **R5 — `--confirm` checks the quote against those answers (F094, O3).** `acceptance-cases.sh
  --confirm <dir> --quote <q>` writes the Confirmed line only when the store holds a line whose hash
  equals sha256(collapsed `<q>`) and whose digests include the cases' current digest. Otherwise it
  exits 3, writes nothing, and says how to get a binding answer: show the cases and the digest
  (`--digest`) in one AskUserQuestion, then quote the answer exactly. `HOW_TO_CONFIRM` in the gate and
  the rule text say the same. A project without the hook script (it has not synced 088 yet) cannot
  confirm until it syncs. No fallback.
- **R6 — Grandfathering is decided by ancestry (F093, developer O4).** `_grandfathered` keeps its
  first two conditions (no acceptance.md, a ticked task) and replaces the date with this:
  the commit that first added `interview.md` is a strict ancestor of the commit that first added
  `scripts/acceptance_cases.py` to this repository (`git log --diff-filter=A --format=%H`, last line;
  `git merge-base --is-ancestor`, and not the same commit). No arrival commit, no interview commit, or
  a git error means not grandfathered (fail closed). `GRANDFATHER_BEFORE` is removed.
- **R7 — Wiring and registration.** Both new hooks are in the template `settings.json` (so
  `sync-core-hooks.py` wires them into every project that has the scripts) and in `CORE_SCRIPTS` with
  their tests. `bash-write-detect-hook.sh` keeps its delegate list equal to the guard's if a parity
  test demands it.
- **R8 — Docs.** The `guard-lib.sh` header (anchor), the `project-maintenance.sh` header (trust is a
  terminal step; what stops the agent), `.claude/rules/spec-interview.md` (the digest goes in the
  question; one line, within the context budget) and `.claude/docs/spec-interview-rationale.md`
  (the binding and its residuals).

## Out of scope

- F092 (suite trust hashes the line, not the files it expands to) and F095 to F097. They stay
  recorded findings. F092 belongs with the nightly's own hardening, not with who may grant trust.
- An agent that writes a script file and runs it, so the command text names nothing (a named
  residual for R3, the same bound bash-write-guard declares). R2 still refuses inside the harness
  unless that script also clears `CLAUDECODE`.
- History rewriting to forge ancestry (R6). It needs a force-push of `main`, which
  `destructive-command-guard` already stops.
- A session started in a subdirectory: a `.git` planted in the start directory itself is at the
  anchor, not below it, and still ends the walk. Named residual.

## Clarifications

### Session 2026-10-01 (auto-picked, recommended option; payload shape measured, not assumed)

- Q: Where does the developer-words hook read the answers? → A: Measured on this session's own
  AskUserQuestion calls with a capture hook: PostToolUse carries `tool_response` as an object with
  `questions` and `answers`, and `answers` maps the question text to the chosen label (or the typed
  "Other" text). `tool_input.answers` holds the same map after the fact. At PreToolUse,
  `tool_input` has only `questions`. The hook reads `tool_response.answers`, then
  `tool_input.answers`.
- Q: Can the agent supply its own `answers`? → A: The tool schema exposes an `answers` input. R3
  therefore also matches `AskUserQuestion` and denies a call whose `tool_input.answers` is a
  non-empty object at PreToolUse, where an honest call never has one (measured).
- Q: Which digests count, from which text? → A: 12-hex tokens in the question text (the `answers`
  key), not in option labels or descriptions. The developer reads the question.
- Q: Does R2's CLAUDECODE check apply to `--trust` without `--yes`? → A: No extra check. Inside the
  harness there is no terminal, so the isatty requirement already refuses it.
- Q: Does the trust-anchor guard deny a Bash command that only reads a store (`cat`)? → A: Yes. The
  guard judges the command text, as the opaque pass does, and the deny names the Read tool as the
  way to look.

## Threat model

Trust boundary for all four parts: **the agent's tool calls → state that stands for a human
decision or for the project's shape**. The attacker is the gated agent itself (Claude, same OS user),
trying to make a gate allow work it should block. Out of model: another OS user, a malicious template.

### TB1 — the edited path → "which project is this" (R1, F090)

- **Spoofing.** A planted `.git` (empty file, `git init`, a worktree `.git` file) below the project
  makes a subdirectory the root. *Mitigation:* R1 ignores every `.git` strictly below the anchor.
  *Residual:* a session whose `CLAUDE_PROJECT_DIR` is itself a subdirectory: a `.git` at the anchor is
  not below it. A symlinked subdirectory that leads out of the anchor is judged where it lands
  (guard_canon), which is outside, so the old walk runs there. That is correct, since the write also
  lands outside.
- **Denial of service.** A legitimate submodule's files are now gated by the outer register (O1).
  Accepted by the developer.

### TB2 — the agent's shell → the nightly trust store (R2, R3, F091)

- **Elevation.** `--trust --yes`, `MAINTENANCE_TTY=<file>`, a pty wrapper (`script`) feeding `yes`, or
  a direct write to the store makes the 02:30 run execute a command the agent chose. *Mitigation:* R2
  refuses `--yes` under `CLAUDECODE` and any non-terminal prompt input; R3 denies the command text
  and Write/Edit of the store. *Residual:* a script file the agent writes and runs, which unsets
  `CLAUDECODE` and spells nothing; runtime-assembled names. Same bound as bash-write-guard.
- **Tampering.** Editing an existing trusted line to a new hash. Covered by the same store denial.

### TB3 — the agent → "the developer confirmed these cases" (R3, R4, R5, F094)

- **Spoofing.** `--confirm --quote <invented>`, an Edit that writes the Confirmed line, a `sed -i` that
  swaps the digest, a write to the developer-words store, or an AskUserQuestion with model-supplied
  `answers`. *Mitigation:* R5 checks the quote against a hash the PostToolUse hook wrote from the
  real answer, bound to the digest the question showed; R3 denies the Confirmed line through
  Edit/Write/shell, the store, and pre-filled answers. *Residual:* the indirect-script route (TB2);
  a developer who answers "Confirmed as written" to a question that misdescribes the cases (the
  question text is the agent's, which is why the digest and the file path go in it).
- **Information disclosure.** Answers stored on disk. *Mitigation:* hashes only.
- **Denial of service.** A full store; capped at 500 lines.

### TB4 — git metadata → "this spec predates 080" (R6, F093)

- **Tampering.** `GIT_COMMITTER_DATE`/`GIT_AUTHOR_DATE` forgery. *Mitigation:* ancestry, which no
  date variable changes. *Residual:* rewriting history so the interview's add precedes the arrival
  needs a force-push of a pushed `main` (destructive-command-guard) or a fresh unpushed repo, where
  nothing was grandfathered to begin with.

### /tla (2026-10-01)

`ConfirmBinding.tla`: with every 12-hex token in the question recorded, NoSelfConfirmation is
violated in 4 steps. The agent shows a digest it precomputed for case text that is not on disk yet,
gets a yes for the text that is, writes the other text and confirms. GAP-1, fixed (developer: fix
now). A token now counts only when it equals the digest of an acceptance.md on disk when the
developer answers. The `ondisk` model holds (219 distinct states), and `test-developer-answers.sh`
pins the attack.

### Adversarial review (2026-10-01)

`security-scanner` in assume-exploitable mode reported 11 findings, all traced and none run. Seven
were reproduced here with payload PoCs and fixed:

1. `project-maintenanc?.sh --trust` with `env -u CLAUDECODE`. Now any `--trust` option and any mention
   of `CLAUDECODE` are denied, whatever the script is called.
2. `$'\x63laude-…'`, `.git/c*-…` and brace spellings. `$'…'` is decoded before matching, and any glob
   or brace through `.git/` is denied.
3. A Confirmed line written by `printf '**Confirmed%s**' … >> acc*.md`. The delegate expands a
   globbed target, and the gate re-checks an uncommitted Confirmed line against the answer store. A
   committed line is trusted, because the store is per clone.
4. Regression: a linked worktree under `.claude/worktrees/` lost its own root and became exempt. A
   `.git` below the anchor is a root again when git's back-link from `.git/worktrees/<n>/gitdir`
   confirms it. Writing that link by hand is denied.
5. A case-insensitive file system: a differently cased path skipped the anchor. The comparison folds
   case on macOS and Windows.
8. A payload over 128 KB in the environment (Linux). It is now read from stdin.
9. `**Then** the **Confirmed** badge` was denied as a Confirmed line. The guard now compares exactly the
   lines the parser reads.

#7 (`git replace --graft`, a re-created spec path) is fixed. git runs with `GIT_NO_REPLACE_OBJECTS=1`
and an empty graft file, and the interview takes its newest add. Every Write/Edit into a `.git` path,
including planting a `.git` file, is now denied outright, which also closes F090's first step.

Recorded rather than fixed: #6 (an answer binds words and a digest, not their meaning: F104), #11
(settings files have no edit guard: F103), Unicode normalisation and the subdirectory start (F105).
#10 (shallow clones and squashed histories fail closed) is the developer's O4 choice and stays.

### /security-review (2026-10-01)

Two high-confidence findings, both fixed. (1) A hard-linked alias of an acceptance.md was not judged
as one, and a local commit then made the forged line trusted. The guard now matches the file by
inode (`-ef` in the precheck, `samefile` in the verdict) and denies `ln … acceptance.md`. (2)
`git init --separate-git-dir=…/worktrees/x` plus a back-link written outside `.git/` passed as a
linked worktree. The link target must now be `<this project's git common dir>/worktrees/<name>`, and
`--separate-git-dir` is denied. Recorded: an empty `--no-checkout` worktree (F106), and a committed
line being trusted per clone (F107).

### /simplify and a lockout (2026-10-01)

`/simplify` gave the 088 git calls one `_git()` wrapper, so the replace/graft protection now covers
all of them. It also gave the acceptance.md locations one list (`ACCEPTANCE_GLOBS`, imported by the
guard together with the parser's `CONFIRMED_PREFIX`), and replaced guard-lib's per-call `uname` and
`tr` subshells with `$OSTYPE` and `nocasematch`. Skipped as design changes rather than cleanups:
dropping the guard's Confirmed-line layers in favour of the gate alone, moving the stores behind the
sandbox's `denyWrite`, and removing `--yes` (against O2).

While applying it, a half-landed edit crashed the guard's verdict. The precheck matched `claude-` in
the harness's own `scratchpad_dir`, so every call reached the verdict and was denied, including the
guard's own repair. The developer fixed it from the `!` prompt. Two changes came out of it: the precheck
reads only from `"tool_input"` on, and a crash still denies but leaves an Edit/Write of the guard's
own files (`trust-anchor-guard-hook.sh`, `acceptance_cases.py`, `guard-lib.sh`) open, with a notice.
Both are pinned in `test-trust-anchor-guard.sh`.

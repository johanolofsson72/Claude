# Spec interview — 105-guard-bypasses

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO with human overflow. The row is `[hardened]` (the guards are the trust boundary, the answer
store, about twelve files), so the four decisions that change what a guard lets through went to the
developer (O1–O4), answered 2026-11-17. The base questions had defensible recommendations.

## Q1 — Scope boundary
**Q:** What is in, what is out?
**A (auto):** In: F173–F178, F184, F186–F190 as R1–R12. Out: a script the agent writes and runs (088
bound), names assembled at runtime from parts that spell nothing, shell writes to a guard script (R6),
a PATH directory reached through a `cd` the text cannot follow (R4).

## Q2 — Primary actor and trigger
**Q:** Who triggers the code this changes?
**A (auto):** The agent, through a PreToolUse call (Edit/Write/MultiEdit/NotebookEdit, Bash, `mcp__*`),
for R1, R2, R4, R6, R7, R8 (guard side). The developer, for the mod installer (R8), the maintenance
pass that runs `validate-hooks.sh` (R11), and the AskUserQuestion answers R9 binds.

## Q3 — Happy-path outcome
**Q:** What does success look like?
**A (auto):** Every reproduced bypass is denied with a reason that names the cause and the developer's
route; ordinary work (reading `.git/HEAD`, printing `git rev-parse --git-dir`, editing a guard script
that parses, a read next to `bash x.sh "$(pwd)"`) is allowed with no output.

## Q4 — Data model
**Q:** What new state exists?
**A (auto):** Two changes to persisted state: answer-store tokens become `<digest>@<spec-name>` (R9),
and the mod marker records the installed digest (R8). Nothing else.

## Q5 — Which verbs count as touching the git dir (R1)
**Q:** Which shell verbs are refused on a path with a `.git` component?
**A (auto):** The 098 set (chmod chown chgrp chflags chattr setfacl xattr mv rename) plus rm rmdir
unlink shred truncate touch mkdir ln install cp dd. Readers (cat, ls, head, git itself) stay allowed.

## Q6 — `.git` component spelling (R1)
**Q:** Does `.gitignore` or `.github/x` count?
**A (auto):** No. `.git` as a whole component only, followed by `/`, whitespace or the end, as 098's
regex already reads it.

## Q7 — Which git-dir spellings are refused (R2)
**Q:** Which command substitutions count as naming the git dir?
**A (auto):** `$(…)` or backticks running `git rev-parse` with `--git-dir`, `--git-common-dir`,
`--absolute-git-dir` or `--git-path`. A bare `git rev-parse --git-dir` prints and is allowed.

## Q8 — Protected notice bases (R3)
**Q:** Which git dirs may hold a stamp?
**A (auto):** A `.git` directory; the target of `CLAUDE_PROJECT_DIR/.git` when it is a file (098 TB1
guards it); any `gitdir:` target whose resolved path has a `.git` component. Otherwise no stamp.

## Q9 — PATH comparison (R4)
**Q:** How is "on PATH" decided?
**A (auto):** The target's parent directory equals a PATH entry as spelled or as resolved (realpath),
after `~`/`$HOME` expansion; empty and relative PATH entries are resolved against the payload cwd.
A PATH directory that does not exist yet still counts.

## Q10 — Parse check scope (R6)
**Q:** Which files get the parse check, and with what?
**A (auto):** `*.sh` (bash -n, the same `bash` the hooks run) and `*.py` (`compile`) whose parent
directory is named `scripts`. Only Edit, MultiEdit and Write carry bytes.

## Q11 — A file that is already broken (R6)
**Q:** May an edit to an unparseable file be refused?
**A (auto):** No. Refused only when the current bytes parse and the new ones do not; a new or broken
file can always be written, so the check never blocks its own repair.

## Q12 — Error state
**Q:** What does a deny say?
**A (auto):** The cause in one line, the spec and R, and the developer's route (usually: ask the
developer to run it with `!`). The command text is never echoed.

## Q13 — Empty state
**Q:** A call with nothing to judge?
**A (auto):** Exits 0 with no output, before python, as today. New triggers are cheap text tests.

## Q14 — Loading / cannot decide
**Q:** A guard that cannot decide?
**A (auto):** trust-anchor and settings-edit fail closed on a crash as before. R6's own check failing
(no bash, a timeout) is no verdict: allowed, since a broken parse check must not lock the repair path.
R5 unsure means `project`, never the exemption.

## Q15 — Version-suffixed runners (R7)
**Q:** How are `python3.12`, `perl5.30` read?
**A (auto):** The basename with a trailing run of digits and dots stripped is compared too, so
`python3.12` → `python`, `bash5` → `bash`.

## Q16 — Handed-on names (R7)
**Q:** Which expansions carry a previous command's name?
**A (auto):** `$_`, `${_}`, history `!$ !! !* !:`, and a command substitution when the line also writes
a file. A substitution on a line that writes nothing (`bash x.sh "$(pwd)"`) stays allowed.

## Q17 — Nested program strings (R8)
**Q:** Which program strings are judged as commands?
**A (auto):** Every word with whitespace handed to a runner (sh bash zsh dash ksh fish eval, past the
run wrappers), not only those naming git or claude. Depth cap 3 kept.

## Q18 — Spec name in the token (R9)
**Q:** Which spec name is bound?
**A (auto):** The basename of the spec directory, exactly what `--question` shows in its first line.

## Q19 — Wiring audit sources (R11)
**Q:** Which settings files count for coverage?
**A (auto):** `.claude/settings.json` only. Local and user files are per-machine; a clone gets the
committed file.

## Q20 — Which guards the audit expects (R11)
**Q:** When is an unwired guard a finding?
**A (auto):** When its script exists in the project's `scripts/`. A project that never received a guard
has nothing to wire.

## Q21 — Performance
**Q:** What may this cost?
**A (auto):** No new process on the common path of any guard (SC-2). R4 and R6 add a python run only for
a path in a PATH directory or a script under `scripts/`.

## O1 — A project with no .git (R1)
**Q:** If a registered or synced project loses its `.git`, what should the guards do?
**A:** Deny + judge (Recommended): the pipeline guards deny naming the cause; the CORE guards keep
judging with `CLAUDE_PROJECT_DIR` as the root and announce.

## O2 — Width of the PATH refusal (R4)
**Q:** Refuse any write to a PATH directory, or only the guard tools' names?
**A:** Any write to PATH (Recommended).

## O3 — Mod source pin (R8)
**Q:** How should the installer pin the mod's source?
**A:** `--accept <digest>` (Recommended): the installer prints the staged files' sha256 and installs only
a digest the developer passes; the marker records it; a rerun of the same digest needs no flag.

## O4 — Answers recorded before R9
**Q:** What happens to bare-digest answer lines?
**A:** Honour if unique (Recommended): a bare digest binds when exactly one acceptance.md on disk carries
it; with two, neither is bound.

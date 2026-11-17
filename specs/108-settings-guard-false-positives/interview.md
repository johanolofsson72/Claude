# Spec interview — 108-settings-guard-false-positives

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. Spec-only, not hardened (three files, no new trust boundary), so no overflow. Every
loosened verdict gets a deny control instead.

## Q1 — Scope boundary
**Q:** What is in, what is out?
**A (auto):** In: F193, F221, F229, F232 as reproduced in the Problem table. Out: the heredoc-then-run
deny (098 R7 working as meant), resolving `$(git rev-parse --show-toplevel)`, a Python mutation gate
(row 109).

## Q2 — Primary actor
**Q:** Who is hurt today?
**A (auto):** The agent running read-only commands in a project, and the developer who has to reword
or approve them. Each false positive costs a retry and teaches the agent to dodge the guard's words.

## Q3 — Which pipe mates become filters?
**Q:** Which commands join `STDOUT_FILTERS`?
**A (auto):** sort, uniq, rev, tac, paste, and a sed that `reads()` already accepts. Not awk (it has
`system()` and file output), not xargs (it runs whatever it is given), not tee (it writes).

## Q4 — sort's program option
**Q:** How is `sort --compress-program` handled?
**A (auto):** A sort with any `--compress-program` word is no filter. `sort -o f` stays a spill,
judged as today.

## Q5 — uniq's output operand
**Q:** How is `uniq in out` handled?
**A (auto):** Count operands after dropping options and the values of `-f -s -w`. Two or more operands
means it writes the second, so it is no filter.

## Q6 — What counts as dots?
**Q:** Which words name the cwd when `dots` is on?
**A (auto):** `\.[./]*` in full: `.`, `..`, `./`, `../..`. A word that starts with `/` is absolute and
never the cwd.

## Q7 — Where does the cause go?
**Q:** How does the hook learn which rule fired?
**A (auto):** A third tab field on `settings-bash`, the slot `KEYS` already reads. The hook prints
`Rule: <cause>` after `Derived target:`. A mod verdict converted from settings-bash shows it in its
existing `(…)` slot.

## Q8 — Anchor words for program fragments
**Q:** Which literal pieces anchor a glob fragment inside a program string?
**A (auto):** `sett`, `.c`, `claude`, `plugin`, `skill`, `hook`, `mods`, case-insensitive. They cover
the three settings files and every mod zone spelling the guard knows.

## Q9 — Does R4 weaken bash -c?
**Q:** Can `bash -c 'rm .c*'` or `bash -c 'cp x .*/settings.json'` slip through?
**A (auto):** No. The program is re-judged as a command line of its own (105 R8), where `.c*` and
`.*` are real words and globbed as today. R4 changes only the fragment scan of the outer word.

## Q10 — R5 separators
**Q:** Which separators keep a cd chain alive?
**A (auto):** Only `&&`. `;`, newline, `||`, `|`, `&` end it, and the next command is judged against
every base. A cd whose previous separator was `||` or `|` does not start one.

## Q11 — R5 and grouping
**Q:** What about `(cd x && a) && b` or `{ cd x; } && b`?
**A (auto):** A line with `(`, `)`, `{`, `}` or a backtick outside quotes keeps today's line-wide bases.
A subshell's cd does not outlive it, and following that is not worth the risk.

## Q12 — R5 targets
**Q:** Which cd targets start a chain?
**A (auto):** A literal word after `~` and `$HOME`-style expansion, with no `$`, backtick or glob, and
not `-`. A relative target is joined to the bases before it. No argument means home.

## Q13 — R5 and guarded targets
**Q:** Does R5 change `cd ~/.claude && printf x > settings.json`?
**A (auto):** No. by_name and dots are still set line-wide for a cd into a guarded directory, and the
chained base is that directory, so the bare name is joined to it and refused.

## Q14 — Shell keywords
**Q:** Which reserved words are passed over?
**A (auto):** `do then else elif if while until`. `!`, `{` and `time` are already handled by
`RUN_WRAPPERS` where it matters. `for`, `case` and `select` are not passed over: their words are
names, and a `for` over settings paths stays a non-read.

## Q15 — Which commands run a script file?
**Q:** When are a command's arguments a script's data?
**A (auto):** sh, bash, zsh, dash, ksh, python, python3 (version stripped) whose first operand is a
file, with only known options before it (`-x -e -u -v -n -o VALUE` for shells, `-u -B -E -I -O -W
VALUE -X VALUE` for python). Or a command word that is a path ending `.sh`, `.bash` or `.py`. `-c`,
`-m`, `-s`, any unknown option, or a heredoc/here-string on the line keeps today's reading.

## Q16 — Is a script argument matched at all?
**Q:** Does R7 skip the argument entirely?
**A (auto):** No. The whole word is still matched, so a single-path argument naming a settings file is
refused. Only the split into fragments is skipped for multi-word arguments.

## Q17 — find -exec end
**Q:** Where does a find -exec grep's word list end?
**A (auto):** At the first `;` or `+` word after it, or the end of the command. `{}` is an operand
there, never a pattern when it comes after the pattern.

## Q18 — Error state
**Q:** What if parsing fails part way?
**A (auto):** Unchanged: an unbalanced quote naming a settings word is refused, and a guard crash
denies. R3 gives the unbalanced quote its own cause.

## Q19 — Test placement
**Q:** Where do the cases go?
**A (auto):** `scripts/test-settings-edit-guard.sh`, one `[108]` block after the `[101]` cases, each
allow case paired with its deny control. One assertion that a deny reason holds `Rule:`.

## Q20 — Mutation measure
**Q:** How is the change measured, given `run-mutation-gate.sh` mutates bash only?
**A (auto):** By hand, as in spec 101: one targeted mutant per new branch, run against the suite, the
result written into the spec's As built section.

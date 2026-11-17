# 108 — settings guard false positives

Track: spec-only. No new entity, state machine or external surface, and the change stays in three
files (`settings_guard.py`, `settings-edit-guard-hook.sh`, `test-settings-edit-guard.sh`). Not
hardened by the row, but every rule below loosens a guard verdict, so each one ships with deny
controls next to its allow cases and a `security-scanner` pass on the diff. Findings: F193, F221,
F229, F232, verbatim in `specs/FINDINGS.md`.

## Problem

`settings_guard._bash_verdict` refuses read-only commands that name a settings path, or that only
look like they do. Each case below was reproduced on 2026-11-17 against the live guard with
`CLAUDE_PROJECT_DIR` set to this repository.

| Finding | Command (shortened) | Today | Why |
|---|---|---|---|
| F193 | `git log -- .claude \| sort \| uniq` | deny | `STDOUT_FILTERS` lacks sort, uniq, rev, tac, paste, so the pipe mate counts as a program the read feeds |
| F193 | `git log -- .claude/settings.json \| sed -n 1,5p` | deny | a pure sed is a read on its own (spec 095 R8) but not a filter in a pipe |
| F193 | `cd "$(git rev-parse --show-toplevel)" && … printf '{"cwd":"//"}' …` | deny, target `//` | a cd nobody can follow turns on `dots`, and the dots test accepts any run of `.` and `/`, so `//` reads as the cwd |
| F193 | the deny says `Derived target:` and nothing about which rule fired | — | the verdict carries no cause |
| F221 | `curl … \| python3 -c '… re.findall(r"\"(.*?)\"", …)'` | deny | a fragment of a program string is globbed, and `.*?` matches `.claude` |
| F221, F229 | `cd <scratch>/fx && printf '{}' > .claude/settings.json` | deny | every relative word is also tried against the payload cwd, even in an `&&` chain where the cd must have succeeded |
| F229 | `for f in scripts/*.sh; do grep -q 'no .claude dir' "$f"; done` | deny | `do` is taken as the command word, so the grep is not a read |
| F229 | `grep -rn 'no .claude dir' scripts \| sort` | deny | the multi-word pattern is split into fragments, `.claude` is one, and sort is no filter |
| F229 | `bash scripts/finding.sh --add 'the … .claude dir … was refused'` | deny | a script's multi-word argument is split into fragments as if it were a program |
| F232 | `find . -exec grep '[a-z]*' {} +` | deny, target `[a-z]*` | `pattern_indices` knows only `xargs grep`, so find's by-name reading treats the pattern as a file name |

## Requirements

- **R1 — Stdout filters (F193).** A pipe mate counts as a filter when it is one of today's
  `STDOUT_FILTERS` or `sort`, `uniq`, `rev`, `tac`, `paste`, or a `sed` that `reads()` accepts
  (pure script, no `-i`). `sort` with `--compress-program` is no filter (it runs a program). `uniq`
  with a second operand is no filter (it writes that file). `-o`/`--output` stay what they are today:
  a spill, refused when anything on the line runs text.
- **R2 — Dots means the cwd (F193).** With `dots` on, only a word that starts with `.` and holds only
  `.` and `/` (`.`, `..`, `./`, `../..`) names the directory. `/` and `//` are the root.
- **R3 — The deny names its rule (F193).** A `settings-bash` verdict carries a third field, the
  cause, and the hook prints it as `Rule: <cause>` under the derived target. Causes: a redirect
  target, a command that is not a read, a read inside `$( )` or after a prelude, a read whose output
  reaches a named command, an output option, a name handed on, an unbalanced quote.
- **R4 — Program fragments need an anchor (F221).** When a word holds a program (whitespace or
  quotes inside it), a fragment with glob characters is matched only if it also carries a literal
  piece of a guarded name: `sett`, `.c`, `claude`, `plugin`, `skill`, `hook`, `mods`. A fragment
  without glob characters is matched as today. A shell program (`bash -c`, `eval`) is still re-judged
  as a command line of its own, where its globs are real words.
- **R5 — A cd chained by `&&` leaves the cwd behind (F221, F229).** On a line with no grouping
  (`( ) { }` and backticks outside quotes), the commands after `cd D &&` (D literal: no `$`, no glob,
  not `-`) are judged against D resolved from the bases before it, not against the payload cwd. The
  chain ends at any separator other than `&&`; after that, a command is judged against every base on
  the line, as today. A cd reached through `||` or a pipe does not start a chain. The line-wide
  `by_name` / `dots` rules for a cd into a guarded directory or one nobody can follow are unchanged.
- **R6 — Shell keywords are not commands (F229).** `do`, `then`, `else`, `elif`, `if`, `while`,
  `until` at the head of a simple command are passed over by `command_word` and `reads`. This also
  makes `then cd .claude` count as a cd, which today it does not.
- **R7 — A script's own arguments are data (F229).** When a shell or python runs a script file
  (`bash scripts/x.sh …`, `python3 scripts/x.py …`, or `scripts/x.sh …` run directly), its
  multi-word arguments are not split into fragments. Each word is still matched whole, so
  `bash scripts/x.sh .claude/settings.json` is refused as today. `-c`, `-m`, `-s`, a heredoc or a
  here-string, or an option this reading does not know, keeps today's splitting.
- **R8 — find -exec grep (F232).** `pattern_indices` also finds the grep/rg after find's `-exec`,
  `-execdir`, `-ok`, `-okdir`, up to its `;` or `+`.
- **R9 — Tests.** Every row of the Problem table is an allow case labelled `[108]` in
  `test-settings-edit-guard.sh`, and each rule has at least one deny control next to it
  (`| sort --compress-program=sh`, `| uniq - out`, `| sed -i`, `cd x; printf > .claude/settings.json`,
  `cd x && a || printf > .claude/settings.json`, `(cd x && a) && printf > …`, `python3 -c` with an
  anchored glob, `bash -c` with a dot glob, `bash scripts/x.sh .claude/settings.json`,
  `then cd .claude && printf > settings.json`). The cause appears in the deny reason.

### As built

- **R5 grew while being tested.** A chain also ends at any command that can move the shell itself:
  `time cd -`, `command cd -`, `builtin`, `eval`, `source`/`.`, `exec`, `pushd`, `popd`, `!`,
  `coproc` (`MOVERS`). A function definition on the line keeps line-wide bases, because calling it
  can run a cd. A relative cd target is chained only when `CDPATH` does not appear on the line. The
  per-command separators already end a chain at `(` and `)`, so the grouping test matters only for
  function bodies and quoted substitutions.
- **A quoted `$( )` is re-judged (found while testing R5).** shlex keeps `"$(…)"` as one word, so
  its commands were never split, and HEAD allowed `echo "$(printf x > .claude/settings.json)"`
  outright. Each substitution body is now judged as a command line of its own, the way 105 R8 judges
  a `bash -c` program. A read inside one (`"$(cat <settings> | wc -l)"`) still passes. The fix was
  smaller than recording it, so it went into this spec.
- The heredoc test for R7 is `"<<" in cmd`. That covers heredocs and here-strings, and it no longer
  shares its text with the 105 here-string line that a sabotage arm patches.
- **The adversarial review changed four rules.** A `security-scanner` pass on the first cut found
  seven commands that HEAD denied and the first cut allowed. All seven reproduced, and each is now a
  `[108]` control:
  - **B1, B2:** a cd target starting `~` (`~-` is OLDPWD, `~+`, `~user`), or one holding a `..`
    component, starts no chain. bash's cd is logical, so `lnk/..` is not the directory realpath gives.
  - **B3:** R4's anchor test was too wide. `glob.glob('.*/s*.json')` has no anchor. A fragment is
    now skipped only when it reads as a regex (a lazy quantifier, `+`, `^`, a backslash class), has
    no `/`, and carries no anchor.
  - **B4:** R7 counts only a script that already exists inside the project and that no other command
    on the line names, so `printf … > /tmp/e.sh && bash /tmp/e.sh '<program>'` is split again.
  - **Minor:** `sort -o…` in any spelling, attached included, is no filter. uniq counts every word
    after `--` as an operand.
- Measured by hand (row 109 owns a Python mutation gate). Twelve new sabotage arms each replace one
  new branch, and the suite catches every one. The list below is the first eight; the review added
  four more: the `/` and regex tests of R4, the `~`/`..` test of R5, and the project test of R7. The eight new sabotage arms each replace one
  new branch, and the suite catches every one: compress-program, uniq's operand count, the fragment
  anchor, `||` in a chain, a chain started after `||`, the function-definition group, the quoted
  `$( )` re-judge, and `-c` with script data. The 101 `cd sub` arm now uses `;`, since an `&&` chain
  catches that case on its own.

## Recorded bounds

- R4 reads a glob fragment spelled with regex syntax and no `/` (`.*?`) as a regex. An interpreter
  that calls `glob.glob('.*?')` and deletes what it gets is not seen. HEAD saw it only by accident.
- R4 and R7 trust that an interpreter program or a script does not build the path from pieces. It
  could do that today with `'.cl' + 'aude'`, so the program-string scan was already best effort.
  A script the agent writes and then runs is outside this guard either way (it can hard-code the
  path).
- R5 handles `cd` only. `pushd`, `popd`, `cd -` and a cd inside a subshell or group keep today's
  line-wide bases.
- A `CDPATH` exported by the developer's shell profile is invisible to the guard. It already
  misdirected relative cd targets before this spec (the line-wide bases join them to the cwd too),
  so R5 does not widen it.

## Non-goals

`cat > f <<EOF … EOF; bash f` where the body names `.claude`: the heredoc is written to a file the
line then runs, which is the 098 R7 rule doing its job. Resolving `$(git rev-parse --show-toplevel)`
as a cd target. A mutation gate for the Python guard modules (row 109).

## Clarifications

### Session 2026-11-17 (auto-picked, recommended option)

- Q: Is `xargs wc -l` after a read a filter? → A: No. xargs runs what it is given. Reading that safely
  needs the same parse as `pattern_indices`, and no finding asks for it.
- Q: Does R5 apply to `pushd`? → A: No. pushd and popd move a stack, and `cd -` returns to the cwd,
  so all three keep line-wide bases.
- Q: Should a cause string name the command? → A: For a read that flows, yes: the first pipe mate
  that is not a filter, so `| sort --compress-program=sh` says which command it was. Other causes are
  fixed phrases. The full command is still not echoed.

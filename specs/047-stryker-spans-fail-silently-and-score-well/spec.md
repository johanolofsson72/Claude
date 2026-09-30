# 047 — stryker-spans-fail-silently-and-score-well

Track: spec-only [hardened]. No entity, no state machine. Hardened on the size trigger (seven files,
two of them new) and because it adds a PreToolUse deny on Bash: a guard that can refuse the
developer's own `dotnet` commands is a new surface, and a false deny there costs more than the defect.

Evidence: ighweld-2026, findings F184, F197, F185, F069. Diagnosis in `specs/INDEX.pending.md`.

## The defect

Stryker.NET's per-file targeting fails in ways that read as success, and so does running it next to
a build.

- **F184.** `'**/X.cs{845-1080}'` uses a hyphen where Stryker wants `..`. Stryker does not reject
  it. The pattern matches no file, the file is not mutated, and the run reports a clean result.
- **F197.** `{98..120}` is a CHARACTER span, not a line span. Stryker's own docs say "the indices of
  the first character and the last character", under a heading that says "a specific span of
  lines". ighweld spec 161's first run covered a couple of dozen characters and the output did not
  show it.
- **F185.** With a span on `WpqrService.cs` the file still generated its whole mutant set. A span
  is no per-spec gate.
- **F069.** A `dotnet build` or `dotnet test` running next to Stryker overwrites the mutated
  assembly, and the run scores about 0% without a warning.

Nothing in the template looks at any of this. `project-maintenance.sh` section 5 reads the score
and, since 043, the per-module report. It never reads the patterns that decided what got mutated,
and nothing stops a second `dotnet` process from sharing the output directory.

## Decision

One helper, `scripts/stryker_guard.py`, owns both questions. The shell code calls it and does not
duplicate the rules.

1. **Pattern check.** A Stryker.NET mutate pattern is split into an optional `!`, a glob and zero or
   more trailing `{...}` groups. Each pattern gets one verdict:
   - `badspan`: a brace group that is not `{N..M}` with N ≤ M. Stryker reads it as part of the glob,
     so it matches nothing.
   - `nomatch`: an include pattern whose glob matches no `.cs` file under the root. Matching is
     lenient on purpose (full relative path, or any trailing run of path segments), so a verdict of
     "matches nothing" is never a guess.
   - `span`: a well-formed span. It counts characters, not lines, and ighweld measured that it does
     not shrink the run.
   - An exclude (`!`) pattern that matches nothing is not reported. Excluding nothing costs nothing.
2. **Where patterns come from.** Every committed `stryker-config*.json` (the `mutate` list, under
   `stryker-config` or top level), and literal `-m`/`--mutate` arguments in the project-local
   `scripts/run-mutation-gate.sh`. A token containing `$` is assembled at runtime and is skipped,
   not guessed.
3. **Live check.** `live <root>` lists running processes whose working directory is inside the root
   and that are either Stryker (`dotnet-stryker`, `Stryker.CLI`, `dotnet stryker`) or a `dotnet`
   build verb (`build`, `test`, `run`, `publish`, `pack`, `msbuild`, `vstest`, `watch`). MSBuild
   node-reuse workers and `VBCSCompiler` stay alive after every build and are not matched.
4. **`project-maintenance.sh` section 5.**
   - Every pass, not only `--full`: a Stryker.NET config with a `mutate` key is checked. Each
     `badspan`, `nomatch` or `span` becomes one `[MUTATION]` finding that names the file, the pattern
     and what Stryker does with it. With python3 or the helper missing, the finding says the
     patterns are unchecked. Trap 4 of `mutation-timeouts.md` forbids reporting that state as clean.
   - `--full`: before the mutation run, a live Stryker or build in the project refuses the run with
     a finding that names the processes. It is not stamped, so the job stays due.
5. **`scripts/stryker-guard-hook.sh`** (PreToolUse, Bash):
   - A command that starts Stryker (`dotnet stryker`, `dotnet-stryker`, `run-mutation-gate.sh`) is
     denied while a Stryker or build is live in the project, and denied when one of its literal `-m`
     patterns is `badspan` or `nomatch`. A `span` is denied too, unless the command carries
     `STRYKER_SPANS_ARE_CHARACTERS=1`. That override says "I mean characters". It does not switch the
     guard off.
   - A command that runs a `dotnet` build verb is denied while Stryker is live in the project.
   - `STRYKER_GUARD=off` in the command or the environment disables the hook, and the deny text
     names it.
   - It fails open on everything it cannot read: no python3, no jq, unparseable input, no process
     table, a process whose working directory cannot be read. A guard that locked up `dotnet` would
     be switched off within a day, and its protection with it.
6. **Docs.** `.claude/docs/testing.md`, in the mutation section: spans count characters, a pattern
   that matches nothing still scores, and Stryker runs alone.

## Declared coverage bound

- Windows Git Bash: `ps` lists MSYS processes only, so a native `dotnet.exe` is invisible and the
  live check sees nothing there. The deny is prevention, not a proof. The docs rule is what holds on
  that platform.
- A build started in another terminal after the Stryker run has begun is not caught. The hook sees
  only commands Claude issues, and `--full` checks once, before the run.
- StrykerJS patterns (`file.ts:1-5`) are out of scope; the defects were measured on Stryker.NET.
- The live check scopes to the project root, not one `.csproj`. A Stryker run on project A also
  refuses `dotnet build B/` in the same repository.
- The hook reads the leading command word of each simple command, after env assignments, shell
  keywords and wrappers (`timeout`, `nice -n 10`, `env -u X`). A `dotnet test` inside `bash -c "..."`
  is not parsed, and that case fails open.
- Commands over 64 KB get a coarse regex reading. The run-alone half holds and the pattern half is
  skipped. Patterns over 512 characters are reported as unparseable, not compiled.

## Adversarial review (2026-09-30)

security-scanner found 5 high/medium false-deny and false-assurance paths and 5 low ones. All were
fixed in place, each with an arm (G35–G46, C73–C76):

- H1 A process counted as a build because the words appeared in its argv (`git commit -m "fix dotnet
  test"`). Now the check is executable plus verb.
- H2 `--no-build`/`--help` and `build-server` were builds. A long-lived `dotnet run`/`watch` blocked
  Stryker. Now they are exempt on the process side, and still denied on the command side (they build).
- M1 Regex blow-up on `**/**/…` and `{}{}…`. Now `**/` runs are collapsed, patterns are capped at 512,
  the span tail is scanned right to left without a regex, and the hook has `"timeout": 10`.
- M2 One unparseable pattern blinded the whole config scan. Now it is reported per pattern.
- M3 An unreadable process table read as "none running". Now `unknown` lines become a note in `--full`.
- M4 A runtime `-m "$P"` and case-variant keys (`Mutate`) were skipped silently. Now the first is a
  note, and keys are read case-insensitively.
- M5 BOM, comments and trailing commas were reported as "not JSON". Now it parses the way the .NET
  reader does.
- M6 `grep -m 1` and `python3 -m` in the runner were read as patterns. Now only Stryker lines count.
- L1 Heredoc bodies are stripped. L2 Glob matching ignores case. L3 Wrapper options are skipped.
  L5 One `lsof` call covers all candidates. L4 (the override matched anywhere in the command) was
  left as it is: it can only fail open, and it is visible in the transcript.

## Threat model

Trust boundary: the Bash command string and the process table → a PreToolUse verdict.

- **Spoofing** — n/a. No identity crosses the boundary.
- **Tampering** — a command can carry `STRYKER_GUARD=off`. That is a documented override, it is
  visible in the transcript, and it protects a measurement, not a secret. A process renamed to look
  like Stryker can only cause a deny, never an allow.
- **Repudiation** — n/a.
- **Information disclosure** — the deny text quotes process arguments of the developer's own
  processes, inside the project root only. Nothing leaves the machine.
- **Denial of service** — the real risk. A false match denies the developer's `dotnet test`. Guarded
  by: verb-form matching only (no node-reuse workers), the cwd-inside-root requirement, fail-open on
  every unreadable input, an override named in the text, and a bounded `lsof` per candidate PID.
  Input size: the command is read once and matched by regex; stress arms feed a 1 MB command.
- **Elevation of privilege** — n/a. The hook never executes the command or any part of it; patterns
  are parsed with `shlex`, never evaluated.
- **False assurance** (the threat this spec exists for) — a pattern check that cannot run says so;
  it never reports clean.

## Out of scope

- The project-local runners (045 settled them as project-local). Their literal patterns are read;
  they are not rewritten.
- Rows 053 (`.stryker-tmp` litter) and 041/043 (timeouts, reporters).
- A strict scorer.

## Functional requirements

- FR-01 `{845-1080}` on a mutate pattern in a committed config → a `[MUTATION]` finding that says it
  matches no file.
- FR-02 An include glob that matches no `.cs` file → a finding naming config and pattern.
- FR-03 A valid `{N..M}` span → a finding that says CHARACTER offsets and that the span does not
  shrink the run.
- FR-04 `**/*.cs`, a path suffix (`Services/Foo.cs`) and an exclude that matches nothing → no
  finding.
- FR-05 A literal `-m` pattern in `scripts/run-mutation-gate.sh` is checked; a `$` token is skipped.
- FR-06 python3 or the helper missing while a config has `mutate` → a finding saying unchecked,
  never silence.
- FR-07 `--full` with a live `dotnet test` in the project → the run does not start, the finding names
  the process, and the job is not stamped.
- FR-08 Hook: `dotnet test` while Stryker is live in the project → deny, well-formed (hook_verdict).
- FR-09 Hook: `dotnet stryker` while a `dotnet build` is live in the project → deny.
- FR-10 Hook: `dotnet stryker -m '**/X.cs{845-1080}'` → deny; a valid span → deny;
  the same with `STRYKER_SPANS_ARE_CHARACTERS=1` → allow.
- FR-11 Hook: no live process, or a live one outside the project → allow; an MSBuild `/nodemode`
  worker in the project → allow.
- FR-12 Hook: `STRYKER_GUARD=off` → allow; non-dotnet command → allow without starting python;
  malformed input → allow.
- FR-13 Existing maintenance arms keep their verdicts.
- FR-14 testing.md states the three facts.

## Clarifications

### Session 2026-09-30

- Q: Is a valid span a finding, or only an invalid one? → A: A finding. It is well-formed and still
  wrong for its only use in a committed config (per-spec scoping): it counts characters and, per
  F185, does not reduce the run.
- Q: Deny or warn in the hook? → A: Deny. F069 cost ighweld a full run, and a warning printed next to
  a command that has already started is read after the damage. It fails open everywhere else.
- Q: Should the live check see build-server daemons? → A: No. MSBuild node-reuse and VBCSCompiler
  outlive every build; matching them would deny Stryker for ten minutes after any build.
- Q: Pattern base directory? → A: Lenient matching over every `.cs` under the root (full relative
  path or any trailing segment run). The check only claims "matches nothing" when nothing could match.

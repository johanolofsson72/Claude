# 080 — developer-authored acceptance cases

Track: full, hardened (register tag; also the size trigger: a resolver change, a guard change, a
new helper script, a rule, two docs and tests). Approved from proposal F075 on 2026-10-01.

## Problem

On a full or hardened spec the same agent writes the interview answers, the plan, the code and the
tests. 075 is the measured case: 19 of 23 interview answers and all 95 tests were Claude's. The
sabotage set proved the tests bite. It did not prove that the tests check what the developer
wanted, because nothing the developer said became a test.

The interview's overflow answers are the developer's, but they are answers to design questions,
not statements of behaviour a test can check. spec-kit's own "Acceptance Scenarios" in `spec.md`
are written by Claude too.

## Requirements

- R1 **The artifact.** A full or hardened spec carries `<spec-dir>/acceptance.md`: 3 to 5 cases,
  each a `## AC-<n> — <title>` heading followed by non-empty `**Given**`, `**When**` and `**Then**`
  lines. `<n>` runs 1, 2, 3… without gaps or repeats.
- R2 **Developer confirmation.** The file carries one line
  `**Confirmed:** <YYYY-MM-DD> · <digest> — "<the developer's words>"`. The digest is the first 12
  hex characters of the SHA-256 of the cases' normalised text (headings and Given/When/Then lines,
  whitespace collapsed). Claude may draft the cases. Only the developer confirms them, through
  `AskUserQuestion`, and their answer is quoted on the line.
- R3 **Helper.** `scripts/acceptance-cases.sh` parses the file (`--check <spec-dir>`), prints the
  digest the line must carry (`--digest <spec-dir>`), writes the confirmation line
  (`--confirm <spec-dir> --quote "<words>"`), and lists which cases a test names
  (`--coverage <spec-dir> --root <project>`). One parser, in `scripts/acceptance_cases.py`, used by
  the helper and the guard.
- R4 **Gate, step 1: confirmed cases.** `spec-interview-guard-hook.sh`, once the interview count
  passes, denies every source edit on a full or hardened active spec until `acceptance.md` parses
  and its confirmation digest matches the current cases. A digest mismatch names it: the cases
  changed after the developer confirmed them.
- R5 **Gate, step 2: tests first.** With the cases confirmed, test files are editable. Production
  source stays blocked until every case is named by a test: some test file in the project contains
  `<spec-id>-AC-<n>`. A test file is recognised by path (a `test`, `tests`, `__tests__`, `spec`,
  `e2e` or `integration_test` directory, a `*.Tests`/`*.Test` project directory, or a
  `*.test.*`, `*.spec.*`, `*_test.*`, `test_*.py`, `*Tests.cs`, `*Test.cs`, `*_spec.rb` name).
- R6 **Which specs.** Track `full`, or a row tagged `[hardened]` on any track. Light, spec-only and
  checkpoint rows are exempt. `spec_active.py` reports `hardened` so the guard does not re-parse
  the row.
- R7 **Rollout.** A spec that was already being implemented when this lands is not blocked. That
  means a `tasks.md` with at least one ticked task, no `acceptance.md`, and an `interview.md` first
  committed before 2026-10-02. Every other full or hardened spec is blocked. The date was added after
  code review: without it, ticking one setup task exempted a brand-new spec.
- R8 **Off switch.** `SPEC_ACCEPTANCE=off` (settings `env`) turns the acceptance step off for a
  project. Any other value, or none, leaves it on. The deny text names the switch.
- R9 **Rules follow.** `spec-interview.md` gets a short section, the status summary in
  `spec-register.md` reports `<K> acceptance cases confirmed`, and the long form goes to
  `spec-interview-rationale.md` and `testing.md`.
- R10 New scripts are CORE (`template-autosync.sh`).

## Non-goals

Proving a test was red before the code existed. Checking that a test which names an AC actually
asserts it. Acceptance cases on light or spec-only specs. Moving spec-kit's own acceptance
scenarios. A cryptographic proof of who confirmed: the quote is a record, not a signature.

## Acceptance

See `acceptance.md`. Beyond those: `test-acceptance-cases.sh` green, `test-pipeline-hooks.sh`,
`test-active-spec-resolution.sh`, `test-spec-dir-absent.sh` and `test-bash-write-guard.sh` stay
green, every guard branch has a sabotage arm the suite kills, the threat model below is complete,
and security-scanner plus `/security-review` have run with every flag decided.

## Clarifications

### Session 2026-10-01 (auto-picked)

- Q: Does `SPEC_ACCEPTANCE=off` silence step 2 as well? → A: Yes. It turns the whole acceptance check off; the interview count still applies.
- Q: Where is the "all cases named" cache? → A: `.claude/state/acceptance/<spec-id>` holding the digest it was computed for. A different digest, or no file, means scan again.
- Q: Does MANUAL interview mode change anything here? → A: No. Confirmation is the developer's in both modes; the mode only governs the interview count.
- Q: How is `[hardened]` read? → A: Case-insensitive `[hardened]` anywhere in the row's track field, the same field the track is read from.
- Q: Does a Bash-routed write get the test-file allowance? → A: Yes. `bash-write-guard-hook.sh` replays the same payload shape to this guard, so one decision covers both routes.
- Q: What text does the digest cover? → A: Per case in order: `AC-<n> — <title>`, then the Given, When and Then text, each with whitespace collapsed to single spaces, joined by newlines. Prose outside the cases and the Confirmed line itself are excluded, so the confirmation can be written without changing the digest.

## Threat model

One trust boundary changes: the content of `acceptance.md` and the test tree → the guard's verdict.
Both are written by the same agent the gate constrains.

- Spoofing: Claude writes a Confirmed line the developer never gave. Mitigation: accepted and
  recorded. The rule requires the quote to be the developer's `AskUserQuestion` answer; the
  guard cannot tell who typed a line, and the developer can read `acceptance.md` in the commit.
- Tampering: cases rewritten after confirmation to match the code. Mitigation: the digest (O3);
  any change denies code until re-confirmed. Recomputing the digest is possible, but it is a
  deliberate act that appears in the diff next to the changed case.
- Tampering: a test that names a case without testing it, or a name in a comment. Mitigation:
  accepted (non-goal); only test-file paths count (Q16), and review and the mutation gate judge
  what the test asserts.
- Repudiation: git history of `acceptance.md`.
- Information disclosure: the deny text quotes spec ids and file paths only.
- Denial of service: a huge `acceptance.md` or test tree. Mitigation: the parser reads at most
  64 KB. Case numbers are bounded to 4 digits, because `int()` on 5000 digits raises. A FIFO or other
  non-regular file is refused rather than read. The scan is `git grep -E` on the escaped id with a 5 s
  timeout. A timeout fails open (O6); any other git error denies. Accepted: an agent can force the
  timeout (a huge untracked tree, or `ACCEPTANCE_SCAN_TIMEOUT` in settings). Both show in the
  working tree or the settings diff.
- Tampering with the cache: `.claude/state/` is gitignored, so a cache that stored only "covered"
  could be forged with no trace. Mitigation: the cache stores the digest and the test files that
  named the cases, and a hit re-reads those files. It can only point at test files that really
  contain the names.
- Fail-open by crash: the hook allows on any exit code it does not know. Mitigation: `gate()` runs
  inside `try`; any exception becomes a deny that names it.
- Elevation: a symlink `tests/link → ../src` makes `tests/link/app.ts` look like a test file.
  Mitigation: the edited path and the project root are resolved with `realpath` first.
- Elevation: a path that pretends to be a test (`src/tests_helper/app.ts`). Mitigation: accepted;
  test-path conventions are by directory or name, and a production file under a `tests/` directory
  is a test file by every stack's convention. The grandfather clause (a ticked task) is a bypass a
  diff shows.

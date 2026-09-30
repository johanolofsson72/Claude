# 050 — allium-cli-warns-on-every-spec-it-has

Track: spec-only. No entity, no state machine. Four files touched (hook, its test, the allium skill,
the allium rule) plus the install line in `sync-prompt.md`. No hardening trigger fires.

Evidence: ighweld-2026 F080 / F001 / F031 (location hint), F089 (status assignment). Diagnosis in
`specs/INDEX.pending.md`.

## What was measured (2026-09-30)

Every claim below was run against real binaries: the installed 3.2.3 and release tarballs of 3.2.4,
3.3.0, 3.4.0, 3.5.0 and 3.6.1 from `juxt/allium-tools`.

**The location-hint lint.** Upstream fixed it in **3.3.0**
(`docs/project/rust-checker-parity.md` §6). Before that, the Rust checker inspected the parsed
path, which drops the trailing comment, so it warned on every `deferred` whatever you wrote. That
matches ighweld's report exactly: they were on a pre-3.3 CLI, where no spelling satisfies it. From
3.3.0 on, a hint is anything after the name on the same line that contains a quoted path, an
`http(s)://` URL, or the `-- see:` comment convention from the language reference:

| Line | 3.2.3 / 3.2.4 | 3.3.0 → 3.6.1 |
|---|---|---|
| `deferred Order.fraud_check` | warns | warns (correct: no pointer) |
| `deferred Order.fraud_check -- see: fraud.allium` | warns | clean |
| `deferred Order.fraud_check -- see fraud.allium` | warns | warns (no colon) |
| `deferred Order.fraud_check in "fraud.allium"` | parses as a membership expression, name `?` | parse error |

So the defect on our side is twofold. Nothing tells a project that its CLI is too old for the lint
to mean anything, and the allium skill's reference example is a bare `deferred Order.fraud_check`,
which elicits copy. ighweld on 3.6.1 still carries 116 of these warnings in 52 files: 59 bare
lines, and the rest pointers written as `-- src/…`, `-- specs/…`, `-- tests/…`. Those are real
pointers, but the lint only reads `-- see:`.

**F089.** Still present in 3.6.1. It is not the binding form itself. `allium.status.unreachableValue`
fires when **two entities declare a field with the same name** (`status`) and the rule assigning it
binds the entity through an **untyped trigger parameter** (`when: SyncPush(item)`). The checker
cannot tell which entity `item` is, so it credits the assignment to neither. With one entity carrying
`status`, or with distinct field names, it is clean on both 3.2.3 and 3.6.1. The documented
`surface … context item: T` + `provides: SyncPush(item)` form does not help. An undocumented
`provides: SyncPush(item: T)` silences it on 3.6.1 only, and the skill already forbids typed trigger
parameters. Upstream closed a neighbouring issue (#18, overlapping status values) in June. This case
has no issue.

## Decision

1. **The hook reads the CLI version once per session.** Below 3.3.0 it tells the model, once, that
   the deferred location-hint lint cannot be satisfied on this CLI and how to upgrade. When the same
   write also blocks, the note rides inside the block reason, so the hook still prints exactly one
   JSON object.
2. **An unreadable version is not a verdict.** A CLI whose `--version` does not parse gets no note.
   Validation still runs and still decides on severities. The version note is advice, and a fake or
   future binary must not trip it.
3. **The skill teaches the hint.** The reference example gains `-- see: <path>`, the INVALID table
   gains the rejected spellings, and a line states the three accepted forms and the 3.3.0 floor.
4. **The skill names F089 as a known false positive** with its cause and the workaround that works
   on every version: give the colliding status fields distinct names (`push_status`,
   `response_status`). The undocumented typed-`provides` form is not taught.
5. **The rule drops its excuse.** `.claude/rules/allium.md` no longer says the lint "warns on nearly
   every spec". Warnings still do not block, and the reason is now that they are advice, not that
   one of them is noise.
6. **An upstream issue for F089 is drafted, not filed.** `upstream-issue-f089.md` in this directory.
   Filing on a third party's tracker is the developer's call.

## Functional requirements

- **FR-01** `allium-check-hook.sh` runs `$ALLIUM_BIN --version` and parses `major.minor.patch` from
  its first line. Below 3.3.0 → one `notice_once` per session (key `allium-cli-old`) naming the
  version, the floor, and the upgrade command. At or above → nothing.
- **FR-02** A version that does not parse → no note, and validation behaves exactly as before.
- **FR-03** An old CLI plus a file with errors → one block JSON whose reason carries both the errors
  and the version note. Never two JSON objects on stdout.
- **FR-04** Every existing arm of `test-allium-check-hook.sh` still passes (the hook's blocking
  contract does not change).
- **FR-05** `.claude/skills/allium/SKILL.md`: the reference example uses `-- see:`; the INVALID
  table lists the `in "…"`, bare-string-colon, and `-- see` without colon spellings; the Validation
  section states the 3.3.0 floor and the F089 false positive with its workaround.
- **FR-06** `.claude/rules/allium.md` Validation: no "warns on nearly every spec"; states the floor.
- **FR-07** `scripts/sync-prompt.md` install block states the 3.3.0 floor.

## Non-goals

- Rewriting existing `deferred` lines in product repos. Each project fixes its own lines when it
  next touches the spec; the warning now tells it how.
- Blocking on warnings, or on an old CLI. The hook's contract stays "errors block".
- Upgrading the developer's installed CLI. `brew` refuses the untrusted `juxt/allium` tap without
  `brew trust`, which is the developer's decision.
- A census of hint warnings. `allium-census.sh` counts errors, and that stays its job.

## Clarifications

### Session 2026-09-30

- Q: Floor at 3.3.0 or at the latest (3.6.1)? → A: 3.3.0. It is the release that made the lint
  satisfiable, which is the defect this row is about. A higher floor would nag about fixes nobody
  here depends on.
- Q: Should the note fire on every write when the CLI is old? → A: Once per session. The version
  does not change mid-session, and a repeated note is the noise this row removes.
- Q: Accept `-- src/path` pointers as hints by rewriting them in the skill's eyes? → A: No. The
  template does not reinterpret the CLI's lint. The skill says which spelling the CLI reads, and
  that spelling is `-- see:`.
- Q: File F089 upstream now? → A: Drafted only. It is outward-facing, and the developer decides.

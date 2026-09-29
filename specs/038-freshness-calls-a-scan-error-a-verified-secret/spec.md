# 038 — freshness calls a scan error a verified secret

Track: spec-only. No entity, no state machine, no new surface. Not hardened: one section of one
existing script and its self-test. The secret scan is a security check, but the change narrows a
verdict; it opens nothing.

Evidence: hetznerradar bootstrap, 2026-09-07 (T0). Diagnosis in `specs/INDEX.pending.md`.

## What was measured (2026-09-29, trufflehog 3.95.5)

| Run | Exit |
|---|---|
| `trufflehog git file://<repo with no commits> --only-verified --no-update --fail` | 1, `failed to read index file` |
| `trufflehog filesystem <missing path> … --fail` | 0 (error logged, nothing scanned) |
| same, plus `--fail-on-scan-errors` | 1 |
| clean tree, `--fail --fail-on-scan-errors` | 0 |
| `--help`: `--fail` | "Exit with code 183 if results are found." |

So 183 means results, 1 means trufflehog could not scan. The script's bare `if` turned the exit-1
case into `[FINDING] … Rotate them NOW`. And without `--fail-on-scan-errors`, a scan that errored
part-way exits 0 and reads as clean.

## Decision

- Capture the exit code and branch on it at both call sites (`git`, `filesystem`).
- 0 → clean, as today. 183 → `[FINDING]`, as today.
- Anything else → a third state: `[WARN] trufflehog could not scan (exit N)` with trufflehog's own
  error line(s), `SECRETS_STATUS="scan failed (exit N) — <reason>"`, `trufflehog` added to
  `NOT_SCANNED`. `FINDINGS` is not set. The RESULT line then says NOT SCANNED, which is what spec
  023 already does for a key scan that could not finish.
- Pass `--fail-on-scan-errors`, so an error mid-scan lands in the third state instead of in clean.
  An older trufflehog that does not know the flag exits non-zero on it, which is the third state
  with the reason on screen. Visible, not silent.
- A git repo with no commits gets a hint on the warn line: nothing in history to scan yet.

## Functional requirements

- **FR-01** Exit 0 → `Secrets: no verified credentials`, no `[FINDING]`.
- **FR-02** Exit 183 → `[FINDING] trufflehog found verified secret(s)`, `VERIFIED SECRET(S) FOUND`, exit 1.
- **FR-03** Any other exit → `[WARN] trufflehog could not scan (exit N)`, trufflehog's error text
  shown, `Secrets: scan failed (exit N)`, RESULT `NOT SCANNED: trufflehog`, no `[FINDING]`,
  no `rotate`, script exit 0 when nothing else found.
- **FR-04** FR-01..03 hold for both the `git` and the `filesystem` call site.
- **FR-05** Both call sites pass `--fail-on-scan-errors`.
- **FR-06** trufflehog's stderr still reaches the terminal on every path.

## Scenarios

- SC-038-01 git repo, stub exits 0 → clean wording, no finding.
- SC-038-02 git repo, stub exits 183 → finding, exit 1.
- SC-038-03 git repo, stub exits 1 with an error on stderr → warn + reason, NOT SCANNED, no rotate.
- SC-038-04 no-git dir, stub exits 1 → same as 03 via the filesystem call.
- SC-038-05 no-git dir, stub exits 183 → finding.
- SC-038-06 the stub sees `--fail-on-scan-errors` on both call sites.
- SC-038-07 real trufflehog (when installed) on a repo with no commits → warn, no finding.

## Out of scope

- `project-maintenance.sh` section 1 treats freshness exit 0 as clean, so a NOT SCANNED run
  (trufflehog missing, key scan incomplete, now scan failed) passes the maintenance pass silently.
  That predates this spec and has the same shape as 033. Recorded as a finding.
- Falling back to a filesystem scan when the repo has no commits.

## Clarifications

### Session 2026-09-29

- Q: Should a scan failure make the script exit non-zero? → A: No. Exit codes stay as they are:
  1 means findings. NOT SCANNED already exits 0 with the "that is not clean" line (spec 023), and
  a third exit code would change what `project-maintenance.sh` reads. The maintenance gap is a
  finding.
- Q: Add `--fail-on-scan-errors`? → A: Yes. Without it, the reverse conflation (error read as
  clean) stays, and the diagnosis names both directions.

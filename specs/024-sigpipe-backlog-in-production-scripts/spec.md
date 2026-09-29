# 024 — sigpipe backlog in production scripts

Track: spec-only. No entity, no state machine, no new surface. Not hardened: shell rewrites with no
behaviour change, no auth/PII/upload. It touches more than six files, but the size trigger is about
new surface, and every edit here swaps one pipe for an equivalent that has no pipe.

Evidence: msroute F008 (2026-09-25), `specs/INDEX.pending.md` § 024.

## Problem as filed

`validate-no-sigpipe-assertions.sh --all` lists pipelines outside the self-tests that feed an
early-exit consumer (`grep -q`, `head`). The row called them mostly harmless diagnostics and asked
for one-at-a-time fixes, because a bulk regex pass once turned msroute's suite red (M2).

## What was measured (2026-09-29)

1. **The backlog is 66, not 54.** There are 9 more in `scripts/test-register-bytes.sh`, which spec
   017 added. That self-test pipes into `grep -q`, so the **default** gate (`scripts/test-*.sh`) is
   red on `main` right now: exit 1, "FAIL: 9 pipeline(s)".
2. **"141 costs nothing" is wrong under a parent that ignores SIGPIPE.** .NET (and any runtime that
   sets `SIGPIPE` to `SIG_IGN` before it spawns a child) passes the ignore on. The writer then gets
   `EPIPE` in place of the signal, and bash prints `printf: write error: Broken pipe` to stderr.
   Reproduced here: `perl -e '$SIG{PIPE}="IGNORE"; exec "bash","r.sh"'` prints that line once per
   call of an `is_core`-shaped function, while the default disposition prints nothing. That is
   msroute F008: a stderr-silence assertion fails, and only under load, so it passes in isolation.
   A diagnostic pipeline leaks the line just as an assertion does, so the harmless ones are not
   actually harmless.
3. **Exposure is per line, not per file.** Each of the 75 sites has a rewrite with no pipe into an
   early-exit reader: a here-string, a consumer that reads all input (`sed -n 1p`, `awk 'NR<=n'`),
   or a command substitution captured first.

## Decision

Fix all 75 lines by hand, one line at a time, each with a rewrite whose output is byte-identical,
and run each touched script's own self-test after its file is done. After that, `--all --strict`
must exit 0 in the template, and a self-test arm keeps it there.

## Functional requirements

- **FR-01** Every production pipeline `--all` reports is rewritten so that no early-exit consumer
  reads a pipe. Allowed shapes: `grep … <<< "$VAR"`; `grep … FILE`; `sed -n 1p` / `sed -n 1,Np`
  in place of `head -1` / `head -N`; `awk -v n=… 'NR<=n'` where N is a variable that can be 0;
  `{ head -c N; cat >/dev/null; }` for a byte cap (drains the writer).
- **FR-02** The 9 self-test sites in `scripts/test-register-bytes.sh` are rewritten the same way, so
  the default gate is green again.
- **FR-03** No behaviour change. Every rewrite is exact for the inputs the line can receive; the
  output differs only in edge cases where the old line was wrong (`echo "$X"` with `X=-n`).
- **FR-04** `scripts/test-no-sigpipe-assertions.sh` gains an arm: in the template's own tree,
  `--all --strict` exits 0. Downstream (sync-owned CORE exempt) the arm is not run and says so.
- **FR-05** The two headers that quote the backlog ("54 production pipelines, nearly all legitimate
  diagnostics where a 141 costs nothing") and the gate's backlog message are corrected with the
  SIG_IGN mechanism, so the next reader does not rebuild the same backlog.
- **FR-06** The F008 mechanism is pinned by a deterministic arm: a fixture pipeline whose tail after
  the match exceeds the pipe buffer, run with SIGPIPE ignored, writes `write error` to stderr in its
  piped form and nothing in its here-string form. The real `is_core` is not the red case because
  its 3.3 KB list leaks only under load: 0 of 40 runs leaked at idle on the old line, measured
  2026-09-29. A test that goes red only sometimes is not a red case.

## Acceptance

- `bash scripts/validate-no-sigpipe-assertions.sh` exits 0.
- `bash scripts/validate-no-sigpipe-assertions.sh --all --strict` exits 0 in the template.
- Every self-test that drives a touched script passes, before and after (see `run-log.md`).
- The FR-06 arm is red on the piped form and green on the here-string form, in the same run.

## Clarifications

### Session 2026-09-29

- Q: Fix only the lines whose status is read, or all? → A: All. Measured #2: a diagnostic leaks to
  stderr under SIG_IGN the same way, and stderr silence is what F008's consumer asserted.
- Q: Make `--all` the default? → A: No. The header records that it was tried and reverted because
  it broke three meta-test arms. `--strict` is pinned by a new arm instead (FR-04).
- Q: Bulk rewrite with sed? → A: No, M2. Each line is edited by hand and its file's self-test is run.
- Q: Red case for F008 on the real `is_core`? → A: No; measured 0/40 at idle (race). Synthetic
  fixture past the pipe buffer instead (FR-06), plus the `--strict` arm (FR-04).
- Q: `head -n $N` where N may be 0? → A: `awk 'NR<=n'`; `sed -n 1,0p` prints line 1.

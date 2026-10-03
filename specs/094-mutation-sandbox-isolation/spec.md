# 094 — mutation sandbox isolation

Track: spec-only. No entity, no state machine, no new external surface. It narrows what a test can
reach while the mutation gate runs it. Not hardened: no trigger fires. The change removes reach and
adds none. Findings verbatim in `specs/FINDINGS.md`.

## Problem

| Finding | Where | What goes wrong today |
|---|---|---|
| F117 | `scripts/run-mutation-gate.sh` `run_test` | Each test runs in a throwaway copy, but with the developer's real `HOME`. `template-autosync.sh` `template_candidates()` lists `$HOME/repos/Claude`, and the git config under `$HOME` holds the developer's identity and credential helpers. A mutant that flips a sandbox guard in autosync (L1040, L3425 at H4) can fetch, fast-forward or push from the real template clone. The runner header says the copies "share nothing with the real repository" |
| F128 | `scripts/test-bash-write-guard.sh:586` | Reported 2026-10-02: section 14 of `test-hook-channels.sh` failed because the nojq decoder read `permissionDecision` without the `hookEventName` discriminator |

## Requirements

- **R1 (F117).** `run_test` runs every test with a home of its own: `HOME` is `<copy>.home`, one per
  worker copy, created with the copy and removed with the run. It holds one `.gitconfig` with a
  neutral identity (`mutation` / `mutation@invalid`) and `commit.gpgsign = false`, so tests that
  commit keep working without the developer's global config.
- **R2 (F117).** The test's environment also drops `CLAUDE_TEMPLATE_DIR`, `XDG_CONFIG_HOME` and
  `GIT_CONFIG_GLOBAL`, which can each point git or autosync back at the developer's files.
- **R3 (F117).** Git's network transports are refused inside a test: `protocol.https.allow`,
  `protocol.http.allow`, `protocol.ssh.allow` and `protocol.git.allow` are `never` in the sandbox
  `.gitconfig`. Not through `GIT_CONFIG_COUNT` or `GIT_SSH_COMMAND`: `self-test-env.sh`, the first
  line of all 94 self-tests, unsets both. A test that sets its own `HOME` loses the block, and it
  has also left the developer's home, which is the route F117 names. Local path and `file://`
  remotes, which every fixture uses, still work.
- **R4 (F117).** The runner header states what the copies share and what they do not.
- **R6 (found implementing R1).** `test-drive-sync.sh` AC-35 used `$HOME` as "an ancestor of
  this repository" and went red when the gate gave the test a home of its own. AC-35 now uses
  the repository's grandparent, which is an ancestor everywhere. A `$HOME` case (AC-35b) runs
  only where `HOME` really holds the repository. The arm that guards the refusal uses the
  grandparent too.
- **R5 (F128).** Verify only. The decoder at `test-bash-write-guard.sh:586` already checks
  `hookEventName == "PreToolUse"`, and `test-hook-channels.sh` section 14 is green on `39e27bf`.
  Record it; no code change.

## Non-goals

- Network isolation for anything but git (curl in a test, for instance). No test under the gate uses
  one against a real host, and a general network sandbox is not portable to Git Bash.
- Changing the ordinary suite run. It runs unmutated code, so its sandbox guards hold.
- `ssh` keys found through the passwd entry rather than `$HOME`: R3 refuses the ssh transport
  before a key is read.

## Success criteria

- SC-A: a test run by the gate sees a `HOME` under the run directory, not the caller's.
- SC-B: with `CLAUDE_TEMPLATE_DIR` set in the caller's environment, the test sees it unset.
- SC-C: inside a test, `git config protocol.https.allow` and `protocol.ssh.allow` answer `never`,
  and `git commit` succeeds.
- SC-D: the sabotage arm for R1 goes red when the `HOME` assignment is removed.
- SC-E: the mutation gate's baseline is green on the real target table with R1–R3 in place.

## Clarifications

### Session 2026-10-03

- Q: One shared sandbox home, or one per worker? → A: One per worker copy (`<copy>.home`). Workers
  run in parallel, and a test that writes under `~` would otherwise race another worker.
- Q: Protocol block in the sandbox `.gitconfig`, or through the environment? → A: The sandbox
  `.gitconfig`. The environment was the first choice, until reading `self-test-env.sh` showed every
  self-test unsets `GIT_CONFIG_COUNT` and `GIT_SSH_COMMAND` before its first command.
- Q: Should `GIT_CONFIG_NOSYSTEM` be set too? → A: No. The system config can change how a test
  behaves, and R3 already makes its credential helper unreachable.

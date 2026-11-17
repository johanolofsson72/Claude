# Plan — 107

| R | Files | Check |
|---|---|---|
| R1 | `scripts/project-maintenance.sh` (`failure_lines`, `SUITE_TAIL`) | `[107]` suite stub: FAIL on line 2 of 30 is quoted |
| R2 | `scripts/project-maintenance.sh` (`add`/`note` append to partial file, TERM/INT/HUP trap, cleanup after verdict) | `[107]` ratchet that kills its parent pass with TERM: partial report printed, rc 143, no stamp; clean pass leaves no partial file |
| R3 | `scripts/project-maintenance.sh` (mutation bound, refusal without timeout) | `[107]` stub `dotnet` that sleeps, bound 1 s → UNMEASURED; no timeout on PATH → NOT RUN |
| R4 | `scripts/project-maintenance.sh` (count, streak file, unattended refusal) | `[107]` N of M note; streak reaches cap → finding; reset on exit 0 |
| R5 | `scripts/project-maintenance.sh` (`--dir "$PWD"`), `scripts/register-similarity.sh`, `scripts/register_similarity.py` (`pair_wanted`, header) | `[107]` stub register-similarity records its argv; python unit test of `pair_wanted`; live case when Ollama is up |
| R6 | `scripts/test-worktree-root-detection.sh` | validate-portability clean on it |
| R7 | the two test files | run both suites, then the full template suite |

No new trust boundary. The streak file and partial file are written under the git dir, with names
filtered through `safe_label`.

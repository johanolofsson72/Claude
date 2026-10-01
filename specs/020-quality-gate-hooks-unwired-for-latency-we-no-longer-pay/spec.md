# 020 — quality-gate hooks, measured and run at night

Track: full, hardened (size trigger: a decision table, two scripts, a corpus, project-maintenance,
maintenance-due, a doc and a test). Held 2026-09-29 while Ollama was off; resumed 2026-10-01 after the
developer re-enabled it on this 64 GB machine (loopback only).

## Problem

Fifteen local-LLM hooks that check code (secret-scan, test-realism, test-assertion, test-gap,
test-name, async-audit, auth-check, linq-perf, n1-query, react-deps, migration-safety,
dockerfile-review, spec-criteria, spec-scope, plan-feasibility) have been unwired since 2026-05 for
latency, and since 2026-09-06 for memory. Latency no longer matters at 02:30, but nobody knows which
of them is right often enough to read. On 2026-10-01, one sample run showed test-assertion flagging
a test that has an `Assert.True`, and test-name renaming a name that was already descriptive.
`local-llm-stats.sh` measures ok% and seconds, not whether a flag is true.

## Requirements

- R1 **Corpus.** `scripts/fixtures/quality-gates/<hook>/` holds at least 2 files with a seeded defect
  and 2 clean files per hook, named so the hook's own trigger fires. `expect.tsv` lists
  `file<TAB>bad|clean<TAB>marker`. For a bad file, `marker` is a word that a true flag line names
  (the test, the field, the method).
- R2 **Bench.** `scripts/quality-gate-bench.sh` runs each hook on its corpus through the real
  local-llm path and scores it. A bad file counts as caught when a flag line contains its marker. A clean file counts as a false flag when any flag line appears (flag line: see Clarifications). It writes
  `scripts/quality-gates.tsv`: `hook<TAB>verdict<TAB>caught/bad<TAB>false/clean<TAB>median_s<TAB>date`.
- R3 **Verdict rule.** `nightly` when every bad file is caught, at most one clean file gets a false
  flag, and the median is ≤ 60 s. Otherwise `off`. An unmeasured hook is `off`.
- R4 **Nightly pass.** `scripts/quality-gate-pass.sh` takes files changed in commits since its last
  run (recorded as a commit sha in `.claude/state/quality-gates/last`, first run: the last 24 h,
  capped at 50 files). It feeds each file to every `nightly` hook as a PostToolUse Write payload and
  writes `.claude/state/quality-gates/latest.md`: a date, then each flag grouped by file.
- R5 **Morning.** `maintenance-due.sh` prints one line when `latest.md` holds flags:
  `quality gates: N flags from <date> — <path>`. No flags, no line.
- R6 **Wiring.** `project-maintenance.sh --full` runs the pass when a model is reachable. The bench
  runs on `--bench-quality-gates`, which is opt-in because it takes minutes. With no model, both
  print one line and change nothing: no table rewrite, no `last` move.
- R7 **Docs.** `.claude/docs/local-llm.md` gets the measured table and how to re-bench.
- R8 The scripts and `quality-gates.tsv` are CORE. The corpus stays in the template (autosync ships files,
  not directories); projects inherit the measured verdicts, and benching is a template-side job.

## Non-goals

Wiring any hook into `settings.json` (in-session). Bash-triggered hooks (stacktrace, bash-tldr,
pr-splitter…), which have no file to replay. Improving a hook's prompt. Turning flags into
FINDINGS rows.

## Clarifications

### Session 2026-10-01 (auto-picked)

- Q: Does the pass stamp a maintenance-due job? → A: No new job. It rides `--full` (as mutation and similarity do); its own `last` sha is its state.
- Q: Which model? → A: Whatever local-llm-detect.sh picks (qwen3-coder:30b here); the table records the date, and a re-bench after a model change is the developer's call.
- Q: What is a "flag line"? → A: After an optional `- ` bullet, an UPPER_CASE tag and a colon (NO_ASSERT:, UNREALISTIC:, N+1:, LEAK:…), or spec-criteria's `"phrase" → fix`. `VERDICT:` (spec-scope's summary) is not a flag. Corrected during implementation: the first reading assumed every prompt used a bare `TAG:`; three do not.
- Q: Does one call per fixture measure a hook? → A: No: the hooks run at temperature 0.2 and the first bench saw async-audit miss a fixture it caught on the next call. Each fixture runs 3 times (`QUALITY_GATES_RUNS`) and counts by majority.
- Q: A seeded defect the hook's own trigger rejects? → A: A corpus defect, refused with exit 2, never scored as a miss. "Fired" means the hook reached local-llm-call.sh (its trace line). Found by code review: three fixtures never reached the model.
- Q: Does `--full --if-due` run the pass on a night with nothing due? → A: Yes. The pass has no due threshold; the early "nothing due" exit runs it first (code review #4).
- Q: How does the bench reach the model when a session has LOCAL_LLM_DISABLE=1? → A: It does not override it. A disabled machine is "no model" (AC-4), named as disabled rather than unreachable.

## Threat model

New trust boundary: repository file content → the local model → `latest.md` → the developer.

- Information disclosure: file contents go to the model. Mitigation: the model is Ollama on
  `127.0.0.1` (LaunchAgent plist pinned to loopback 2026-09-06); the pass refuses a non-loopback
  `OLLAMA_HOST` unless `QUALITY_GATES_REMOTE_OK=1`.
- Tampering / injection: a file can carry instructions aimed at the model, and the model's output is
  untrusted. Mitigation (O3): output is written only to `latest.md`; the banner carries a count and a
  path, never text. Nothing parses model output beyond counting flag lines.
- Denial of service (O4): 50 files, 30,000 bytes each, 120 s per call; skips are listed.
- Repudiation: n/a (local report). Spoofing / elevation: n/a (no identity, no privileges).
- Secrets in the report: secret-scan's flag lines quote what they found, and other hooks can echo a
  credential (dockerfile-review: `RISK: ENV ..._SECRET=...`). Mitigation: `latest.md` lives in
  gitignored `.claude/state/`; a LEAK/SECRET line keeps only `line N | reason`; any other line has
  credential-shaped values (`password=`, `token:`, `Bearer `, quoted or not) cut to 4 characters.
- Elevation via the changed set (adversarial review): a committed symlink `x.test.ts -> ~/.ssh/id_rsa`
  would be read and sent to the model. Mitigation: symlinks are skipped and every file must resolve
  inside the project. State files are written with `O_NOFOLLOW`; a state directory that resolves
  outside the project is refused.
- Hiding a change: a commit of 50 junk files pushes the real change past the cap. Mitigation: the
  skipped count is in the report header and in the banner (`N flags, M files skipped`).
- Model output in latest.md: flag lines only, control characters stripped, 300 characters each.
  Claude reads the file only when the developer opens it; the banner carries numbers and a path.
- Lock takeover: the lock holds a pid; a live holder is never displaced, and a 2 h deadline lists
  what it could not reach as skipped.

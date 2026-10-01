# Spec interview — 088-guard-trust-anchors

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO (base auto-answered with recommended; genuinely-ambiguous escalated; overflow human-answered if flagged).
Flag: hardened (authorization layer of every gate, two new hooks, ≥ 6 files), so the four policy questions went to the developer as overflow (O1–O4), all of them threat-surface (who may become the root, who may grant trust, who may confirm, what counts as "before 080").

## Q1 — Scope boundary
**Q:** Which findings does 088 close?
**A (auto):** F090, F091, F093 and F094, the four the row names. F092 (suite identity hashes the line, not the files) is a nightly-integrity question, not a who-may-grant question, and stays recorded with F095–F097.

## Q2 — Scope boundary: which walks
**Q:** Does R1 touch every `.git` walk in the repository, or only the guards?
**A (auto):** Only the five PreToolUse guards F090 names. The SessionStart/Stop walkers (084 R1) start from `CLAUDE_PROJECT_DIR` itself, so a `.git` planted below it is never on their path.

## Q3 — Primary actor
**Q:** Who is the adversary?
**A (auto):** The agent being gated: Claude in a session, writing files and running shell commands as the developer's own user. Not an outside attacker. The goal is that every self-grant needs a conspicuous act that a guard refuses, not that it becomes impossible. A same-user process can always write a same-user file.

## Q4 — Happy path
**Q:** What changes for an ordinary session?
**A (auto):** Nothing visible. Guards resolve the same root (the anchor holds the real `.git`). `--trust` is run by the developer in their own terminal as the 082 header already says. Acceptance cases are confirmed through one AskUserQuestion that shows the digest, then `--confirm` with the answer quoted.

## Q5 — Data model
**Q:** What new persisted state is there?
**A (auto):** One file, `<git-common-dir>/claude-developer-words`: lines of `<epoch> <sha256-hex> <digest12>…`, capped at 500 lines. Untracked by construction (it is inside the git dir), per clone, no plaintext.

## Q6 — Validation: what is the anchor?
**Q:** When is `CLAUDE_PROJECT_DIR` used as the anchor?
**A (auto):** When it is set, names an existing directory (resolved with `cd -P`), and the canonical edited file lies strictly inside it by path segment. Otherwise the old walk runs unchanged.

## Q7 — Validation: what is a "digest" in a question?
**Q:** How does the hook find the digest the question showed?
**A (auto):** Every token of exactly 12 lowercase hex characters bounded by non-hex characters in the question text. The acceptance digest is 12 hex (080). Corrected by /tla GAP-1: a token is recorded only if it equals the digest of an acceptance.md on disk when the developer answers. Extra tokens were not harmless; a precomputed digest for unwritten text let the agent swap the cases after the yes.

## Q8 — Validation: quote normalisation
**Q:** How is a quote compared with an answer?
**A (auto):** Both are whitespace-collapsed with the same `_collapse` 080 uses for the Confirmed line, then hashed with SHA-256 over UTF-8. Case is kept: the quote is the developer's words verbatim.

## Q9 — Four states: success
**Q:** What does success look like for each part?
**A (auto):** R1: the guard's verdict is the one the real root gives. R2: `--trust` at a real terminal with `yes` records the store. R5: `--confirm` prints the Confirmed line it wrote. R6: a pre-080 spec stays exempt.

## Q10 — Four states: error
**Q:** What does each refusal say?
**A (auto):** Each names the rule and the human route. R2: "run --trust in a terminal of your own; Claude Code sets CLAUDECODE". R3: which store or line, and why the agent may not write it. R5: "no AskUserQuestion answer matches this quote for digest <d>; show the cases and the digest in one AskUserQuestion and quote the answer exactly". Exit codes: R2 2, R5 3.

## Q11 — Four states: empty
**Q:** What happens with no store, no anchor, or no arrival commit?
**A (auto):** No developer-words file: `--confirm` refuses (exit 3) with the same how-to. No anchor: old walk. No arrival commit of `acceptance_cases.py`: not grandfathered (fail closed).

## Q12 — Four states: loading
**Q:** Is there a slow path?
**A (auto):** R6 adds two `git` calls, bounded by the existing `_scan_timeout`, on the gate path only when a spec has no acceptance.md and a ticked task. R1 adds one `cd -P` subshell per guard call that reaches the walk. The developer-words hook is one python process per AskUserQuestion.

## Q13 — Error semantics: fail open or closed
**Q:** Which way does each new piece fail?
**A (auto):** The trust-anchor guard fails closed on an unparseable payload that mentions a trigger word, like `sensitive-file-guard`. The developer-words hook fails silent (PostToolUse cannot block; the cost lands on `--confirm`, which says so). R6 fails closed. R1 falls back to the old walk when the anchor is unusable, because that is what the harness gives a test.

## Q14 — Authorization: the developer's own route
**Q:** How does the developer still do each thing?
**A (auto):** Trust: `bash scripts/project-maintenance.sh --trust` in their own terminal (not the `!` prefix, which runs inside Claude Code's shell). Confirm: answer the AskUserQuestion. Overrides of the guards are not added: the stores are human-only by definition.

## Q15 — Concurrency
**Q:** Can two sessions corrupt the developer-words file?
**A (auto):** Appends are single `write` calls of one short line (well under PIPE_BUF), so concurrent appends interleave by line. The trim to 500 lines rewrites through a temp file and `os.replace`. A line lost in a race costs a refused `--confirm` and a re-ask.

## Q16 — Integration: bash-write-guard
**Q:** How do shell writes reach the new guard?
**A (auto):** As the sixth delegate, basename class, after core-owed-tick. Not added to the post-layer `bash-write-detect-hook.sh`: `acceptance-cases.sh --confirm` legitimately rewrites acceptance.md from a Bash call, and the post-layer cannot tell it apart.

## Q17 — Integration: projects
**Q:** How do projects receive it?
**A (auto):** CORE_SCRIPTS plus the template `settings.json`. `sync-core-hooks.py` wires a hook into a project once its scripts exist there.

## Q18 — Edge: a real submodule
**Q:** What happens to an edit inside a submodule under the project?
**A (auto):** Per O1, it is gated by the project's register. Recorded in the guard-lib header.

## Q19 — Edge: the template repo itself
**Q:** Does the new guard exempt the template repository, like core-machinery does?
**A (auto):** No. The template runs the nightly and confirms acceptance cases too; its stores need the same protection. Developing the guard here means reading the stores with the Read tool, not `cat`.

## Q20 — Non-functional
**Q:** What does R3 cost on the hot path?
**A (auto):** A bash `case` precheck on the raw payload. A payload that names no trigger word exits without a process. Only `acceptance.md` writes and Bash commands with a trigger word reach python.

## Q21 — Reversibility
**Q:** How is 088 rolled back?
**A (auto):** Revert the commit. The developer-words file is inert without the hook and can be deleted. Specs confirmed under 088 keep valid Confirmed lines; the format does not change.

## Q22 — Non-goals
**Q:** What does 088 not promise?
**A (auto):** It does not stop an agent that writes a helper script and runs it, or one that assembles names at runtime. Those are named residuals, as in bash-write-guard's coverage bound.

## O1 — Nested .git under the project (escalated, developer)
**Q:** A source file under the project dir but inside a nested repo or submodule: which register gates it?
**A:** Project register. Every .git strictly below CLAUDE_PROJECT_DIR is ignored by the five guards; a real submodule's files are gated by the outer register too.

## O2 — Who may grant nightly trust (escalated, developer)
**Q:** How hard is "trusting a nightly command" locked to a human?
**A:** Script + guard. project-maintenance.sh refuses --trust --yes inside a Claude Code shell and needs MAINTENANCE_TTY to be a real terminal; a new PreToolUse guard denies Bash that runs --trust, sets MAINTENANCE_TTY or names the store, and Write/Edit of the store.

## O3 — What binds a confirm quote to the developer (escalated, developer)
**Q:** What ties an acceptance-case --confirm quote to the developer?
**A:** AUQ answer + digest. A PostToolUse hook on AskUserQuestion records sha256(answer) plus the 12-hex digests the question showed, in .git, no plaintext; --confirm needs the quote to equal one answer whose question carried this exact digest; a guard stops Edit/Write/shell writes of the Confirmed line.

## O4 — What counts as "begun before 080" (escalated, developer)
**Q:** How does grandfathering decide a spec started before acceptance cases existed?
**A:** Git ancestry. Grandfathered only when the commit that first added interview.md is a strict ancestor of the commit that first added scripts/acceptance_cases.py; no arrival commit means not grandfathered.

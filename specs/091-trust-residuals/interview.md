# Spec interview — 091-trust-residuals

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO (base auto-answered with recommended; genuinely-ambiguous escalated; overflow human-answered if flagged).
Flag: hardened (trust layer under sync, nightly and acceptance gate; a new external API call; tagged
row; ≥ 6 files), so the three authorization policies go to the developer as overflow (O1–O3): what
the agent may still change about origin, the placement table, and what counts as a confirmation.

## Q1 — Scope boundary
**Q:** Which findings does 091 close?
**A (auto):** The seven the row names: F079 F080 F092 F095 F097 F104 F107. Nothing else is folded in; the open findings from 090 (F128, F129) are not on these code paths.

## Q2 — Primary actor
**Q:** Whose move does each requirement stop?
**A (auto):** The agent's (an injected or mistaken Claude session in a project or in the template), plus a third party who can name a repository or push a fork commit (F097's unanchored match, F079's fork network). The developer's own routes stay open: `!` commands, their editor, their terminal.

## Q3 — Happy path
**Q:** What does success look like on the template author's machine?
**A (auto):** Nothing visible changes: the template is still recognised (anchored URL + root commit), CORE edits there are still allowed, autosync still skips it, a pinned project on a main commit still syncs, and a confirmation still takes one AskUserQuestion. Only the attack paths change.

## Q4 — Data model: template identity
**Q:** What is the template's identity, if not its URL?
**A (auto):** The anchored URL AND the root commit d3cf8238372ce7a37d5d66b115cbcbf9d57bb2b9. Measured 2026-10-02: none of the 46 synced projects under ~/repos shares it, and reading it costs 22 ms on 463 commits.

## Q5 — Data model: replace refs and grafts
**Q:** Can the root be faked without rewriting history?
**A (auto):** `git replace` can, and `--no-replace-objects` undoes it. A `.git/info/grafts` file can too, and `--no-replace-objects` does NOT undo it (measured); `GIT_GRAFT_FILE` pointed at a missing file does. Both are applied.

## Q6 — Validation: URL forms
**Q:** Which URL spellings count as the template?
**A (auto):** `https://github.com/johanolofsson72/Claude`, `git@github.com:johanolofsson72/Claude`, `ssh://git@github.com/johanolofsson72/Claude`, each with optional `.git` and optional trailing `/`. Case-sensitive, as today. Anything else (a mirror, a GHE host) is a project.

## Q7 — Four states: impostor
**Q:** What does autosync do when the URL says template and the history does not?
**A (auto):** Nothing written, one `[warn]`. Syncing would be wrong if it is the template (a shallow clone), and skipping silently would be wrong if it is a project. A human can tell which.

## Q8 — Error semantics: pin proof
**Q:** What happens when the pin cannot be proven to be on main (offline, rate-limited, no python3)?
**A (auto):** Fail closed for the sync (nothing written, `[pin] … not synced` with the reason), fail open for the session (exit 0). A pinned project asked not to track main; an unproven pin must not mean "take whatever answered".

## Q9 — Integration: GitHub compare API
**Q:** Which call proves ancestry, and how is it read?
**A (auto):** `GET /repos/johanolofsson72/Claude/compare/<pin>...main?per_page=1`, https only, 30 s, unauthenticated (60 an hour per IP; it runs only when the stamp's SHA differs from the pin). Accept `status` ahead or identical AND `merge_base_commit.sha` == pin, read by `json.load`. Measured: the root commit answers ahead, ahead_by 462, merge base = the pin.

## Q10 — Edge cases: local clone and the pin
**Q:** Does the local-clone path fetch to check ancestry?
**A (auto):** No. It asks `merge-base --is-ancestor PIN refs/remotes/origin/main` with what the clone has. A clone that has never seen main's descendant of the pin falls through to the remote path, which asks GitHub.

## Q11 — Edge cases: skip-worktree and ignored files
**Q:** How does a "clean" clone ship bytes that are not the commit's, and what is synced instead?
**A (auto):** `git status` hides skip-worktree and assume-unchanged paths, and ignored files are copied by the `find` over `.claude/skills`. Flagged paths go through 007bi's committed-bytes staging (checkout-index from the index); skills are listed with `git ls-files`. One warning names the flagged paths.

## Q12 — Integration: claude -p flags
**Q:** Which CLI flags confine update-template's model, and what if the installed claude lacks them?
**A (auto):** `--restricted` (measured in 2.1.287 --help: confines file tools to the working dirs, ignores settings files, refuses bypassPermissions, settings/git/tool-config writes need a person), `--permission-mode dontAsk`, `--tools <list>`. If `claude --help` lacks `--restricted`, refuse with exit 2: an updater that cannot confine the model does not run.

## Q13 — Edge cases: frontmatter hooks
**Q:** --restricted may not count a skill's frontmatter as tool configuration. What catches a `hooks:` key?
**A (auto):** A post-run scan of changed and new files under `.claude/skills/` and `.claude/agents/`: a `hooks:` key between the opening `---` lines is named `[REVIEW]` and the script exits 4 after the diff. Nothing is reverted; the human reads it.

## Q14 — Data model: suite identity
**Q:** Which files fold into the suite's identity?
**A (auto):** Every file reached by a token holding `/`, glob-expanded from the repository root; a directory adds its regular files. For the template's line that is the 93 `scripts/test-*.sh`. Blob hashes via one `git hash-object --stdin-paths`. What a test sources is out of scope.

## Q15 — Reversibility: re-trust after this lands
**Q:** The identity text changes shape, so every trusted suite reads as CHANGED. Acceptable?
**A (auto):** Yes. The nightly already says "it CHANGED since it was trusted" and names `--trust`; the developer re-trusts once. Silently migrating the old hash would trust files nobody looked at, which is the finding.

## Q16 — Concurrency / ordering: cloud stamps
**Q:** The placement can change between a cloud run and the pull. Which placement decides?
**A (auto):** The one on this machine at pull time. A job the developer moved home since is not marked done by a cloud stamp; worst case it runs once more locally.

## Q17 — Authorization: secrets placement
**Q:** May any table put `secrets` in the cloud?
**A (auto):** No. Hard-coded local in workload-placement.sh, with a warning when a table says cloud. 6–51 s locally; the template's own table already says local.

## Q18 — Edge cases: confirm label
**Q:** What about the developer typing a correction instead of clicking Confirm?
**A (auto):** Recorded without a digest, so `--confirm` refuses it. Claude edits the cases from the correction and asks again; that is the flow the rule already describes ("confirm or correct").

## Q19 — Edge cases: upstream shortcut
**Q:** A fresh clone has no answer store. Is a confirmed spec still open to code there?
**A (auto):** Yes, once the Confirmed line is on `@{upstream}`, which a clone of a pushed repo always has. A local branch with no upstream gets no shortcut, and its line needs an answer recorded in this clone.

## Q20 — Non-functional limits
**Q:** What may each check cost?
**A (auto):** template_identity: one `remote get-url` plus, only when the URL matches, one rev-list (22 ms). Pin proof: one https call, only on a pinned run whose stamp differs. suite_identity: one hash-object process. Guards: no new process on a payload without a trigger word.

## Q21 — Acceptance criteria
**Q:** What proves 091 done?
**A (auto):** Each row of the spec's Problem table reproduced as a failing test before the fix and passing after; the template's own runs unchanged (exemption, sync skip, existing confirmations); the full suite green; mutation ≥ 80 % on the changed modules; /tla on the confirm binding.

## Q22 — Non-goals
**Q:** What is deliberately not attempted?
**A (auto):** Signed cloud results, a source-closure suite hash, meaning beyond "showed the cases and clicked Confirm", and a guard on `git update-ref` for remote-tracking refs. Each is a recorded residual.

## O1 — Authorization: who may rewrite a remote URL  (overflow — developer)
**Q:** With identity = anchored URL + root commit, should trust-anchor-guard also deny the agent's Bash commands that rewrite a remote URL (git remote add/set-url/rename/remove, git config remote.*.url|pushurl, url.*.insteadOf)?
**A:** Deny all remote writes.

## O2 — Authorization: who may place a job in the cloud  (overflow — developer)
**Q:** Should the agent's tools be denied writing .claude/workload-placement.tsv?
**A:** Deny agent writes.

## O3 — Input tampering: what counts as a confirmation  (overflow — developer)
**Q:** Which answers may confirm acceptance cases (the question must show every case title and the digest either way)?
**A:** Exactly "Confirm".

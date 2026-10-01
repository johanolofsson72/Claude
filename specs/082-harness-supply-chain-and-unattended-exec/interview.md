# Spec interview — 082-harness-supply-chain-and-unattended-exec

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO (base auto-answered with recommended; genuinely-ambiguous escalated; overflow human-answered if flagged).
Flag: hardened (row tag + risk domain), so the four policy questions went to the developer as overflow (O1–O4).

## Q1 — Scope boundary
**Q:** Does 082 also fix the deny-list bypasses and guard fail-opens named in F038–F042?
**A (auto):** No. Those are row 083. 082 covers the nine findings on the row and nothing else.

## Q2 — Primary actor and trigger
**Q:** Who triggers each fixed path?
**A (auto):** SessionStart hook (autosync), cron (nightly), the developer at a terminal (lane-catchup, prune, update-template, `--trust`), and Claude Code tool calls (local-llm hooks, stryker guard).

## Q3 — Happy path, autosync
**Q:** With no pin and a clean clone or no clone, what does a sync look like after 082?
**A (auto):** Same output and commits as before. The only difference is that the tarball URL names the 40-hex SHA that ls-remote returned.

## Q4 — Data model, the trust store
**Q:** Where are trusted command hashes stored, and in what shape?
**A (auto):** `.git/claude-trusted-commands`, one `<sha256>  <label>` line per command (`suite`, `mutation`). It lives in `.git/`, so it is never committed or synced, and a clone starts untrusted.

## Q5 — Validation, the pin
**Q:** What does `CLAUDE_TEMPLATE_PIN` accept?
**A (auto):** Exactly 40 hex characters, case-insensitive, normalised to lower case. A tag or short SHA is refused with a `[warn]`, because both can be moved or collide.

## Q6 — Four states, autosync refusal
**Q:** What does the developer see when a dirty clone is refused?
**A (auto):** Success: nothing changes. Error: `[warn] template clone at <path> has uncommitted changes — not synced` plus the two overrides. Empty (no clone): falls through to the remote path as before. Loading does not apply (hook output).

## Q7 — Error semantics, nightly skip
**Q:** Is an untrusted command at night an error or a note?
**A (auto):** A finding (`add`), so the run's summary is not "clean". The job is not stamped and stays due, which keeps it visible at the next SessionStart.

## Q8 — Authorization, who may trust
**Q:** May Claude run `--trust` on the developer's behalf?
**A (auto):** The script cannot tell. `--trust` prints every command it records in full, and the docs say it is a human step. Enforcing that is out of reach for a shell script: an accepted residual in the threat model.

## Q9 — Concurrency
**Q:** Two prune runs, or prune during a live agent?
**A (auto):** The existing lock/pid check stays. R10 only removes more cases from "removable", so a race can at worst keep a worktree.

## Q10 — Integration, the cron line length
**Q:** Does adding `--unattended` risk BSD cron's 999-character cap?
**A (auto):** It adds 13 characters. The installer already refuses an over-long line by name, so a long path fails loudly, not silently.

## Q11 — Edge, prune with a failed rev-list
**Q:** What if `git rev-list` errors (corrupt object, missing ref)?
**A (auto):** KEEP with the reason `cannot tell what is unique`. Today it reads as 0 and removes.

## Q12 — Edge, lane-catchup with malformed JSON
**Q:** What if `~/.claude/settings.json` does not parse?
**A (auto):** Report it and change nothing. A backup is written only when a change is about to be made.

## Q13 — Non-functional, guard timeout
**Q:** How long may a stryker_guard call take at night?
**A (auto):** 60 s per call by default, `MAINTENANCE_GUARD_TIMEOUT` to override. With no timeout binary the matcher is linear anyway, and a note says the call was unbounded.

## Q14 — Edge, symlink in template
**Q:** A symlink that points inside the template tree, is that safe to follow?
**A (auto):** It is skipped too. One rule with no resolution logic is cheaper to trust than a containment check, and the template ships no symlinks today (verified with `find -type l`).

## Q15 — Edge, OLLAMA_HOST spelling
**Q:** Which spellings count as loopback?
**A (auto):** Scheme http or https, host `127.0.0.1` (any `127.x.y.z`), `localhost`, `[::1]`, `::1`, any port. A bare `host:port` with no scheme is read as http. Everything else is remote.

## Q16 — Acceptance criteria
**Q:** What proves 082 done?
**A (auto):** The five confirmed acceptance cases pass as named tests, every R has a test in the suite, the template suite is green, and the threat model has no unmitigated threat without a recorded residual.

## Q17 — Non-goals and assumptions
**Q:** Signature verification of template commits?
**A (auto):** Out. There is no signing key today, and the developer chose exact-SHA fetch plus an opt-in pin (O1).

## Q18 — Reversibility
**Q:** How is each change undone?
**A (auto):** `CLAUDE_TEMPLATE_ALLOW_DIRTY=1`, an unset pin, and dropping `--unattended` from the cron line each restore the old behaviour. lane-catchup leaves a timestamped backup of the settings file.

## Q19 — Resource exhaustion (threat surface)
**Q:** Can a committed file still hang or flood the nightly?
**A (auto):** The glob matcher is O(len(glob) × len(path)), and each guard call is time-bounded. The suite and mutation commands keep their existing bounds. A test feeds the old pathological glob and asserts it completes in under 2 s.

## Q20 — Information disclosure (threat surface)
**Q:** Can the local-LLM hooks send repository text off the machine after 082?
**A (auto):** Only with `LOCAL_LLM_ALLOW_REMOTE=1` set by the developer. Without it a remote `OLLAMA_HOST` disables the offload before any request is made.

## Q21 — Input tampering (threat surface)
**Q:** Can the ledger report be turned into code execution or a write elsewhere by a sibling directory?
**A (auto):** No. It runs this repository's own convergence script against the sibling's data, the append refuses a symlink, and the resolved ledger path must stay inside the repository.

## O1 — Autosync source policy  (overflow — developer)
**Q:** How should template autosync decide what it fetches into the six projects?
**A:** Track main, fetch exact SHA (recommended). Default stays auto-update from main, the tarball is fetched by the exact SHA ls-remote returned, and a project can opt in to `CLAUDE_TEMPLATE_PIN=<sha>`.

## O2 — Dirty template clone  (overflow — developer)
**Q:** The local template clone has uncommitted edits. What should autosync do?
**A:** Refuse, with an opt-in override (recommended). Skip with a warning; `--force` or `CLAUDE_TEMPLATE_ALLOW_DIRTY=1` restores the `-dirty-` behaviour.

## O3 — Nightly trust model  (overflow — developer, authorization)
**Q:** The cron nightly runs `.claude/.suite-command` and `scripts/run-mutation-gate.sh` unattended. What trust model?
**A:** Hash pin in `.git` (recommended), `direnv allow` style: `--unattended` runs a declared command only when its SHA-256 matches what was recorded with `--trust`.

## O4 — Credential denies and skill clones  (overflow — developer, information disclosure + supply chain)
**Q:** lane-catchup strips `~/` deny rules, and sync-prompt clones seven skill repos unpinned. Which combination?
**A:** Keep credential denies, and pin the skills (recommended). lane-catchup keeps the `~/.ssh`, `~/.aws`, `~/.gnupg` and similar denies (backup + atomic write), and each skill clone is checked out at a recorded commit SHA in `sync-prompt.md`.

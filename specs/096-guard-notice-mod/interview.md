# Spec interview — 096-guard-notice-mod

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO (base auto-answered with recommended; genuinely-ambiguous escalated; overflow human-answered if flagged).
Flag: not large/advanced. Light track, no hardened trigger: the mod writes nothing, and its one
security piece (R6) reuses 095a's verdict. No overflow.

## Q1 — Scope boundary
**Q:** Toasts for every hook's deny, or only this template's guards?
**A (auto):** Any deny whose text starts `BLOCKED —` (the template's guard convention) and the two
fail-open phrasings. Other hooks' denies are out.

## Q2 — Primary actor and trigger
**Q:** Who sees it, and when?
**A (auto):** The developer at an interactive terminal session with the mod installed. Toasts fire after
a tool call's result; the band draws above the prompt at every render.

## Q3 — Happy-path outcome
**Q:** What does success look like?
**A (auto):** A 6-second toast "settings-edit-guard failed open: <cause>" or "denied: BLOCKED — …", and a
band "Register: 097 — prompt-audit-cleanup · maintenance due: suite, mutation".

## Q4 — Data model
**Q:** What state does the mod keep?
**A (auto):** `$.state` (session): the band text, a hidden flag. Module variables: the set of toasts
already shown and the time of the last maintenance run. Nothing in `$.store`; nothing on disk.

## Q5 — Validation and parsing
**Q:** How is the active row found?
**A (auto):** Only lines under `## Specs` up to the next `## `; the first `- [/]`, else the first `- [ ]`;
`- [!]` never. The id and slug are the first two ` — `-separated fields.

## Q6 — The four states
**Q:** Error, empty, loading?
**A (auto):** Error: the maintenance script fails or times out → `maintenance: unknown`. Empty: no
`specs/INDEX.md` → no band; no notice → no toast. Loading: the band shows the row immediately and adds
maintenance when the script answers.

## Q7 — Error semantics
**Q:** May the mod ever block or alter a tool call?
**A (auto):** Never. Every hook calls `next(e)` and returns its result unchanged; an exception in the
mod's own code is caught and the result returned (a failing hook must not lose a deny).

## Q8 — Authorization
**Q:** Who may install it?
**A (auto):** Only the developer, with `!` (095a M2). The agent's run of `install-*-mod.sh` is denied
(R6).

## Q9 — Concurrency and ordering
**Q:** Parallel tool calls raising the same notice?
**A (auto):** Dedupe by key before the toast; two calls racing may both toast once. Accepted (noise, not
loss).

## Q10 — Integration points
**Q:** What does it depend on?
**A (auto):** The `BLOCKED —` and `ALLOWED` phrasings in `scripts/guard-lib.sh` and
`settings-edit-guard-hook.sh`; `specs/INDEX.md` format; `scripts/maintenance-due.sh --brief` output
lines `  · <name> — …`. A change to any is caught by `lib.test.ts` fixtures copied from the real
text.

## Q11 — Edge cases
**Q:** A project with no maintenance script, a non-template project?
**A (auto):** No script → no maintenance part, no error. No register → no band. The toasts work in any
project.

## Q12 — Non-functional limits
**Q:** Cost per turn?
**A (auto):** A file read per turn; the script at most every 10 minutes, 20-second limit.

## Q13 — Acceptance criteria
**Q:** How is it proven?
**A (auto):** `lib.test.ts` (node --experimental-strip-types) for all classification and parsing,
`scripts/test-guard-notice-mod.sh` for layout, install and `claude plugin validate`, and the guard's
self-test for R6. The live toast and band are checked by the developer after installing (SC-A, SC-B),
since the agent cannot load a mod.

## Q14 — Non-goals and assumptions
**Q:** Assumptions?
**A (auto):** Claude Code 2.1.287+ with mods; a PreToolUse hook's additionalContext arrives in the
`tool.call` result's `context` (the reference says hook context is kept whole from `next`). If it
does not, R2 shows nothing and the developer's check (SC-A) says so: a finding, not a silent pass.

## Q15 — Reversibility
**Q:** Undo?
**A (auto):** `! bash scripts/install-guard-notice-mod.sh --uninstall`; revert the commit for the repo
side.

## Q16 — Install target
**Q:** Where does the installer put it by default?
**A (auto):** `<config>/skills/guard-notice`: measured to load in 2.1.288 with no flag and documented in
the plugin reference. `--target` for a folder the developer loads with `--plugin-dir` or
`CLAUDE_CODE_PLUGIN_DIRS` instead.
</content>
</invoke>

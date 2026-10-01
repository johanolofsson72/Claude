# Spec interview — 083-guard-bypass-and-fail-open

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO (base auto-answered with recommended; genuinely-ambiguous escalated; overflow human-answered if flagged).
Flag: hardened (row tag + risk domain: the enforcement boundary itself), so the three policy questions go to the developer as overflow (O1–O3).

## Q1 — Scope boundary
**Q:** Does 083 also touch the autosync sandbox leaks (F013–F020) or the template mutation runner?
**A (auto):** No. Those are rows 084 and 085. 083 is the eight guard findings on its row.

## Q2 — Primary actor and trigger
**Q:** Who triggers the changed paths?
**A (auto):** Claude Code, once per tool call (PreToolUse: Read, Edit, Write, MultiEdit, NotebookEdit, Grep, Glob, Bash), and once per session (SessionStart, R11). The developer only sees the deny reason or the notice.

## Q3 — Happy path
**Q:** What does an ordinary session look like after 083?
**A (auto):** Identical to today on a machine with jq and python3. No new prompts and no new output. The only visible change is a deny where a bypass used to pass.

## Q4 — Data model
**Q:** Does 083 add any persisted state?
**A (auto):** No. Verdicts are computed per call. R11 prints from the SessionStart hook, which runs once per session by construction, so no marker file is needed.

## Q5 — Validation: what is a canonical path?
**Q:** Lexical normalisation or full symlink resolution?
**A (auto):** Both, split: the deepest existing ancestor directory resolved physically with `cd -P`, the non-existent tail normalised lexically. A Write to a new file has no physical path yet, and a symlinked directory must not hide a CORE file.

## Q6 — Validation: what counts as a tick?
**Q:** Line-level `- [x]` or row-id level?
**A (auto):** Row-id level. A tick is an id whose status is `[x]` in the resulting file and was not `[x]` before. That ignores rewording a ticked row (archive-completed-rows shortens them) and catches the split Edit.

## Q7 — Four states: success
**Q:** What does a correct allow look like?
**A (auto):** No output, exit 0, as today.

## Q8 — Four states: error
**Q:** What does a deny look like?
**A (auto):** Exit 0, one JSON object with `hookEventName: PreToolUse`, `permissionDecision: deny` and a reason that names the guard, the cause and the repair. Never the command text for Bash (FR-015 of bash-write-guard: commands can carry secrets); derived paths only.

## Q9 — Four states: empty
**Q:** What if the payload has no path or command?
**A (auto):** Allow silently. An empty field is an answer (nothing to judge), unlike an unparseable payload.

## Q10 — Four states: loading / degraded
**Q:** What is the "cannot decide" state?
**A (auto):** No parser, malformed payload, or a crashed resolver. Fail-closed guards deny with the cause (R2). Fail-open guards allow with an `additionalContext` notice (R3). Neither is silent.

## Q11 — Error semantics: recoverable?
**Q:** How does the developer recover from a no-parser deny?
**A (auto):** Install jq or python3. Until then, edits under the root `scripts/`, `specs/` and `.claude/` stay allowed, so the tooling can be repaired. The deny says this.

## Q12 — Authorization
**Q:** Who can override?
**A (auto):** The existing env overrides stay (ALLOW_CORE_MACHINERY_EDIT, ALLOW_TICK_WITH_CORE_OWED). R9 and R10 get none, matching the settings deny list. The model asks the developer to run the command with `!`.

## Q13 — Concurrency
**Q:** Are there ordering concerns between guards?
**A (auto):** No new ones. Hooks for one call run in parallel and any deny wins. R11 runs once at SessionStart. The tick guard reads the register at hook time, and the Edit applies afterwards. The window is the same as core-machinery's (spec 039) and accepted there.

## Q14 — Integration: settings wiring in projects
**Q:** How do the two new guards reach the six projects?
**A (auto):** As CORE scripts with script-backed hooks: `sync-core-hooks.py` appends a template core hook when its script exists in the project. The old inline sensitive-file hook is retired by exact text match, only when the replacement script is present.

## Q15 — Integration: bash-write-guard delegation
**Q:** Do the delegated guards see canonical paths when called from bash-write-guard?
**A (auto):** Yes. Each guard canonicalises its own input (R4), so the delegate path inherits it with no change in bash-write-guard.

## Q16 — Edge: payload size
**Q:** What about payloads over 4096 bytes?
**A (auto):** The 4096-byte precheck bound stays (it is a speed bound). Above it, the guards parse exactly as today, but with the R1 fallback, so size no longer decides fail-open.

## Q17 — Edge: quoted text in Bash
**Q:** Does `git commit -m "remove rm -rf from docs"` trip R9 or R10?
**A (auto):** R9: no. Quoted arguments to a non-shell command are data. R10: only when a token is itself path-shaped and sensitive. A commit message token is one string whose segments are not `.ssh` and so on.

## Q18 — Edge: template repo
**Q:** Do the new guards apply in the template repo itself?
**A (auto):** Yes. They are not ownership guards, so there is no reason to self-exempt. The template's own commands must pass. The suite proves that by running in this repo.

## Q19 — Non-functional: cost
**Q:** What may R9/R10 cost per Bash call?
**A (auto):** A bash-only precheck first. Python starts only when the raw command contains a trigger word (`rm`, `sudo`, `git`, `find`) or a sensitive name. Target under 10 ms for the common case, the same budget spec 073 set.

## Q20 — Acceptance criteria
**Q:** What proves 083 done?
**A (auto):** The five acceptance cases, one test per R with a sabotage arm each (the hard mutation gate stand-in until row 085), R8's sweep over every wired guard, and the full template suite green.

## Q21 — Reversibility
**Q:** How is 083 rolled back?
**A (auto):** One revert. The settings change is two hook entries and one retired inline hook. The retire step keys on exact text, so reverting the template restores the old hook in the next sync.

## O1 — `.env.example` and friends  (overflow — developer, information disclosure)
**Q:** Now that R10 covers Bash, Grep and Glob, what should `.env.<suffix>` do?
**A:** Allow example/sample/template (recommended). `.env.example`, `.env.sample` and `.env.template` pass; `.env`, `.env.local`, `.env.production` and every other suffix stay blocked.

## O2 — `find -delete` in the destructive guard  (overflow — developer, availability)
**Q:** Should R9 deny `find … -delete` and `find … -exec rm`, which are not in today's deny list?
**A:** Deny them (recommended). Same blast radius as `rm -rf`, same `!` escape.

## O3 — Fail-closed when tooling is missing  (overflow — developer, availability vs bypass)
**Q:** With neither jq nor python3, what do the three pipeline guards do?
**A:** Deny source edits (recommended), naming the missing tool. `scripts/`, `specs/` and `.claude/` at the root stay editable so the tooling can be repaired.

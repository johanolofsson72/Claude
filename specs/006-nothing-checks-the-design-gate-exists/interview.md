# Spec interview — 006-nothing-checks-the-design-gate-exists

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO (base auto-answered with the recommended option; no hardened trigger fired: spec-only,
no new entity, 5 files, no external surface, so no overflow).

## Q1 — Scope boundary
**Q:** Which skills are in the required set?
**A (auto):** `frontend-design` and `humanizer`, the two skills `CLAUDE.md` calls BLOCKING that do not ship with the template.

## Q2 — Scope boundary (out)
**Q:** Are spec-kit skills and the template's own `.claude/skills/` in scope?
**A (auto):** No. Spec-kit presence is `project-maintenance.sh` §3b, and shipped skills arrive with the sync.

## Q3 — Primary actor & trigger
**Q:** Who calls the predicate?
**A (auto):** `ui-design-hook.sh` on each UI edit (PreToolUse) and `project-maintenance.sh` on each maintenance pass. A developer can run it by hand.

## Q4 — Happy path
**Q:** What happens on a machine where both skills are installed?
**A (auto):** Nothing new. The hook emits the same payload as today and maintenance adds no line.

## Q5 — Data model
**Q:** What does the predicate read?
**A (auto):** `<project>/.claude/skills/<name>/SKILL.md`, `<cfg>/skills/<name>/SKILL.md`, `<cfg>/plugins/installed_plugins.json` (each `installPath`) and `enabledPlugins` in the user, project and local settings files. Read only.

## Q6 — Validation rules
**Q:** When does a plugin skill count as reachable?
**A (auto):** When `<installPath>/skills/<name>/SKILL.md` exists and the plugin key is not set to `false` in the highest-precedence settings file that mentions it.

## Q7 — Qualified names
**Q:** How is `plugin:skill` handled?
**A (auto):** Only that plugin's install paths are searched; project and user skill dirs are skipped.

## Q8 — Four states: error
**Q:** What does the developer see when `frontend-design` is missing during a UI edit?
**A (auto):** One `systemMessage` line: the gate cannot be met, plus the install command. The model gets the full explanation as additionalContext.

## Q9 — Four states: empty / cannot tell
**Q:** What if the plugin registry is missing or python3 is absent?
**A (auto):** A missing registry means no plugins, which is a normal "missing" result. With no python3 the plugin half cannot be read: exit 3, the hook falls back to today's output, and maintenance records a note.

## Q10 — Error semantics
**Q:** Is a missing skill fatal to the edit?
**A (auto):** No. It is advisory and loud (see Clarifications). A deny would stop work the developer cannot fix mid-edit.

## Q11 — Authorization
**Q:** Any authorization surface?
**A (auto):** None. Local read-only file checks, no network.

## Q12 — Concurrency
**Q:** Can concurrent hook runs interfere?
**A (auto):** No. The script writes nothing.

## Q13 — Integration: CORE sync
**Q:** Do projects get the new scripts?
**A (auto):** Yes. Both go into `CORE_SCRIPTS`; `test-sync-prompt-core-parity.sh` reads that list, so `/project-update` follows.

## Q14 — Edge case: disabled plugin
**Q:** Installed but disabled in project settings?
**A (auto):** Missing. The Skill tool would not load it, and the check has to agree with the Skill tool.

## Q15 — Edge case: stale cache hash
**Q:** The plugin cache holds several hash dirs; which counts?
**A (auto):** Only `installPath` entries from the registry. A leftover hash dir does not make a plugin installed.

## Q16 — Non-functional: latency
**Q:** Cost on each UI edit?
**A (auto):** One python3 start, and only on edits that already passed the UI-extension filter. Non-UI edits pay nothing extra.

## Q17 — Acceptance criteria
**Q:** How is "done" measured?
**A (auto):** The test harness passes with every case bite-checked. `--required` exits 0 here, a fixture without the plugin makes the hook emit a `systemMessage`, and the existing maintenance and hook tests stay green.

## Q18 — Non-goals
**Q:** Auto-install?
**A (auto):** No. Installing a plugin or cloning a repo is the developer's call. The check prints the command.

## Q19 — Reversibility
**Q:** How is it rolled back?
**A (auto):** Revert the commit. The hook's old output is still the fallback path, so removing the script restores the old behaviour.

## Q20 — Config dir
**Q:** Is `~/.claude` hard-coded?
**A (auto):** No. `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`, which is also what lets the tests run on fixtures.

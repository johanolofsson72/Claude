# Prompt audit: /Users/jool/repos/Claude

Date: 2026-10-03. Template repo at `b01be40` (working tree has uncommitted `specs/FINDINGS.md` and `specs/INDEX.md`, not touched).

## Step 0: assumptions

- **Scope:** `CLAUDE.md`, `.claude/rules/*.md` (22 files, 11 always-loaded counting CLAUDE.md, the rest path-scoped), `.claude/agents/*.md` (4), `.claude/skills/*/SKILL.md` (11). Also reported on, never edited: `~/.claude/CLAUDE.md` and `~/.claude/projects/-Users-jool-repos-Claude/memory/MEMORY.md`. Hook scripts that inject text (`scripts/emit-*.sh`) and `.claude/settings.json` are outside the requested scope. Where they matter they are listed as `flag` only. Both settings files were read with the Read tool, only to check the `language` key and the hook wiring.
- **Target model:** Claude Opus 5.5 for the main session and every unpinned file. Pinned subagents: `dotnet-reviewer` and `security-scanner` on Sonnet 5.5 (`model: sonnet`), `test-runner` on Haiku 4.5 (`model: haiku`), `db-agent` inherits Opus 5.5.
- **Provenance:** spec 081 (`bddad8c`, 2026-10-01) rewrote every always-loaded file, so `git blame` puts most lines on the same day. When two passages disagree I ordered them by when the concept first showed up (`git log -S`) and by which side a hook enforces.

## Summary

The always-loaded surface is in better shape than most. Spec 081 already took out most of the shouting, and the pressure-word count is low (CLAUDE.md has 10, all but one of them the defined `(BLOCKING)` label). What's left is mostly **Group 2: files contradicting each other**. Three findings matter most:

1. **CLAUDE.md contradicts the rules it points to, four separate times.** "Medium (2–5 files) → brief plan" says one thing and feature-pipeline's "2+ files is not trivial" says another. "Larger features: interview the developer" clashes with the AUTO spec interview. "/tla on full/light" clashes with "light skips /tla unless state is non-trivial". And "max 3 attempts" sits next to "after 2 failed fixes, /clear" in the same file, while the hook enforces 3. Opus 5.5 follows instructions literally, so every one of these pairs makes the model pick a side. The `/project-wizard` CLAUDE.md template has the same four contradictions and still carries the pre-081 ALL-CAPS text, so every new project inherits them.
2. **There are two stop lists.** `feature-pipeline.md` "When to stop" gives 3 legitimate stops and `continuous-execution.md` gives 7. Both are always loaded, and the shorter one forbids the status-summary stop that `spec-register.md` requires.
3. **Broken script path in `ui-ux-pro-max`:** 12 commands say `python3 skills/ui-ux-pro-max/scripts/search.py`. That path doesn't exist from the project root. The script lives at `.claude/skills/ui-ux-pro-max/scripts/search.py`. One more copy is in project-wizard.

Counts: Group 1 (dated text): 9 · Group 2 (config files): 14 · Group 3 (tool descriptions): not applicable (no tool definitions; skill descriptions are trigger text and were left alone) · Group 4: 1 (subagent per-call reminder), the rest not applicable (no request code).

**Bytes saved from always-loaded context if every hunk is taken: 1,346 bytes** (38,265 → about 36,919; ~340 tokens). Per file: spec-interview 403, feature-pipeline 302, carve-budget 223, spec-hardening 183, spec-register 158, CLAUDE.md 143, continuous-execution −66 (it grows). The on-demand files shrink too: project-wizard 637, dotnet-reviewer 234, tla 36, allium 15. ui-ux-pro-max grows 96 because of the longer path.

The size win is small and isn't the point. The point is that the always-loaded set stops disagreeing with itself.

## Language contradiction: verdict

What wins in this repo is **English**, and the files don't actually conflict here:

- `.claude/settings.json:494` has `"language": "english"`. Claude Code builds the session's `# Language` block from that key.
- `~/.claude/CLAUDE.md` says Swedish is only the default and that "a project's own setting wins over this line", naming that exact key. So the global file gives way to the repo by its own wording.
- Project `CLAUDE.md:40` says English. MEMORY.md says English.

So the outcome is the same everywhere. The cost is redundancy and a misleading memory line:

- The MEMORY.md line "Communicate in English (migrated from Swedish on 2026-04-02)" sits under "User preferences", which makes it read like a global user preference. It's really a fact about this one project, and on the user level it is false: the global default is Swedish. It is also a migration fossil.
- Project `CLAUDE.md:40` restates the settings key, but it also covers commits, docs and code comments, which the `language` key doesn't. That part is useful.

**Cleanest consistent fix:** keep `settings.json` `language` as the one source for conversation language. Keep `CLAUDE.md:40` for artifacts, and optionally point it at the setting ("Conversation language comes from `language` in `.claude/settings.json`; commits, docs, code and comments are English."). In MEMORY.md (outside the repo, so not in the patch), replace the line with: `- Language: this project converses in English via .claude/settings.json "language"; the global default is Swedish.` The global CLAUDE.md is fine as it is. Its dated paragraph ("Fram till 2026-08-26 …") is history, but it carries the reason for the precedence rule, so I'd keep it.

One thing I'm not sure about: whether the `language` key is copied into downstream projects by `/project-update` / `sync-template`. If it is, every project created from the template converses in English no matter what the global default says. That may be what's wanted, but nothing states it.

## Persona vs. the project's tone requirements (reported, not edited)

The global `## Persona` says to communicate "**exclusively** through filthy, creative sexual innuendo" and "never be clinical". Three places in the project's own requirements collide with that:

1. **Fixed-wording outputs.** `validation-followup.md:10` requires a verbatim sentence. `spec-register.md:55-72` defines a fixed status-summary template. Spec-interview answers and `AskUserQuestion` options have set formats too. "Exclusively" leaves no room for these.
2. **Human-facing artifacts.** `CLAUDE.md:18` routes commits, PRs, docs, email and README through `humanizer`. Humanizer strips AI tics, but it doesn't change register, so a commit written in the persona's voice comes out of humanizer still in that voice. In practice the conflict is real for anything that leaves the terminal: git history, READMEs, and email through `johanizer`.
3. **"Flag *everything*"** (Code review style) pushes toward more findings, while `carve-budget.md` exists to make the backlog converge. The audit guide's row 1a also applies: an unscoped "flag everything" tends to over-trigger on current models.

Suggested scoping line for the global file (the user's call, outside the patch): *"The persona applies to conversational replies only. Commits, PRs, docs, emails, fixed-format summaries and AskUserQuestion text follow the project's tone and go through humanizer."*

## Findings

### High confidence (contradicted by the repo itself)

| # | Location | Evidence | Pattern | Why | Action |
|---|---|---|---|---|---|
| F1 | `CLAUDE.md:78` vs `CLAUDE.md:25` | "After 2 failed fixes of the same problem: `/clear`" vs "**Max 3 attempts per problem** … `repeat-failure-guard-hook.sh` enforces this" | G2 contradiction | The hook's `ATTEMPT_LIMIT` defaults to 3. The pre-081 text already had both lines (`claude-md-rationale.md`). | remove line 78 (in patch) |
| F2 | `CLAUDE.md:56` | "Medium (2–5 files) → brief plan, then do it." | G2 contradiction | `feature-pipeline.md:41`: "Anything touching 2+ files … is not trivial", and the pipeline guards hard-block edits. The rule is the one enforced. | rewrite: "Trivial (the one-file cases listed in feature-pipeline.md) → do it. Everything else runs the pipeline." (in patch) |
| F3 | `CLAUDE.md:28` | "**Larger features:** interview the developer (`AskUserQuestion`), then write a spec before coding." | G2 contradiction | `spec-interview.md` defaults to AUTO (memory: changed to auto 2026-07-08). Human questions only come up for escalations and overflow. This line is older. | remove (in patch) |
| F4 | `CLAUDE.md:68` | "6. UI: `/tla` has run (full/light tracks)." | G2 contradiction | `feature-pipeline.md:34`: light track "skip `/tla` unless the state is non-trivial". "UI:" is also the wrong qualifier, since /tla depends on the track, not on whether there's UI. | rewrite (in patch) |
| F5 | `.claude/rules/feature-pipeline.md:51-53` vs `continuous-execution.md:9-17` | "Only for genuine ambiguity …, a hard blocker …, or Allium/TLA+ findings." | G2 contradiction | continuous-execution lists 7 stops: the spec-end status summary, register rewrite and convergence stop are missing here. The "When to stop" text dates from 2026-05-14 and the 7-item list is newer (convergence stop added later). | rewrite to point at continuous-execution (in patch) |
| F6 | `.claude/skills/ui-ux-pro-max/SKILL.md:148,159,167,176,192,210,264,273,276,282,295,298`; `.claude/skills/project-wizard/SKILL.md:881` | `python3 skills/ui-ux-pro-max/scripts/search.py` | G2 volatile specifics | That path doesn't exist from the project root. The script is `.claude/skills/ui-ux-pro-max/scripts/search.py`. Every flag used in the skill (`--design-system`, `--persist`, `--page`, `--domain`, `--stack`, `-n`, `-p`, `-f`) is still defined in `search.py`. | rewrite path (in patch) |
| F7 | `.claude/skills/tla/SKILL.md:156`, `.claude/skills/allium/SKILL.md:321` vs `.claude/rules/validation-followup.md:10` | three different "say verbatim" zero-findings sentences | G2 contradiction | The rule is always loaded, so whenever a skill runs, two "verbatim" sentences are in context at once. No script matches any of them (grepped `scripts/`). | rewrite skills to defer to the rule's sentence (in patch) |
| F8 | `.claude/skills/project-wizard/SKILL.md:538` | "Use the hireflow CLAUDE.md as the reference template — it is the most up-to-date version." | G2 stale fact | It points at another repo. After spec 081 the template's own `CLAUDE.md` is the newest version, and hireflow can't be checked from here. | rewrite to `$TEMPLATE/CLAUDE.md` (in patch) |
| F9 | `.claude/skills/project-wizard/SKILL.md` generated-CLAUDE.md block (~556-690) | `## Critical rules (READ FIRST)`, seven `**ALWAYS**` bullets, "**BLOCKING REQUIREMENT**" ×2, "**IMPORTANT:** ALWAYS … NEVER guess.", plus copies of F1-F4 | G1a pressure + G2 contradiction | This is the pre-081 CLAUDE.md, and it gets stamped into every new project. Opus 5.5 over-applies stacked ALWAYS. Each new project also inherits the F1-F4 contradictions. | rewrite critical rules plainly; drop the "Interview pattern", "After 2 failed" and "IMPORTANT" lines; fix the triage and /tla lines (in patch). The rest of the block (Execution mode, Priority order) carries the same pre-081 tone; left for the user, low |
| F10 | `scripts/emit-pipeline-reminder.sh:8` (UserPromptSubmit hook text) | "(1) Write spec with destructive browser tests (min 8 scenarios, 6 attack categories) … (2) IMMEDIATELY after spec is written: run /speckit-clarify" | G2 contradiction + G1a | It contradicts "sized per function, not a flat quota" (CLAUDE.md:19, tests.md:57, specs.md:92) and leaves out the spec interview that `spec-interview.md` puts between specify and clarify. Heavy caps too: "MANDATORY", "IMMEDIATELY", "Do NOT ask … Asking is a bug". This text reaches the model on every matching prompt. | **flag** (scripts are outside the requested scope). Suggested: drop the quota, insert "(1b) spec interview → interview.md", lower the caps |

### Medium confidence (documented pattern)

| # | Location | Evidence | Pattern | Why | Action |
|---|---|---|---|---|---|
| F11 | `.claude/rules/spec-register.md:11` vs `project-workflow.md:13` | "**Commit and push to `main` directly** (solo, no PRs, no feature branches)." | G2 contradiction | project-workflow says `PRs=yes` → the standard PR flow. The register rule hardcodes solo even though it has its own "Two lanes" section. project-workflow (2026-05-02) is older, but it's the rule built to decide this question. | rewrite to defer to project-workflow, keeping solo as the default (in patch) |
| F12 | `.claude/rules/continuous-execution.md:11` vs `.claude/rules/scenarios.md:212` | scenarios.md: a scenario gap "is a legitimate stop under `continuous-execution.md`" | G2 contradiction | continuous-execution doesn't name it. The model has to infer that it falls under "genuine ambiguity". | rewrite item 1 to name it (+66 bytes, in patch) |
| F13 | `.claude/rules/spec-register.md:90-92` | 7-item "Forbidden" paragraph | G1c prohibition list / repetition | 5 of the 7 restate the contract in the same file (lines 9-15, 76) or continuous-execution. The full list with reasons stays in `spec-register-rationale.md` § What this rule forbids. | keep the two new items, drop the restatements (in patch) |
| F14 | `.claude/rules/feature-pipeline.md:47-49` | 6-item "Forbidden" | G1c | 4 of 6 restate lines 7 and 14-16 of the same file or spec-interview.md. "Happy-path-only tests" and the /tla clause add information and stay. | trim (in patch) |
| F15 | `.claude/rules/spec-hardening.md:24-26` | 6-item "Forbidden" | G1c | 5 restate the triggers, the four additions and the fresh-context section. The GitHub-Action item is the only new fact. | rewrite as a one-line "Where it runs" (in patch) |
| F16 | `.claude/rules/carve-budget.md:15-17` | 7-item "Forbidden" | G1c | 5 restate contract items 1-5. "A third carve without folding" and "'The finding was real'" are new (the latter is incident-backed in `carve-budget-rationale.md`). | trim (in patch) |
| F17 | `.claude/rules/spec-interview.md:74-82` | 7-bullet "What this rule forbids" | G1c | 4 restate lines 7, 8, 23 and 33. The overflow bullet is kept because line 12 alone ("should almost always") is weaker, so dropping it would loosen the rule. | trim to the 4 bullets that add information (in patch) |
| F18 | `.claude/rules/spec-interview.md:29` | "a spec begun before 080 arrived (ticked task, no `acceptance.md`, interview committed before it, by ancestry)" | G1d migration-relative / G2 history | The guard (`acceptance_cases.py:325`) owns the grandfathering, and the rationale doc has the details. The model can't act on "by ancestry". Tests grep their own fixtures, not this rule text. | rewrite to "specs the guard grandfathers" (in patch) |
| F19 | `CLAUDE.md:5,9,17` | "Critical rules (READ FIRST)", "BEFORE answering", "BEFORE writing any UI code" | G1a | Caps emphasis on top of the defined `(BLOCKING)` label adds nothing for Opus 5.5. The `(BLOCKING)` markers stay because line 7 defines them. | lowercase (in patch) |
| F20 | `.claude/rules/spec-hardening.md:5` | "When a spec is HARDENED" | G1a | Same as F19. | lowercase (in patch) |
| F21 | `.claude/agents/dotnet-reviewer.md:7-12` | PostToolUse hook echoing "Focus on .cs file changes only. Ignore generated files and migrations." after **every** Bash call | G1d instruction re-insertion | It re-injects text the prompt body already holds (line 19) on every call. Sonnet 5.5 keeps a once-stated instruction, and per-call repeats cost tokens. `.claude/docs/agents-templates.md` quotes the same hook as an example. Update it if this hunk is taken. | remove the hook, fold "skip generated files and migrations" into line 19 (in patch) |

### Low confidence / flag only (not in the patch)

| # | Location | Note |
|---|---|---|
| F22 | `.claude/rules/scenarios.md` (26,016 bytes, path-scoped on `**/specs/**`, `**/spec*.md`) | It loads on essentially every pipeline run, but `context-budget.sh` only counts unscoped rules, so it escaped 081's trim. It's 3× the largest always-loaded rule. Suggest the 081 treatment: contract in the rule, long form in `scenarios-rationale.md`. Too large to do safely as one patch hunk. `specs.md` (11 KB, same globs) is a smaller version of the same case. |
| F23 | `CLAUDE.md:7` | "(BLOCKING) rules are enforced by hooks and by the Definition of Done." The humanizer rule (line 18) has no in-session hook (`local-llm-humanize-hook.sh` isn't wired in settings.json; memory says it runs nightly), and it isn't in the DoD. The claim is partly false. Rewording it would weaken a stated requirement, so it's flagged only. |
| F24 | MEMORY.md "ALL generated text MUST go through humanizer skill (100%, no exceptions except code)" vs `CLAUDE.md:18` "human-facing text (docs, commits, PRs, email, README)" | Scope disagreement (all text vs human-facing artifacts), plus caps. Outside the repo. Suggest aligning the memory line to CLAUDE.md's scope. |
| F25 | MEMORY.md "Hooks can **now** be defined in SKILL.md…(since v2.1.0)"; "Prompt hooks … deterministic" | Migration-relative phrasing. Also, `type: "prompt"` hooks are model-evaluated, so they aren't deterministic. Outside the repo. |
| F26 | `.claude/skills/project-wizard/SKILL.md:134` | "⚠️ **IMPORTANT**: Speckit skills … are NOT available as slash commands in this session … requires a restart." I believe current Claude Code hot-reloads skills added under `.claude/skills/` mid-session, which would make this a fossil. I haven't verified it against this install, so it isn't in the patch. |
| F27 | Hardened triggers stated 4 times (`CLAUDE.md:14`, `feature-pipeline.md:32`, `spec-interview.md:12`, `spec-hardening.md:7`). Spec-kit checklist stop stated twice (`feature-pipeline.md:22`, `continuous-execution.md:7`). | The copies currently agree, so per keep-list item 8 they stay. Mentioned because a future edit to one copy will create a conflict. |
| F28 | `"the full pre-081 text"` in the rationale pointers of 8 always-loaded rules | History phrasing (G2), about 25 bytes each. It accurately describes what the doc contains, so it's left alone. |
| F29 | `.claude/settings.json` PostToolUse UI-test message (line 180) and PreCompact echo (line 374) | "BLOCKING VALIDATION REQUIRED … Do NOT skip … Do NOT declare", "IMPORTANT: Preserve …". G1a pressure inside hook text. Settings files are outside the scope and guarded. |
| F30 | `.claude/skills/tla/SKILL.md:152`, `allium/SKILL.md:319` | "batched in a single tool call … one question per finding". If `AskUserQuestion` caps questions per call (I believe it's 4), a run with more findings can't follow the rule as written. Not verified. |
| F31 | `.claude/rules/spec-hardening.md:7` "When in doubt, harden." | An "if in doubt" construction, but it's a deliberate risk policy (keep-list 1). Kept. |

### Keep list (matched a grep, deliberately untouched)

- `github-actions.md:3` iskvalp incident (3000 min in four days). It's a measured incident and the reason for the rule.
- `continuous-execution.md:7` "Never ask 'Phase 1 complete, should I continue?'". The Stop hook `continuous-execution-hook.sh` still catches this failure, so it's current.
- `validation-followup.md:10` verbatim sentence and `spec-register.md` status template. They pin a format and stay.
- `spec-interview.md:27` "Never confirm on the developer's behalf". A real constraint that is hook-enforced.
- `tla/SKILL.md:298-332` "CRITICAL: Process lifecycle rules". A fragile operation backed by the TLC CPU incident in memory, so the exact script stays.
- `allium/SKILL.md:71,87,247` "`-- allium: 3` MUST be line 1". A format contract checked by `allium check`.
- Skill `description` fields. Trigger text; Group 3's urgency exception applies.
- All `(BLOCKING)` labels in CLAUDE.md. They're defined vocabulary that hooks and the DoD key off.

## Stale paths check

Every `scripts/*.sh|py|tsv`, `.claude/docs/*`, `.claude/rules/*` and `.claude/skills/*` path named in the scoped files resolves, apart from F6. The misses were all downstream-project or generated paths, which aren't contradictions: `specs/SCENARIOS.md`, `specs/INDEX.notes.md`, `specs/PHASE-DEBT.md`, `.claude/.sync-stack`, `.claude/.template-sync`, `.claude/.runtime-markers`, `.claude/skills/graphify/SKILL.md` (written by `graphify install`), and `.claude/agents/custom-agent.md` (a placeholder in a sample report). `CLAUDE.md:110` names `.claude/docs/<rule>-rationale.md` generically, but only 11 of the 22 rules have one (low).

## Verification done

- `git apply --check prompt-audit.patch` passes against the current working tree.
- Out-of-band grep for every removed or changed phrase across `scripts/`, `tests/`, `.claude/docs`, `.claude/skills` and `.claude/rules`. No test or hook matches the removed rule text. `HARDENED` and `begun before 080` appear in tests only as their own fixture strings or comments. `READ FIRST` in `specs.md:15` is a different heading and is untouched.
- `context-budget.sh` on the patched copies stays within the cap.
- Not done: behavioural probes (Step 7). Each removal is a hypothesis. The F1-F5 contradiction fixes are the low-risk ones; the Forbidden-list trims (F13-F17) are the ones to watch, and if a regression shows up, put back the single line.

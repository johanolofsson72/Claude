# Plan — 096

| R | Files | Test |
|---|---|---|
| R1 | `mods/guard-notice/` (`plugin.json.staged`, `hooks.json.staged`, `register.tsx`, `lib.ts`, `types/index.d.ts`) | `scripts/test-guard-notice-mod.sh` layout arm |
| R2 R3 | `lib.ts` `failOpenNotices`, `denyLine`, `Seen`; `register.tsx` `tool.call` hook | `mods/guard-notice/lib.test.ts` |
| R4 | `lib.ts` `activeRow`, `maintenanceDue`, `bandText`; `register.tsx` `session.start`, `turn.complete`, `ui.render AbovePrompt` | `lib.test.ts` |
| R5 | `scripts/install-guard-notice-mod.sh` | `scripts/test-guard-notice-mod.sh` |
| R6 | `scripts/settings_guard.py` (`MOD_INSTALLER`), `settings-edit-guard-hook.sh` wake on `-mod.sh` | `scripts/test-settings-edit-guard.sh` [096-R6] |
| R7 | `.claude/docs/workflows.md`, installer header | — |

Order: frontend-design pass → lib.ts + lib.test.ts → register.tsx → staged JSON + types → installer + its
test → R6 in the guard + arms → docs → converge, simplify, full suite.

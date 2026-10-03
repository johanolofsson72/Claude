# Plan — 095a

| R | Files | Test |
|---|---|---|
| R1 | `scripts/settings_guard.py`: `ModZones` (load roots, ancestor walk with cache), `Guarded.file_of` / `is_dir` / `glob_hit` consult it, `Guarded.mod_of` | `test-settings-edit-guard.sh` [095a-R1], PBT over generated paths |
| R2 | `settings_guard.py` `edit_verdict`: a mod path is `mod-file` before any settings parsing | [095a-R2], 095a-AC-1, AC-2, AC-4 |
| R3 | `bash_verdict` unchanged; `main()` renames a `settings-bash` hit on a mod path to `mod-bash`; by-name adds `hooks.json` | [095a-R3], 095a-AC-1, AC-4 |
| R4 | `Repo` gains mod candidates (`ls-files`, `ls-tree -r --name-only` per named revision, untracked mod files); `compare` treats a mod rel as "any change"; `main()` renames to `mod-git` | [095a-R4] fixture repo, 095a-AC-3 |
| R5 | `mcp_verdict` unchanged (it goes through `file_of`/`is_dir`); rename to `mod-file` | [095a-R5], 095a-AC-1 |
| R6 | `settings-edit-guard-hook.sh` pre-check: wake words, ancestor walk on `file_path` and `cwd` | [095a-R6] end to end |
| R7 | hook `case` arms `mod-file`, `mod-bash`, `mod-git`; repair path unchanged | [095a-R7] |
| R8 | `specs/095a-mod-loading-guard/probe-autoload.py` | run once by hand, result in spec.md |
| R9 | hook header, `.claude/docs/security.md`, `.claude/docs/workflows.md` | — |
| R10 | `settings_guard.py` `claude_cli_verdict` inside `_bash_verdict` | [095a-R10] |

Order: tests first (sections 095a-R1..R10 and the AC cases) → `ModZones` + `file_of` (R1) → edit (R2) →
shell/MCP rename (R3, R5) → R10 → git (R4) → hook pre-check and text (R6, R7) → docs (R9) → suite,
mutation gate, adversarial review, `/tla`.

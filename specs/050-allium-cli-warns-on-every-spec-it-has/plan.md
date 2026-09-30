# Plan — 050

1. Tests red first in `scripts/test-allium-check-hook.sh`: fake CLIs that answer `--version` with
   3.2.3, 3.3.0 and garbage; arms for FR-01..03; a sabotage arm that flips the comparison.
2. `scripts/allium-check-hook.sh`: after the CLI-present check, read the version, compute
   `OLD_NOTE` below 3.3.0. At the end: a block appends `OLD_NOTE` to its reason; a pass emits it
   through `notice_once`. Header comment: replace the "warns on nearly every spec" line.
3. `.claude/skills/allium/SKILL.md`: example `deferred … -- see: …`; INVALID rows; Validation
   section with the floor and F089.
4. `.claude/rules/allium.md` Validation text; `scripts/sync-prompt.md` install floor.
5. `upstream-issue-f089.md` draft.
6. Verify: hook suite, the skill's full reference example through real 3.6.1 and 3.2.3, bash -n.

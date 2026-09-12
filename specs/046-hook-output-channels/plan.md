# Plan — 046

1. `scripts/hook-notice.sh` — one emitter, four verbs, session-keyed dedupe.
2. Convert PostToolUse advisories (tla, test-coverage, spec-md-coverage,
   scenario-map, allium, after-specify) to `notice_model` / `notice_once`.
3. Convert SessionStart orientation (register, sync-verify, lane, scenario-map,
   stack-canary) to `notice_model SessionStart`; autosync to `notice_both`.
4. Nest `additionalContext` in all 42 offenders, with the right event name.
5. Add `hookEventName` to all seven PreToolUse deny sites; verify live.
6. Anchor the spec-coverage reminder on the speckit path shape.
7. `scripts/harness-state-gc.sh`, wired to SessionEnd + SessionStart.
8. CORE manifest + test fixtures carry the new files.
9. Rewrite the docs table; add `scripts/test-hook-channels.sh`.

# Plan — 029

1. `scripts/hook-verdict.sh` with `hook_verdict` (R1).
2. Route the five guard tests through it: jq decoders call `hook_verdict`, and python decoders apply the same rule (R2).
3. `test-hook-channels.sh`: per-emit-site check over scripts and inline settings (R3), plus sabotage arms (R4).
4. `scripts/probe-live-deny.sh` (R5). Run it once here.
5. CORE list, workflows.md, register row, and the pending/completed archives (R6).
6. Hardening: STRIDE (in spec), sabotage arms as the mutation proxy, security-scanner in adversarial mode.

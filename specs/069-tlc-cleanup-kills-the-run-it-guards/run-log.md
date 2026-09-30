# Run log — 069-tlc-cleanup-kills-the-run-it-guards

One line per event. Failure memory for a spec resumed in a fresh session.
Append-only, deduped, capped. NOT pipeline input — read the tail, never the whole file.

- 2026-09-30T14:37Z · harness 14/14 macOS + Linux container, red 7/13 on old script; sabotage argv0-java 3 red, age-bound 2 red; BSD pkill skips ancestors so the 144 self-kill only reproduces on Linux or via a sibling shell; diagnosis said PreToolUse, wiring is PostToolUse

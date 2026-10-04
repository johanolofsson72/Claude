# Run log — 099-maintenance-script-fixes

One line per event. Failure memory for a spec resumed in a fresh session.
Append-only, deduped, capped. NOT pipeline input — read the tail, never the whole file.

- 2026-10-04T13:10Z · R1-R5 implemented: ratchet exit 77 skip, Carve accepted line, rules 30.9K->23,549 B + context-budget split/synced msg, archiver verbatim membership, TLC states ignored; touched suites green; full suite + 14 hand mutants running
- 2026-10-04T13:26Z · hand mutants 14/14 killed after 2 arms added (malformed line alone, a nested CLAUDE.md in the split fixture); the settings guard refuses a sed pattern naming the dot-claude dir even in a scratch copy

# Run log — 095-guard-fail-open-sweep

One line per event. Failure memory for a spec resumed in a fresh session.
Append-only, deduped, capped. NOT pipeline input — read the tail, never the whole file.

- 2026-10-03T07:41Z · specify · spec.md written
- 2026-10-03T08:25Z · R4 matcher edit (settings.json L61/L70 += |mcp__.*) confirmed twice by the developer but not on disk (mtime 2026-10-02 15:50); fixture test-hook-channels 095-R4 red until applied
- 2026-10-03T08:25Z · Threat model (security-scanner) adopted: merge-conflict rule, pull only from a configured remote, aliases, same-line ref movers, apply --numstat, MCP keys/joins/command strings, all GIT_* dropped, .template-sync stand-in, system-path reads, sed long-option prefixes, more exec keys
- 2026-10-03T08:26Z · specify · spec.md written
- 2026-10-03T08:47Z · Adversarial review (security-scanner, code-read only): 10 shapes fixed with fixtures (#1-#10 in the guard self-tests); nested-program check limited to shells/eval after it flagged a heredoc to cat
- 2026-10-03T09:15Z · allium:elicit · spec.allium written
- 2026-10-03T09:33Z · R4 applied by the developer (! python one-liner); test-hook-channels 50/50; suite otherwise 93/94 green before it

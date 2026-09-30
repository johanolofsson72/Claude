# Run log — 052-maintenance-runs-what-it-finds

One line per event. Failure memory for a spec resumed in a fresh session.
Append-only, deduped, capped. NOT pipeline input — read the tail, never the whole file.

- 2026-09-30T12:33Z · 052: maintenance suite 251/251, C88-C97 red on HEAD (21 fails) before fix; C98 exercised on this host; live pass surfaced 5 SIGPIPE assertions (fixed in 376d59d)

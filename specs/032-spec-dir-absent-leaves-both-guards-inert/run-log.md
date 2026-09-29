# Run log — 032-spec-dir-absent-leaves-both-guards-inert

One line per event. Failure memory for a spec resumed in a fresh session.
Append-only, deduped, capped. NOT pipeline input — read the tail, never the whole file.

- 2026-09-29T16:34Z · spec 032: filed mechanism (found:false passes) measured false — both guards deny it, at HEAD and at fundit d637ed2; 016a passed via dropped pre-046 deny + .html/.css outside SOURCE_EXTS; widened in 3 guards, 16 red arms green

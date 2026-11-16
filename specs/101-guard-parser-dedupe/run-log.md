# Run log — 101-guard-parser-dedupe

One line per event. Failure memory for a spec resumed in a fresh session.
Append-only, deduped, capped. NOT pipeline input — read the tail, never the whole file.

- 2026-11-16 · specify + interview (18 auto) + clarify written; R1-R4 implemented
- 2026-11-16 · R1 surfaced a shell_glob bug: `sed -- SCRIPT f` read SCRIPT as a file; fixed in sed_walk (old sensitive walker had it right)
- 2026-11-16 · run-mutation-gate.sh mutates bash only; Python lines measured by a hand pass of 11 mutants (scratchpad mut.py)
- 2026-11-16T15:44Z · specify · spec.md written
- 2026-11-16 · hand mutants 10/11 killed, M10 equivalent (marked); M4 (-f beside -e) killed by a new settings-edit case

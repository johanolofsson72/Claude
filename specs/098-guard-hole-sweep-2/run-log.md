# Run log — 098-guard-hole-sweep-2

One line per event. Failure memory for a spec resumed in a fresh session.
Append-only, deduped, capped. NOT pipeline input — read the tail, never the whole file.

- 2026-10-04T06:09Z · specify: spec.md written; F139 and F155 reproduced 2026-10-04 (repro payloads must live in a file: the live settings guard refuses a command line that names the settings file next to bash)
- 2026-10-04T06:15Z · specify · spec.md written
- 2026-10-04T06:19Z · interview Q1-21 + O1-O4 (all recommended); acceptance confirmed 231c3c8c113a; allium:elicit written; threat model agent running
- 2026-10-04T06:22Z · specify · spec.md written
- 2026-10-04T06:51Z · R1 R3 R4 R6 + threat #6 (git-dir chmod/mv, trust-anchor bash-gitmeta) built; tests green. INCIDENT: a backtick in trust-anchor's python heredoc broke the live hook (exit 2 on every call); developer repaired with ! perl. Never put a backtick in that program; bash -n after every guard edit.
- 2026-10-04T07:30Z · R2 R5 R7 R8 built; all 9 owning self-tests green 2026-10-04 (fresh session); phase 3 (T030-T034) next
- 2026-10-04T08:31Z · allium:elicit · spec.allium written
- 2026-10-04T08:31Z · specify · spec.md written
- 2026-10-04T08:31Z · review fixed (R7 dup/spill/unplain, R4 rc, R6 sha+sid, R1 gitfile+notebook) 13d569e; F175-F178 recorded; TLA ReadFlow v2 clean 1080 states (v1 control fails), GitUnsure clean 72; 6 Allium drifts -> update spec (developer); hand mutants + suite running

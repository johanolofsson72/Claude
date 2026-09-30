# Plan — 069

1. Tests first: `scripts/test-tlc-cleanup.sh` with fake TLC processes (`exec -a "java … tlc2.TLC"
   sleep`), each scoped by a unique `--only` token so a test never touches a real run. AC1–AC9
   against the current script, which fails (red).
2. Script: `ps -A -o pid=,etime=,args=`, awk filter on argv[0] basename + pattern + age, marked
   regions `argv0-java` and `age-bound` for the sabotage arms. TERM, one-second wait, KILL.
3. Skill: the `/tla` cleanup paragraph says what the script now kills and what `--all` is for; the
   bracketed fallback stays, flagged as "kills every run".
4. Verify: harness + sabotage, `/bin/bash -n` (bash 3.2), test-template-autosync-eol (it probes
   this script), shellcheck if present.

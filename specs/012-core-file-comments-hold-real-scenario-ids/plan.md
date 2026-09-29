# Plan — 012 core-file comments hold real scenario ids

1. Scrub the nine CORE production scripts. Each `Covers:` line points at its self-test, and each
   worked example uses an `SC-NNN` placeholder. Only comment lines change.
2. `test-validate-scenario-traceability.sh`: add a case that copies every CORE production script
   into a fixture root and runs the real gate with `--roots` against a one-row map. Any reference
   the gate reports is a FAIL naming the file (found with a grep for the reported id). A CORE list
   that is empty or unreadable is also a FAIL.
3. Sabotage arm: plant `# SC-4242` in one copied file. The case must go red and name that file.
4. Verify: A1 grep, the self-test, the suites of the touched scripts, `bash -n`, `py_compile`, and a
   diff audit showing that only comment lines changed.
5. Hardened: STRIDE table in spec.md, adversarial review (security-scanner plus a reviewer), sabotage
   as the mutation gate, and the runtime measured.
6. Register: tick, move the row into INDEX.completed.md, and add a run-log line.

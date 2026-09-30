# Run log — 068-checkpoint-cadence-counts-checkpoints

One line per event. Failure memory for a spec resumed in a fresh session.
Append-only, deduped, capped. NOT pipeline input — read the tail, never the whole file.

- 2026-09-30T14:22Z · harness 12/12 (4 red on HEAD readers); sabotage 3 arms red; fixed pre-existing SIGPIPE assertion in test-next-register-id.sh:154 (from 066); template register itself is 28 feature specs past H1 — the modulo hid it

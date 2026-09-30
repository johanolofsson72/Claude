# Plan — 067

1. Tests first: case49a/b (unreadable dir, unreadable file), case49c (file counts), case50 (pruned
   report dirs). Run on HEAD, see them red.
2. Gate: a marked `walk-error-guard` region before `zero-refs-guard`; add the three prune names.
3. Sabotage arms: guard removed → case49 red; prune names reverted → case50 red.
4. Verify: harness green, `/bin/bash -n`, the repro script.

# Plan — 053

1. Tests first: sweep arms in `scripts/test-stryker-guard.sh` (AC1-AC12) and one `--full` arm in
   `scripts/test-project-maintenance.sh` (AC3 refusal). Run, see them red on HEAD.
2. `stryker_guard.py`: `stryker-js` process kind (node running StrykerJS), used only by the sweep;
   command-side StrykerJS recognition; `sweep` subcommand; `command` mode sweeps after an allow and
   returns `allow<TAB>note`, or denies on `backup`.
3. `stryker-guard-hook.sh`: pass `allow<TAB>note` through as `additionalContext`.
4. `project-maintenance.sh` §5: sweep before the mutation command; `backup` → NOT RUN, not stamped.
5. Verify: both test files, `/bin/bash -n` (3.2), a live pass on this repo.

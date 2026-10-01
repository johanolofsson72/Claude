#!/bin/bash
# What a self-test may not inherit (spec 084, F016 F020). SOURCE this file as the first statement of
# every scripts/test-*.sh, before any cd, pwd or path resolution:
#
#   . "$(dirname -- "$0")/self-test-env.sh" || exit 1
#
# `dirname` does not cd, so CDPATH cannot steer that line; the cd that follows it can no longer be
# steered either. scripts/test-self-test-prologue.sh fails any test that skips this or does it late.
#
# WHY. A self-test runs wherever the developer, the suite runner or a hook happens to start it, and
# each of those leaves variables behind that pick a test's target for it:
#
#   CDPATH              a relative `cd "$(dirname "$0")/.."` lands in ANOTHER clone first (measured in
#                       011: a decoy on CDPATH turned 8 suites red and was itself never touched).
#   CLAUDE_PROJECT_DIR  the harness exports it, and ~24 scripts resolve their project from it before
#                       $PWD. That is the 2026-08-30 incident: a self-test synced the real repository.
#   GIT_*               a git hook exports the location ones, and each beats `git -C`.
#   GIT_CONFIG_*        config given on a command line further up (insteadOf, hooksPath), or another
#                       global/system config file; GIT_SSH_COMMAND, GIT_EXEC_PATH, GIT_NAMESPACE too.
#   DRIVE_SYNC_* / DRIVE_HOOK_SCRIPT
#                       drive-sync.sh has no default script on purpose; an ambient one would be it.
#   CLAUDE_TEMPLATE_* / TEMPLATE_AUTOSYNC_*
#                       which template the sync reads, whether it may be dirty, the sandbox, and
#                       whether the hook runs at all. CLAUDE_TEMPLATE_AUTOSYNC=0 on a second-lane
#                       machine would make every hook arm pass without running anything.
#   BASH_ENV            read by every non-interactive bash the test starts. The test's own shell has
#                       already read it; unsetting it here protects the children only.
#
# A test that needs one of these sets it explicitly after this line, per call where it can.
# Not here, deliberately: HOME (fixtures commit with the developer's identity from ~/.gitconfig) and
# PATH (tests shim it on purpose). Both are residuals named in spec 084.
#
# CORE: ships with every test that sources it. Scenario ids deliberately absent (row 012).

unset CDPATH BASH_ENV CLAUDE_PROJECT_DIR \
  GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CEILING_DIRECTORIES \
  GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_NOSYSTEM \
  GIT_SSH_COMMAND GIT_EXEC_PATH GIT_NAMESPACE \
  DRIVE_SYNC_SCRIPT DRIVE_HOOK_SCRIPT DRIVE_SYNC_CWD DRIVE_SYNC_PATH DRIVE_SYNC_TIMEOUT \
  CLAUDE_TEMPLATE_DIR CLAUDE_TEMPLATE_PIN CLAUDE_TEMPLATE_ALLOW_DIRTY CLAUDE_TEMPLATE_SYNC_SANDBOX \
  CLAUDE_TEMPLATE_AUTOSYNC CLAUDE_TEMPLATE_AUTOSYNC_ALWAYS \
  TEMPLATE_AUTOSYNC_INTERVAL TEMPLATE_AUTOSYNC_LIMIT TEMPLATE_AUTOSYNC_NAME_LIMIT TEMPLATE_AUTOSYNC_TIMEOUT_BACKOFF

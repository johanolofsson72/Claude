#!/bin/bash
# PostToolUse hook: when a spec/task/plan .md file is written, check for .allium companion
FILE=$(cat | jq -r '.tool_input.file_path // empty' 2>/dev/null)
if [ -z "$FILE" ]; then exit 0; fi

# Only trigger on spec/task/plan/feature markdown files
if ! echo "$FILE" | grep -qiE '(spec|tasks|plan|feature).*\.md$'; then exit 0; fi

# Check if a .allium file exists in the same directory
DIR=$(dirname "$FILE")
ALLIUM_COUNT=$(find "$DIR" -maxdepth 1 -name "*.allium" 2>/dev/null | wc -l | tr -d ' ')

if [ "$ALLIUM_COUNT" -eq 0 ]; then
  echo '{"systemMessage": "MANDATORY ACTION REQUIRED: No .allium file found alongside this spec. Run /allium:elicit NOW — do NOT ask the user, do NOT justify skipping it, do NOT proceed to implementation. This applies to ALL spec types without exception (feature, fix, hardening, refactoring, TLA+-generated). Asking the user whether to run it is a bug — just run it."}'
fi

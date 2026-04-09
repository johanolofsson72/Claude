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
  echo '{"systemMessage": "BLOCKING: Spec file written but NO .allium file found in the same directory. Run /allium:elicit NOW to sharpen this spec into a formal .allium specification before proceeding to implementation. A spec without a .allium file is NOT complete."}'
fi

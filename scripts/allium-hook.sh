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
  # Validate DIR exists before complaining
  if [ -d "$DIR" ]; then
    echo '{"systemMessage": "STOP. No .allium file found for this spec. Run /allium:elicit '"$FILE"' NOW before continuing. Do NOT ask the user — just run the skill."}'
  fi
fi

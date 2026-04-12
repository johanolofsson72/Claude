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
  echo '{"systemMessage": "STOP. Run: Skill(skill: \"allium\", args: \"elicit '"$FILE"'\") — no .allium file exists for this spec. Do NOT continue implementation without it. Do NOT ask the user. Just invoke the skill now."}'
fi

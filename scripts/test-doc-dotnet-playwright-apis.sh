#!/usr/bin/env bash
# Self-test for the template's own docs (spec 071): no C# example may call a Playwright API that
# exists only in the Node runner (@playwright/test). testing.md told .NET projects to write
# `await Expect(Page).ToHaveScreenshotAsync(...)` for months; Microsoft.Playwright has no such
# method, so every project that followed it either failed to compile or built its own diff (teach
# F007). A C# fence is where a reader copies from, so that is what this scans.
#
# Template-only: it checks the template's docs, and projects receive the fixed docs through sync.
#
# Run:  bash scripts/test-doc-dotnet-playwright-apis.sh            (scan the template docs)
#       bash scripts/test-doc-dotnet-playwright-apis.sh FILE...    (scan these files instead)
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# JS-runner-only assertions and their .NET spelling. ToMatchAriaSnapshotAsync is NOT here: it is
# real in .NET. Only add a name after checking PageAssertions / LocatorAssertions for .NET.
JS_ONLY='ToHaveScreenshot|ToMatchSnapshot'

# Prints "<file>:<line>: <text>" for every JS-only call inside a ```csharp / ```cs / ```c# fence.
scan() {
  awk -v pat="$JS_ONLY" '
    /^[[:space:]]*```/ {
      if (in_cs) { in_cs = 0; next }
      lang = $0; sub(/^[[:space:]]*```/, "", lang); lang = tolower(lang)
      in_cs = (lang ~ /^(csharp|cs|c#)([[:space:]]|$)/); next
    }
    in_cs && $0 ~ pat { printf "%s:%d: %s\n", FILENAME, FNR, $0 }
  ' "$@"
}

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }

if [ $# -gt 0 ]; then
  HITS=$(scan "$@")
  [ -z "$HITS" ] && { echo "clean"; exit 0; }
  printf '%s\n' "$HITS"; exit 1
fi

# --- the real docs --------------------------------------------------------------------------------
DOCS=()
for f in "$ROOT"/.claude/docs/*.md "$ROOT"/.claude/rules/*.md "$ROOT"/.claude/skills/*/SKILL.md "$ROOT"/CLAUDE.md; do
  [ -f "$f" ] && DOCS+=("$f")
done
[ ${#DOCS[@]} -gt 0 ] || { echo "ERROR: no docs found under $ROOT — nothing was scanned." >&2; exit 2; }

HITS=$(scan "${DOCS[@]}")
if [ -z "$HITS" ]; then ok "no JS-only Playwright assertion in a C# fence (${#DOCS[@]} docs)"
else bad "JS-only Playwright assertion in a C# fence" "$HITS"; fi

T="$ROOT/.claude/docs/testing.md"
CS=$(awk '/^```csharp/{c=1;next} /^```/{c=0} c' "$T")
case "$CS" in *ScreenshotAsync*) ok "testing.md's .NET visual-regression example takes the picture with ScreenshotAsync" ;;
  *) bad "testing.md has no C# ScreenshotAsync example" ;; esac
case "$CS" in *CalcDiff*) ok "testing.md's .NET example diffs the pixels" ;;
  *) bad "testing.md's .NET example never compares anything" ;; esac

# --- the scanner bites (sabotage arms) ------------------------------------------------------------
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
printf '```csharp\nawait Expect(Page).ToHaveScreenshotAsync("a.png");\n```\n' > "$TMP/old.md"
case "$(scan "$TMP/old.md")" in *old.md:2:*) ok "sabotage: the pre-071 snippet is caught" ;;
  *) bad "sabotage: the pre-071 snippet was NOT caught" ;; esac

printf '```ts\nawait expect(page).toHaveScreenshot("a.png");\n```\n' > "$TMP/node.md"
[ -z "$(scan "$TMP/node.md")" ] && ok "a Node fence using toHaveScreenshot is allowed" \
  || bad "a Node fence was flagged"

printf '```cs\nawait Expect(Page).ToMatchAriaSnapshotAsync("- heading");\n```\n' > "$TMP/aria.md"
[ -z "$(scan "$TMP/aria.md")" ] && ok "ToMatchAriaSnapshotAsync (real in .NET) is allowed" \
  || bad "ToMatchAriaSnapshotAsync was flagged"

printf '```csharp\nvar x = 1;\n```\nToHaveScreenshotAsync in prose\n```c#\nExpect(Page).ToHaveScreenshotAsync();\n```\n' > "$TMP/mix.md"
case "$(scan "$TMP/mix.md")" in *mix.md:6:*) ok "fence state resets: prose is ignored, a later c# fence is caught" ;;
  *) bad "fence tracking wrong on mixed file" "$(scan "$TMP/mix.md")" ;; esac

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

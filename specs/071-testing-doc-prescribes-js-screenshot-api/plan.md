# Plan — 071

1. Verify the claim against the .NET API docs; read rocky's VisualBaseline for measured pitfalls.
2. Rewrite testing.md § Visual regression: Node block (TS), .NET block (ScreenshotAsync + SkiaSharpCompare), bullets for alternatives, animations, per-OS baselines, missing-baseline failure. Add Width to ScreenTest.
3. Guard: scripts/test-doc-dotnet-playwright-apis.sh, red against HEAD's testing.md, green after; sabotage + false-positive arms. List it in TEMPLATE_ONLY_SCRIPTS.
4. Verify: scratch NUnit run of the exact snippet (AC2), guard, sigpipe gate, autosync --unlisted tests.

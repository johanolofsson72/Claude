---
paths:
  - "**/*.cs"
  - "**/*.csproj"
---

# .NET code rules

- PascalCase for public members, camelCase for local variables.
- Prefix private fields with `_` (e.g., `_logger`).
- Use `var` only when the type is obvious from the right side.
- One class per file. Filename matches class name.
- File-scoped namespaces (`namespace X;`).
- Primary constructors for services with dependency injection.
- Use `record` for immutable data types.
- Never use `#region` — structure with classes and methods instead.
- Keep methods under 30 lines — extract when needed.
- Async/await: avoid async void, propagate CancellationToken.
- EF Core: avoid N+1 — use Include/ThenInclude, AsNoTracking() for reads.
- Keep `Program.cs` minimal — register services and middleware via extension methods (e.g., `AddApplicationServices()`, `UseApplicationMiddleware()`). No business logic in `Program.cs`.
- ALWAYS run `pkill -f dcpctrl || true` and `pkill -f "/absolute/path/to/src/<subproject>[.]<Suffix>" || true` (one command per subproject) BEFORE `dotnet build`, `dotnet run`, or `dotnet test`. ALWAYS use full absolute paths — relative paths like `src/<subproject>` are FORBIDDEN because they can match and kill processes with the same name in other projects on the machine. Identify subprojects from the `src/` structure and `launchSettings.json` — NEVER kill all dotnet processes globally.

  **The bracketed literal is not decoration — without it the command kills the shell running it.**
  `pkill -f` matches against a process's whole command line, and the shell executing this rule has
  the path on ITS command line, so a plain `pkill -f "/abs/path/src/X.Api"` matches itself. Measured
  2026-09-25: the probe printed its line *before* the `pkill` and then died with exit 144, so the
  `dotnet build` the rule exists to protect never ran at all — and it fails in the direction that
  looks like a build error. Writing one character class (`AgentCrm[.]Api`) changes nothing about what
  the pattern matches in a real process — a regex `[.]` is a literal dot — but the pattern no longer
  matches its own text. Same probe, bracketed: exit 0, and the line after it printed.

## The compiler is the ground truth, the editor is not

`dotnet build` decides whether the code compiles. An editor's inline diagnostics (the LSP / OmniSharp
index) are a cache, and a cache goes stale exactly when the tree moves most — after a merge, a branch
switch, a generated-file rebuild. Measured on agentcrm 2026-09-07: **30 confident diagnostics**
(`FeedSource has no MlsCosta`, `RateLimitPolicies has no FeedRun`, `ParseResult not found`) against a
tree where `dotnet build` returned **0 warnings, 0 errors in 12 s**.

So: before chasing an error the editor reports, run the build. A session that trusts the index spends
its afternoon repairing breakage that does not exist, and the repairs are the only real damage. The
same holds in reverse — a clean index is not evidence of anything until the build agrees.

## Output verbosity (token discipline)

Default `dotnet` output is chatty — every test name, every restore step, every assembly load. The model pays for all of it. Use quiet flags by default and only escalate when debugging:

- `dotnet test --logger "console;verbosity=minimal"` — prints only failed tests + summary
- `dotnet test --logger "console;verbosity=normal"` — escalate when a specific test needs investigation
- `dotnet build --verbosity quiet` (or `-v q`) — only warnings and errors
- `dotnet restore --verbosity quiet`
- For Playwright via `dotnet test`: combine with `--logger` above; Playwright traces are independent and stay verbose unless `PWDEBUG=0` and `--reporter=line` are passed to the underlying runner.

When a test fails and the minimal output doesn't show enough context, re-run only the failing test with normal verbosity: `dotnet test --filter "FullyQualifiedName~ClassName.TestName" --logger "console;verbosity=normal"`. Do not rerun the entire suite at higher verbosity to investigate one failure.

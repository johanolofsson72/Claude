---
globs: "**/*.cs,**/*.csproj"
---

# .NET-kodregler

- PascalCase för publika medlemmar, camelCase för lokala variabler.
- Prefix privata fält med `_` (t.ex. `_logger`).
- Använd `var` bara när typen är uppenbar från höger sida.
- En klass per fil. Filnamn matchar klassnamn.
- File-scoped namespaces (`namespace X;`).
- Primary constructors för services med dependency injection.
- Använd `record` för immutabla datatyper.
- Använd aldrig `#region` — strukturera med klasser och metoder istället.
- Håll metoder under 30 rader — bryt ut vid behov.
- Async/await: undvik async void, propagera CancellationToken.
- EF Core: undvik N+1 — använd Include/ThenInclude, AsNoTracking() för läsning.

---
paths:
  - "**/*.cs"
  - "**/*.csproj"
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
- Kör ALLTID `pkill -f dcpctrl || true` och `pkill -f "/absolut/sökväg/till/src/<delprojekt>" || true` (ett kommando per delprojekt) INNAN `dotnet build`, `dotnet run` eller `dotnet test`. Använd ALLTID fullständig absolut sökväg — relativa sökvägar som `src/<delprojekt>` är FÖRBJUDNA eftersom de kan matcha och döda processer med samma namn i andra projekt på maskinen. Identifiera delprojekten från `src/`-strukturen och `launchSettings.json` — döda ALDRIG alla dotnet-processer globalt.

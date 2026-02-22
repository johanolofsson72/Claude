# Kodstil och konventioner

## C# / .NET

- Följ officiella [C# Coding Conventions](https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/coding-style/coding-conventions).
- PascalCase för publika medlemmar, metoder och klasser.
- camelCase för lokala variabler och privata fält.
- Prefix privata fält med `_` (t.ex. `_logger`).
- Använd `var` när typen är uppenbar från höger sida.
- En klass per fil. Filnamn matchar klassnamn.
- Använd `nullable reference types` (enable i .csproj).
- Föredra `record` för immutabla datatyper.
- File-scoped namespaces (`namespace X;` istället för `namespace X { }`).
- Primary constructors där det passar (t.ex. services med dependency injection).
- Expression-bodied members för enkla implementationer.
- Strukturera med klasser och metoder — använd aldrig `#region`.

## JavaScript / jQuery

- Använd `const` och `let` — aldrig `var`.
- Camelcase för variabler och funktioner.
- Föredra moderna DOM-API:er när jQuery inte redan används i filen.
- Strikt likhet (`===`) alltid.

## HTML / CSS

- Semantisk HTML5.
- BEM-namngivning för CSS-klasser när det passar.
- Mobile-first responsiv design.
- Använd CSS-klasser — aldrig inline `style="..."`.

## WordPress

- Följ [WordPress Coding Standards](https://developer.wordpress.org/coding-standards/).
- Använd child themes och hooks — modifiera aldrig core-filer.

## Allmänna principer

- Kod ska vara läsbar utan kommentarer — bra namngivning räcker oftast.
- Lägg bara till kommentarer där logiken inte är uppenbar.
- Håll metoder korta och fokuserade — en metod gör en sak.
- Föredra explicit framför implicit.
- Felmeddelanden ska vara tydliga och handlingsbara.
- Håll UI tunt — all business-logik i services.

## Filstruktur

- Separera concerns: Models, Views, Controllers, Services.
- Delade komponenter i `Shared/` eller `Components/`.
- I .NET-projekt: `wwwroot/` för webbspecifika filer.
- Statiska assets alltid i `assets/` i projektroten.

## Databas (SQLite)

- Entity Framework Core med SQLite-provider.
- Code-first med migrations.
- Inkludera inte `.db`-filen i git.
- Seed-data via migrations eller separat seed-metod.

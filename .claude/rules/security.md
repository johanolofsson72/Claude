---
globs: "**/*.cs,**/*.cshtml,**/*.razor"
---

# Säkerhetsregler för C#-kod

- Använd ALLTID parametriserade queries — aldrig string concatenation för SQL.
- Validera all användarinput vid API-gränser.
- Exponera aldrig stack traces i produktion — använd ProblemDetails.
- Kontrollera att alla API-endpoints har [Authorize] eller explicit [AllowAnonymous].
- Lagra aldrig hemligheter i kod — använd appsettings.json (lokalt) eller miljövariabler (produktion).

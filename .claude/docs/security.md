# Säkerhet

## Grundregler

- Använd ALLTID parametriserade queries — aldrig string concatenation för SQL.
- Sanera all användarinput (XSS-skydd).
- Konfigurera HTTPS, CSRF-skydd och CORS korrekt.
- Lagra hemligheter i `appsettings.json` (lokalt) eller miljövariabler (produktion) — aldrig i kod.
- Committa aldrig `.env`, `appsettings.Development.json` eller liknande.
- Alla API-endpoints kräver autentisering om inget annat anges.
- Använd aldrig `eval()` eller `extract()` — varken i PHP eller JavaScript.

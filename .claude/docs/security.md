# Säkerhet

## Grundregler

- Parametriserade queries alltid — aldrig string concatenation för SQL.
- Sanera all användarinput (XSS-skydd).
- HTTPS, CSRF-skydd, CORS-konfiguration.
- Hemligheter i `appsettings.json` (lokalt) / miljövariabler (produktion) — **aldrig i kod**.
- Committa inte `.env`, `appsettings.Development.json` eller liknande.
- Alla API-endpoints kräver autentisering om inget annat anges.

## Förbjudna säkerhetsrelaterade implementationer

- **String concatenation i SQL** — använd parametriserade queries.
- **Hemligheter i kod** — inga API-nycklar, lösenord eller tokens.
- **`eval()` eller `extract()`** — aldrig, varken i PHP eller JavaScript.
- **Inline styles** — använd CSS-filer eller CSS-klasser, aldrig `style="..."` i HTML.

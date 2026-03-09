# Säkerhet

## Grundregler

- Använd ALLTID parametriserade queries — aldrig string concatenation för SQL.
- Sanera all användarinput (XSS-skydd).
- Konfigurera HTTPS, CSRF-skydd och CORS korrekt.
- Lagra hemligheter i `appsettings.json` (lokalt) eller miljövariabler (produktion) — aldrig i kod.
- Committa aldrig `.env`, `appsettings.Development.json` eller liknande.
- Alla API-endpoints kräver autentisering om inget annat anges.
- Använd aldrig `eval()` eller `extract()` — varken i PHP eller JavaScript.

## Claude Code permissions.deny — känd bugg

`permissions.deny` i `.claude/settings.json` har kända buggar (GitHub issues #6699, #6631, #27040) där deny-regler inte alltid upprätthålls. Vår settings.json innehåller därför en **PreToolUse backup-hook** som blockerar åtkomst till känsliga filer (`.ssh`, `.aws`, `.env`, credentials) via `hookSpecificOutput.permissionDecision: "deny"`. Denna hook är tillförlitlig — till skillnad från `permissions.deny`.

Om du lägger till nya deny-regler för säkerhetskritiska filer, skapa alltid en matchande PreToolUse-hook som backup.

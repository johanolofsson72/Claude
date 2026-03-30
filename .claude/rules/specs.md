---
paths:
  - "**/spec*.md"
  - "**/tasks*.md"
  - "**/plan*.md"
  - "**/feature*.md"
  - "**/.specify/**"
  - "**/specs/**"
---

# Spec- och task-regler (destruktiva browsertester)

## INNAN du skriver en spec eller task-fil som involverar UI

1. **Läs `.claude/docs/testing.md`** — specifikt sektionen "Destruktiva browsertester (OBLIGATORISKT)".
2. **Läs `.claude/docs/spec-testing-checklist.md`** — checklistan för vilka attackkategorier som MÅSTE finnas.

## Krav på varje spec/task-fil med UI-komponenter

Varje spec som involverar UI **MÅSTE** inkludera en dedikerad fas/sektion för destruktiva browsertester med:

- **Minst 8 destruktiva testscenarier** — dessa ska aktivt försöka knäcka applikationen
- **Alla 6 attackkategorier** ska vara representerade (om relevanta):
  1. Ogiltig input (skräp, XSS, SQL injection, emoji, extremlängd)
  2. Fel ordning (dubbelklick, browser back, URL-hopp, refresh mitt i flöde)
  3. Hoppa över steg (direkt URL, API utan UI, DOM-manipulation)
  4. Gränsvärden (maxlängd, tomma listor, ogiltiga datum)
  5. Timing/race conditions (klick innan laddning, snabb dubbelsubmit)
  6. Tillgänglighet (tab-ordning, Enter, Escape)

- Om features involverar **offline/sync**: lägg till ytterligare destruktiva scenarion:
  - Browser stängs mitt i autosave/sync
  - Nätverket dör mitt i operation
  - Conflict mellan sessioner/enheter
  - Token-förfall under offline
  - Retry efter error-state

## Validering

Innan en spec/task-fil anses komplett, kontrollera:

- [ ] Finns en explicit "Destructive Browser Tests"-fas/sektion?
- [ ] Finns minst 8 destruktiva testscenarier?
- [ ] Täcker scenarierna alla 6 attackkategorier?
- [ ] Om offline/sync: finns ytterligare edge case-tester?
- [ ] Har varje testscenario ett tydligt task-ID och beskrivning?

Om någon av dessa saknas — **specen är INTE komplett**. Lägg till innan du går vidare.

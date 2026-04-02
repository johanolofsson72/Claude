---
paths:
  - "**/spec*.md"
  - "**/tasks*.md"
  - "**/plan*.md"
  - "**/feature*.md"
  - "**/.specify/**"
  - "**/specs/**"
---

# Spec and task rules (destructive browser tests)

## BEFORE writing a spec or task file involving UI

1. **Read `.claude/docs/testing.md`** — specifically the "Destructive browser tests (MANDATORY)" section.
2. **Read `.claude/docs/spec-testing-checklist.md`** — the checklist for which attack categories MUST be present.

## Requirements for every spec/task file with UI components

Every spec involving UI **MUST** include a dedicated phase/section for destructive browser tests with:

- **At least 8 destructive test scenarios** — these should actively try to break the application
- **All 6 attack categories** should be represented (if relevant):
  1. Invalid input (garbage, XSS, SQL injection, emoji, extreme length)
  2. Wrong order (double-click, browser back, URL jumping, refresh mid-flow)
  3. Skip steps (direct URL, API without UI, DOM manipulation)
  4. Boundary values (max length, empty lists, invalid dates)
  5. Timing/race conditions (click before load, rapid double submit)
  6. Accessibility (tab order, Enter, Escape)

- If features involve **offline/sync**: add additional destructive scenarios:
  - Browser closes mid-autosave/sync
  - Network drops mid-operation
  - Conflict between sessions/devices
  - Token expiry during offline
  - Retry after error state

## Validation

Before a spec/task file is considered complete, verify:

- [ ] Is there an explicit "Destructive Browser Tests" phase/section?
- [ ] Are there at least 8 destructive test scenarios?
- [ ] Do the scenarios cover all 6 attack categories?
- [ ] If offline/sync: are there additional edge case tests?
- [ ] Does every test scenario have a clear task ID and description?

If any of these are missing — **the spec is NOT complete**. Add them before proceeding.

---
paths:
  - "**/spec*.md"
  - "**/tasks*.md"
  - "**/plan*.md"
  - "**/feature*.md"
  - "**/.specify/**"
  - "**/specs/**"
---

# Spec and task rules (Allium + destructive browser tests + TLA+)

## Spec creation flow (MANDATORY — every step is automatic)

When a spec is being written (speckit, specify, or manual), follow this exact sequence:

### Phase A: Write the spec
1. **Read `.claude/docs/testing.md`** — the "Destructive browser tests (MANDATORY)" section.
2. **Read `.claude/docs/spec-testing-checklist.md`** — attack categories checklist.
3. Write the spec with destructive browser tests included.

### Phase B: Sharpen with Allium (BLOCKING — do not skip)
4. **Run `/allium:elicit`** on the spec to produce a formal `.allium` specification.
   - Allium refuses vague requirements and forces precision on entities, rules, and triggers.
   - The `.allium` file MUST be saved alongside the spec (same directory).
   - This creates the baseline for drift detection after implementation.
5. **A spec without a corresponding `.allium` file is NOT complete.** Do not proceed to implementation.

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
- [ ] **Has `/allium:elicit` been run and a `.allium` file saved alongside the spec?**

If any of these are missing — **the spec is NOT complete**. Do not proceed to implementation.

## Post-implementation: Drift detection + formal verification

After implementation is complete AND browser tests are written:

1. **Run `/tla`** — this automatically:
   - Runs `/allium:distill` on the implemented code to extract what was actually built
   - Compares distilled spec against the `.allium` from pre-implementation (drift detection)
   - Extracts TLA+ invariants and models the state machine
   - Cross-references invariants with browser tests for coverage gaps
2. Any **spec drift** or **TLA+ gaps** MUST be addressed before the feature is considered done
3. This step is auto-triggered after browser tests are written — no manual trigger needed

### The full pipeline

```
Spec (markdown) → /allium:elicit → .allium spec → Implementation →
Browser tests (destructive) → /tla (distill + drift + invariants) → Done
```

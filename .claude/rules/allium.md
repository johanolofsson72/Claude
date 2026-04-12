---
paths:
  - "**/*.allium"
  - "**/allium/**"
  - "**/spec*.md"
  - "**/tasks*.md"
  - "**/plan*.md"
  - "**/feature*.md"
---

# Allium specification rules

Allium is the preferred specification language for this project. It sits between natural language and TLA+ — more formal than markdown specs, more readable than formal methods.

## The pipeline

```
1. Spec written (markdown)           → what the developer wants
2. /allium:elicit                    → sharpens into .allium (refuses vague requirements)
3. Implementation                    → code written
4. Destructive browser tests         → 8+ scenarios, 6 attack categories
5. /tla (runs /allium:distill first) → drift detection + formal verification
```

## When writing specs (AUTOMATIC — not optional, never ask)

IMMEDIATELY after a spec is written, run `/allium:elicit` to produce a formal `.allium` specification. This is enforced by a PostToolUse hook that checks for `.allium` files when spec files are saved. Do NOT proceed to implementation without it.

The `.allium` file MUST be saved in the same directory as the spec file.

**NO EXCEPTIONS.** Every spec type gets an `.allium` file — feature specs, fix specs, hardening specs, refactoring specs, TLA+-generated specs, security specs. Even if the spec was generated from TLA+ findings. Even if there are no new features. Even if it seems unnecessary. Do NOT ask the user whether to run `/allium:elicit` — just run it automatically. Asking is treated as a bug.

This step:
- Forces precision on entities, rules, and invariants
- Refuses vague or ambiguous requirements
- Creates the baseline that `/tla` will compare against after implementation

## When reviewing implementations

After browser tests are written, `/tla` automatically runs `/allium:distill` to extract what was actually built and compares it against the pre-implementation `.allium`. Differences are **spec drift**.

## Allium commands

| Command | When | Purpose |
|---|---|---|
| `/allium:elicit` | Before implementation | Build formal spec through conversation |
| `/allium:distill` | After implementation | Extract spec from code (used by `/tla`) |
| `/allium` | Any time | Examine project, offer elicit or distill |

## Validation

If the Allium CLI is installed (`allium` command available), `.allium` files are validated automatically after every write or edit. Install via:
- Homebrew: `brew tap juxt/allium && brew install allium`
- Cargo: `cargo install allium-cli`

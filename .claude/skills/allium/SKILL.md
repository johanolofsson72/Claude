---
name: allium
description: Allium specification language — elicit formal specs from markdown, distill specs from code. Sub-commands elicit and distill. Trigger on /allium, allium, elicit, distill, formal spec.
allowed-tools: Read, Grep, Glob, Bash, Write, Edit
user-invocable: true
argument-hint: "[elicit|distill] [spec-file-or-feature-path]"
---

# Allium Specification Skill

You write and manage `.allium` specification files — a formal spec language between natural language and TLA+.

## Sub-commands

| Command | When | What it does |
|---|---|---|
| `/allium:elicit` | Before implementation | Read a markdown spec, produce a `.allium` file |
| `/allium:distill` | After implementation | Read implemented code, extract a `.allium` from what was actually built |
| `/allium` (no sub-command) | Any time | Examine context, decide whether to elicit or distill |

Use `$ARGUMENTS` to determine the sub-command and target. If no argument, look at recent git changes.

## /allium:elicit — Spec to Allium

**Input:** A markdown spec file (spec*.md, tasks*.md, plan*.md, feature*.md)
**Output:** A `.allium` file saved in the same directory as the spec

### Process

1. **Find the spec file** — use `$ARGUMENTS` or find the most recently written spec in the project
2. **Read the spec thoroughly** — understand every requirement, constraint, edge case
3. **Extract entities** — every noun that has state, fields, or identity
4. **Extract rules (invariants)** — conditions that must ALWAYS hold, constraints, uniqueness
5. **Extract triggers** — state transitions, user actions, system events
6. **Write the `.allium` file** in the same directory as the spec
7. **Validate** — run `allium check <file>` if the CLI is installed

### Allium language syntax

```allium
-- Allium Specification: [Title]
-- [Description / scope]

-- ============================================================
-- ENTITIES
-- ============================================================

entity EntityName {
  id: UUID
  name: string                      -- built-in types: UUID, string, Integer, datetime, date, boolean, json
  status: Active | Inactive         -- union types (enums)
  email: string?                    -- optional field (nullable)
  parentId: UUID → ParentEntity.id  -- foreign key reference
  -- UNIQUE(field1, field2)          -- uniqueness constraint
  -- INV: description of invariant   -- inline invariant documentation
}

-- ============================================================
-- RULES (INVARIANTS — must ALWAYS hold)
-- ============================================================

rule RuleName {
  -- Human-readable description
  forall entity in EntityType:
    entity.field == expectedValue

  -- Conditional invariant
  forall x in Type:
    (condition) => consequence

  -- Uniqueness
  forall a, b in Type:
    (a.key1 == b.key1 AND a.key2 == b.key2) => a.id == b.id

  -- Negation
  NOT exists entity in Type WHERE badCondition

  -- Post-condition (after a trigger)
  after TriggerName(param):
    entity.field == newValue
}

-- ============================================================
-- TRIGGERS (state transitions)
-- ============================================================

trigger OnEventName(param1, param2) {
  REQUIRE: precondition that must be true
  action: what happens
  IF condition:
    action: conditional action
  PRESERVE: data that must survive the transition
  RETURNS: ResultType
}
```

### Quality requirements for elicitation

The `.allium` file must be **more precise** than the markdown spec. This means:

- **Refuse vagueness.** If the spec says "validate input" — specify WHAT validation, WHAT input, WHAT happens on failure.
- **Name every constraint.** If there's a uniqueness requirement, express it as a rule with `forall`.
- **Explicit state machines.** If something has a status field, enumerate ALL valid transitions.
- **No hand-waving.** "Handle errors appropriately" is not an Allium rule. "After PaymentFails: order.status TRANSITIONS TO Failed AND user receives notification" is.

If the spec is too vague to formalize, add `-- AMBIGUITY:` comments in the `.allium` file noting what needs clarification. But still write the best possible spec — don't skip it.

### Hardening / fix / refactoring specs

These get `.allium` files too. For fix specs, entities are the things being fixed, rules are the invariants that were violated, and triggers are the corrective actions. There are NO exceptions to this.

## /allium:distill — Code to Allium

**Input:** Implemented code (source files, controllers, services, models)
**Output:** A `.allium` file representing what was actually built (saved with `-current` or `-distilled` suffix)

### Process

1. **Find the implementation** — use `$ARGUMENTS` or recent git changes
2. **Read all relevant source files** — models, controllers, services, middleware, validators
3. **Extract entities** from data models, DTOs, database schemas
4. **Extract rules** from validation logic, constraints, business rules in code
5. **Extract triggers** from API endpoints, event handlers, background jobs
6. **Write the distilled `.allium` file**
7. **If a pre-implementation `.allium` exists** — compare and report drift (see below)

### Drift detection

When both a pre-implementation `.allium` (from elicit) and a distilled `.allium` (from code) exist:

```
ALLIUM DRIFT REPORT:

Specified but NOT implemented:
- Rule "OrderMustHaveItems" — no validation found in OrderService.Create()

Implemented but NOT specified:
- Endpoint DELETE /api/orders/{id}/force — exists in code, not in spec

Behavioral drift:
- Spec: "payment completes before order confirmation"
- Code: allows order confirmation with status=PendingPayment
```

Each drift item is either a bug (code wrong) or a spec update (spec was incomplete) — flag both, let the developer decide.

## Validation

After writing any `.allium` file, attempt validation:

```bash
if command -v allium &>/dev/null; then
  allium check <file.allium>
fi
```

If `allium check` reports errors, fix them before considering the file complete. If the CLI is not installed, note this but still write the file — the syntax is still valuable for drift detection and TLA+ extraction.

## Auto-install Allium CLI

If the CLI is not installed and you need validation:

```bash
if ! command -v allium &>/dev/null; then
  if command -v brew &>/dev/null; then
    brew tap juxt/allium && brew install allium
  elif command -v cargo &>/dev/null; then
    cargo install allium-cli
  fi
fi
```

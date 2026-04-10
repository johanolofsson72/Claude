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
4. **Extract rules** — state transitions, business operations, event handlers
5. **Extract invariants** — conditions that must ALWAYS hold across all entities
6. **Write the `.allium` file** in the same directory as the spec
7. **Validate** — run `allium check <file>` if the CLI is installed

### Allium v3 language syntax

IMPORTANT: Always start files with the version marker `-- allium: 3` on the first line.

```allium
-- allium: 3

-- Comments use double-dash
-- ============================================================
-- ENUMS
-- ============================================================

enum Priority { low | medium | high | critical }

-- ============================================================
-- ENTITIES
-- ============================================================

entity Order {
    customer: Customer
    total: Decimal
    status: pending | confirmed | shipped | delivered | cancelled  -- inline union type
    tracking_number: String when status = shipped | delivered      -- state-dependent field (only exists in these states)
    shipped_at: Timestamp when status = shipped | delivered
    cancelled_at: Timestamp when status = cancelled
    cancelled_by: String? when status = cancelled                  -- optional (nullable) with ?
    notes: String?

    -- Transition graph: defines valid state changes
    transitions status {
        pending -> confirmed
        confirmed -> shipped
        shipped -> delivered
        pending -> cancelled
        confirmed -> cancelled
        terminal: delivered, cancelled
    }

    -- Relationships
    items: OrderItem with order = this                  -- reverse relationship (has-many)
    active_items: items where status = active           -- filtered view
    item_names: items where status = active -> name     -- projected view

    -- Computed fields
    is_complete: status = delivered
    item_count: items.count

    -- Inline invariant
    invariant NonNegativeTotal { this.total >= 0 }
}

-- External entities are defined elsewhere (not owned by this spec)
external entity Customer {
    email: String
    name: String
}

-- Value objects (no identity, compared by value)
value Address {
    street: String
    city: String
    postcode: String
}

-- ============================================================
-- CONFIG
-- ============================================================

config {
    max_retries: Integer = 3
    cancellation_window: Duration = 48.hours
}

-- ============================================================
-- RULES (business operations / state transitions)
-- ============================================================

-- Rules define WHAT happens, not HOW. They have:
--   when:     what triggers this rule (event or condition)
--   requires: preconditions that must be true
--   ensures:  postconditions / effects

rule ConfirmOrder {
    when: ConfirmOrder(order)
    requires: order.status = pending
    ensures:
        order.status = confirmed
}

rule ShipOrder {
    when: ShipOrder(order, tracking)
    requires: order.status = confirmed
    ensures:
        order.status = shipped
        order.tracking_number = tracking
        order.shipped_at = now
}

rule CancelOrder {
    when: CustomerCancels(order)
    requires: order.status in {pending, confirmed}
    ensures:
        order.status = cancelled
        order.cancelled_at = now
        order.cancelled_by = order.customer.name
}

-- Reactive rule: triggers on state transition
rule NotifyOnShipment {
    when: order: Order.status transitions_to shipped
    ensures: Email.created(to: order.customer.email, template: order_shipped)
}

-- Alternative reactive trigger: "becomes" (equivalent to transitions_to)
rule ArchiveDelivered {
    when: order: Order.status becomes delivered
    ensures: AuditLog.created(action: delivered, order: order)
}

-- Rule with if/else
rule ProcessCancellation {
    when: Cancel(order, reason)
    requires: order.status != delivered
    ensures:
        order.status = cancelled
        order.cancelled_at = now
        if reason = customer_request:
            order.cancelled_by = order.customer.name
}

-- Rule with for-block (iteration)
rule BulkConfirm {
    when: BulkConfirm(batch)
    for order in batch.orders where order.status = pending:
        ensures: order.status = confirmed
}

-- Rule with let bindings and arithmetic
rule ComputeMetrics {
    when: MetricsRequested(doc)
    ensures:
        let count = doc.sections.count
        let avg = doc.word_count / count
        MetricsComputed(document: doc, average: avg)
}

-- Rule with collection operations
rule ValidateItems {
    when: Validate(order)
    requires: order.items.all(i => i.quantity > 0)
    requires: order.items.any(i => i.status = active)
    ensures: ValidationPassed()
}

-- Rule with null handling
rule SafeAccess {
    when: Process(item)
    ensures:
        let val = item.optional?.field ?? "default"
        let check = exists item.optional
        Processed(value: val)
}

-- ============================================================
-- INVARIANTS (must ALWAYS hold, checked globally)
-- ============================================================

invariant AllDeliveredHaveTracking {
    for order in Orders where status = delivered:
        order.tracking_number != null
}

-- ============================================================
-- SURFACES (UI / API exposure)
-- ============================================================

actor Admin {
    identified_by: Customer where role = admin
}

surface OrderDashboard {
    facing viewer: Admin
    context order: Order where customer = viewer
    provides: CancelOrder(order) when order.status in {pending, confirmed}
    provides: ShipOrder(order, tracking) when order.status = confirmed
    exposes:
        order.status
        order.tracking_number
}

-- ============================================================
-- DEFERRED & OPEN QUESTIONS
-- ============================================================

deferred Order.fraud_check

open question "How should partial shipments work?"
```

### Key syntax rules

1. **Version marker** — `-- allium: 3` MUST be the first line
2. **Comments** — `-- comment text`
3. **Types** — `String`, `Integer`, `Decimal`, `Timestamp`, `Duration`, `Boolean`, `Set<T>`
4. **Optional fields** — append `?` to type: `notes: String?`
5. **State-dependent fields** — `field: Type when status = state1 | state2`
6. **Inline union types** — `status: draft | active | archived` (no enum declaration needed)
7. **Named enums** — `enum Name { value1 | value2 }` or `enum Name { value1 \n value2 }`
8. **Backtick literals** — for values with special chars: `` `no-cache` | `pt-BR` ``
9. **Transition graphs** — `transitions field { state1 -> state2; terminal: final_states }`
10. **Rules** — `when:` (trigger), `requires:` (precondition), `ensures:` (postcondition)
11. **Reactive triggers** — `when: entity: Type.field transitions_to value` or `becomes`
12. **Iteration** — `for x in Collection where condition:` (block or expression level)
13. **Let bindings** — `let name = expression`
14. **Collection ops** — `.count`, `.sum(x => expr)`, `.all(x => expr)`, `.any(x => expr)`
15. **Null safety** — `?.` optional chaining, `??` null coalescing, `exists`, `not exists`
16. **Entity creation** — `Type.created(field: value, ...)` in ensures clauses
17. **External entities** — `external entity Name { ... }` for entities defined elsewhere
18. **Value objects** — `value Name { ... }` for identity-less objects
19. **Surfaces** — `surface Name { facing:, context:, provides:, exposes: }`
20. **Deferred specs** — `deferred Entity.capability` for future work
21. **Open questions** — `open question "text"` for unresolved design decisions

### What NOT to write (common mistakes)

- ~~`forall x in Type:`~~ → use `for x in Collection where condition:` or invariant blocks
- ~~`trigger OnEvent { REQUIRE: ... }`~~ → use `rule Name { when: ... requires: ... ensures: ... }`
- ~~`PRESERVE:`, `RETURNS:`~~ → not valid Allium keywords
- ~~`NOT exists x WHERE ...`~~ → use `not exists x` or negate in requires clause
- ~~`UUID → Entity.id`~~ → use relationship: `field: Entity` or `items: Type with field = this`
- ~~`UNIQUE(field1, field2)`~~ → express as invariant
- ~~No version marker~~ → ALWAYS include `-- allium: 3` as the first line

### Quality requirements for elicitation

The `.allium` file must be **more precise** than the markdown spec. This means:

- **Refuse vagueness.** If the spec says "validate input" — specify WHAT validation, WHAT input, WHAT happens on failure.
- **Name every constraint.** If there's a uniqueness requirement, express it as an invariant.
- **Explicit state machines.** If something has a status field, define a `transitions` graph with ALL valid transitions and terminal states.
- **No hand-waving.** "Handle errors appropriately" is not an Allium rule. Express it as a rule with `when:/requires:/ensures:`.

If the spec is too vague to formalize, add `open question "..."` entries or `-- AMBIGUITY:` comments. But still write the best possible spec — don't skip it.

### Hardening / fix / refactoring specs

These get `.allium` files too. For fix specs, entities are the things being fixed, rules capture the corrective actions with their preconditions and effects, and invariants express the constraints that were violated. There are NO exceptions to this.

## /allium:distill — Code to Allium

**Input:** Implemented code (source files, controllers, services, models)
**Output:** A `.allium` file representing what was actually built (saved with `-current` or `-distilled` suffix)

### Process

1. **Find the implementation** — use `$ARGUMENTS` or recent git changes
2. **Read all relevant source files** — models, controllers, services, middleware, validators
3. **Extract entities** from data models, DTOs, database schemas
4. **Extract rules** from API endpoints, event handlers, business logic (use `when:/requires:/ensures:` structure)
5. **Extract invariants** from validation logic, constraints, business rules
6. **Define transition graphs** from state machine logic in code
7. **Write the distilled `.allium` file**
8. **If a pre-implementation `.allium` exists** — compare and report drift (see below)

### Drift detection

When both a pre-implementation `.allium` (from elicit) and a distilled `.allium` (from code) exist:

```
ALLIUM DRIFT REPORT:

Specified but NOT implemented:
- Rule "OrderMustHaveItems" — no validation found in OrderService.Create()

Implemented but NOT specified:
- Endpoint DELETE /api/orders/{id}/force — exists in code, not in spec

Behavioral drift:
- Spec: "payment completes before order confirmation" (rule ConfirmOrder requires payment.status = paid)
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

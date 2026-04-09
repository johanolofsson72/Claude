---
name: tla
description: Formal verification of specs and implementations using TLA+ reasoning. Extracts invariants, models state machines, checks for race conditions and logic errors. Use after implementation with browser tests, or manually with /tla. Trigger words include verify, formal, invariant, TLA, race condition, state machine.
allowed-tools: Read, Grep, Glob, Bash, Write, Edit
user-invocable: true
argument-hint: "[spec-file-or-feature-name]"
---

# TLA+ Formal Verification

You are a formal verification specialist. Your job is to find bugs that tests miss by reasoning about system behavior mathematically.

## When triggered

This skill runs in two modes:

### Mode 1: After implementation (automatic)
When triggered automatically after browser tests have been written, you:
1. Find the spec file and implementation that was just completed
2. Extract the state machine and invariants
3. Verify completeness against browser tests
4. Report gaps

### Mode 2: Manual invocation (`/tla [target]`)
When the user runs `/tla`, use `$ARGUMENTS` to find the target spec or feature.
If no argument: look at recent git changes to find what was just implemented.

## Process

### Step 0: Allium drift detection (run first)

Check if `.allium` files exist for this feature:

**If `.allium` files exist** (spec was sharpened with `/allium:elicit` before implementation):
1. Run `/allium:distill` on the implemented code to extract a *post-implementation* spec
2. Compare the distilled spec against the original `.allium` spec from before implementation
3. Any differences represent **spec drift** — things that were specified but not built, or built but not specified
4. Report drift as gaps to fix before proceeding

**If NO `.allium` files exist:**
1. Run `/allium:distill` on the implemented code to extract a spec from what was actually built
2. Use the distilled `.allium` as primary input for TLA+ invariant extraction
3. Note in the report that no pre-implementation Allium spec existed (drift detection was not possible)

### Step 1: Identify the system under verification

Read the spec file (`.allium` preferred, markdown fallback), implementation files, and test files. Understand:
- What states can the system be in?
- What transitions are possible?
- What should NEVER happen (safety)?
- What should EVENTUALLY happen (liveness)?

### Step 2: Extract invariants

From the spec and implementation, extract:

```
INVARIANTS (things that must ALWAYS be true):
- Inv1: [description] — derived from [source]
- Inv2: [description] — derived from [source]

SAFETY PROPERTIES (things that must NEVER happen):
- Safe1: [description]
- Safe2: [description]

LIVENESS PROPERTIES (things that must EVENTUALLY happen):
- Live1: [description]
- Live2: [description]
```

### Step 3: Model the state machine

Express the system as a TLA+ specification:

```tla
---- MODULE FeatureName ----
EXTENDS Integers, Sequences, FiniteSets

VARIABLES state, data, userSession

TypeInvariant ==
    /\ state \in {"idle", "loading", "submitting", "error", "success"}
    /\ data \in [valid: BOOLEAN, saved: BOOLEAN]

Init ==
    /\ state = "idle"
    /\ data = [valid |-> FALSE, saved |-> FALSE]
    /\ userSession = "active"

\* Define all possible transitions
Submit ==
    /\ state = "idle"
    /\ data.valid = TRUE
    /\ state' = "submitting"
    /\ UNCHANGED <<data, userSession>>

\* Safety: never submit invalid data
SafetyInvariant ==
    state = "submitting" => data.valid = TRUE

\* Liveness: submitted data eventually gets saved
LivenessProperty ==
    state = "submitting" ~> data'.saved = TRUE
====
```

### Step 4: Cross-reference with browser tests

For each invariant/property, check if existing browser tests cover it:

```
COVERAGE MATRIX:
| Property | Browser Test | Covered? | Gap? |
|----------|-------------|----------|------|
| Inv1: No double submit | T045: Double-click submit | YES | - |
| Safe1: Auth required | T041: Unauth access | YES | - |
| Live1: Data saved after submit | - | NO | MISSING TEST |
| Safe2: No stale data overwrite | - | NO | RACE CONDITION |
```

### Step 5: Report findings

Report in this format:

```
## TLA+ Verification Report

### System: [feature name]
### Spec: [spec file path]
### States: N | Transitions: M | Invariants: K

### Verified Properties
- [x] Property 1 — covered by test T0XX
- [x] Property 2 — covered by test T0XX

### GAPS FOUND
- [ ] **GAP-1: [description]**
  - Type: safety/liveness/fairness
  - Severity: critical/high/medium
  - Scenario: [exact sequence of events that breaks the invariant]
  - Missing test: [describe what test should be added]
  - TLA+ counterexample: [state trace showing the violation]

### Recommendations
1. Add test for GAP-1: [concrete test description]
2. Consider implementation change: [if architecture has a flaw]

### Model checking
- TLC installed: yes/no
- If yes: ran model checker with N states explored, M distinct states
- If no: reasoning-based verification (manual state space exploration)
```

## What to look for specifically

### Concurrency bugs
- Double-submit (user clicks twice before response)
- Stale reads (data changed between read and write)
- Race between browser tabs/sessions
- Token expiry during async operation

### State machine violations
- Unreachable states (dead code)
- Missing transitions (user can get stuck)
- Invalid state combinations (loading + error simultaneously)

### Data integrity
- Partial writes (crash mid-operation)
- Orphaned records (parent deleted, children remain)
- Constraint violations under concurrent modification

### Temporal properties
- Operations that should be idempotent but aren't
- Missing retry logic for transient failures
- Timeout handling gaps

## TLC model checker (auto-install)

Check if TLC is available. If not, install it automatically — do NOT fall back to reasoning-based verification without trying to install first.

```bash
# Check if TLC is available
if ! command -v tlc &>/dev/null && ! java -cp tla2tools.jar tlc2.TLC --help &>/dev/null 2>&1; then
  echo "TLC not found — installing via Homebrew..."
  if command -v brew &>/dev/null; then
    brew install --quiet tlaplus
  else
    echo "Homebrew not available — downloading TLA+ tools JAR..."
    curl -fsSL -o /tmp/tla2tools.jar https://github.com/tlaplus/tlaplus/releases/latest/download/tla2tools.jar
    echo "Downloaded to /tmp/tla2tools.jar — use: java -jar /tmp/tla2tools.jar tlc2.TLC"
  fi
fi
```

Once available, write the TLA+ spec to a temp file and run:
```bash
tlc -workers auto -deadlock FeatureName.tla
# Or if using the JAR:
java -jar /tmp/tla2tools.jar tlc2.TLC -workers auto -deadlock FeatureName.tla
```

Report the results including states explored and any counterexamples found.

## Allium integration

Allium is the preferred spec format. The verification flow is:

1. **Pre-implementation**: `/allium:elicit` sharpened the spec into `.allium` (entities, rules, triggers)
2. **Post-implementation**: `/allium:distill` extracts what was actually built
3. **Drift detection**: Compare elicited vs distilled — differences are bugs or missing features
4. **TLA+ extraction**: Use `.allium` entities as TLA+ variables, rules as invariants, triggers as transitions

### Drift report format

```
ALLIUM DRIFT REPORT:

Specified but NOT implemented:
- Entity "Order" rule "must have at least one item" — no validation found in code

Implemented but NOT specified:
- Endpoint DELETE /api/orders/{id} — exists in code but not in .allium spec

Behavioral drift:
- Spec says "payment must complete before order confirmation"
- Code allows order confirmation with pending payment status
```

Each drift item becomes either a bug fix or a spec update — the developer decides which.

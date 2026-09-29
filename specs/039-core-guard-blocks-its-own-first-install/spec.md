# 039 — core guard blocks its own first install

Track: spec-only. No entity, no state machine, no new surface. Not hardened: one existing guard and
its self-test. The guard is a protection, but the change narrows a deny to the writes that change
something; every write that alters a CORE file is still refused.

Evidence: hetznerradar bootstrap, 2026-09-07 (T0). Diagnosis in `specs/INDEX.pending.md`.

## The defect

`scripts/core-machinery-guard-hook.sh` decides on the path alone. A first `/project-update` places
every CORE script for the first time, and the guard refused `scripts/tlc-cleanup.sh` with bytes
identical to the template's copy. The only way through was `ALLOW_CORE_MACHINERY_EDIT=1`, which is
also the escape hatch for a deliberate local repair. Reaching for it as routine bootstrap wears it out.

## Decision

After the classifier says CORE, and before denying, compute the bytes the tool call would leave on
disk and compare them with `<template>/<rel>`:

- `Write` → `tool_input.content`.
- `Edit` → the current file with `old_string` replaced by `new_string` (first occurrence, or every
  one with `replace_all`).
- `MultiEdit` → the same, applied in order over `tool_input.edits`.

Byte-identical → allow, silently. Anything else denies as today: different bytes, no template clone,
no template copy of the file, an Edit against a file that does not exist, a payload with no bytes
(the Bash route through `bash-write-guard-hook.sh` passes a path only), or a computation that fails.

The template is resolved from the candidates the deny message already uses: `$CLAUDE_TEMPLATE_DIR`,
`~/repos/Claude`, `~/repos/claude`. No fetch.

## Functional requirements

- **FR-01** Write whose content equals the template copy → no output, exit 0.
- **FR-02** Write whose content differs by one byte (including a trailing newline) → deny as today.
- **FR-03** Edit / MultiEdit whose result equals the template copy → allow silently.
- **FR-04** Edit / MultiEdit whose result differs → deny.
- **FR-05** No template clone resolvable, or no file at `<template>/<rel>` → deny (fail closed).
- **FR-06** A payload with a path and no bytes (the Bash delegation) → deny as today.
- **FR-07** Non-CORE paths, the template repo, the override and a broken classifier behave exactly
  as before (arms A3–A12 unchanged).
- **FR-08** The deny text says a byte-identical write would have passed, so a sync author knows why.

## Scenarios

- SC-039-01 Write, content == template copy → silent.
- SC-039-02 Write, content == template copy minus the final newline → deny.
- SC-039-03 Write, content differs → deny.
- SC-039-04 Edit on a drifted project copy, result == template → silent.
- SC-039-05 Edit, result != template → deny.
- SC-039-06 Edit with replace_all → result computed over every occurrence.
- SC-039-07 MultiEdit, result == template → silent.
- SC-039-08 Write identical bytes, no template reachable → deny.
- SC-039-09 Write identical bytes, template has no such file → deny.
- SC-039-10 path-only payload (Bash route) for a CORE file → deny.
- SC-039-11 Write of non-ASCII content equal to template → silent.
- SC-039-12 Edit against a file that does not exist → deny.

## Out of scope

- The Bash route. `cp "$TEMPLATE/scripts/x" scripts/x` reaches the guard with a path and no bytes,
  so it is still denied. Reading the source of a `cp` is a parser change in
  `bash-write-guard-hook.sh`; recorded as a finding.
- Comparing against what the sync would fetch from origin instead of the local clone.

## Clarifications

### Session 2026-09-29

- Q: Compare against the local clone or the fetched template? → A: The local clone, the same
  candidates the deny text names. A guard in front of every edit is worth a stat, not a fetch.
  A stale clone can let through bytes that match an older template version. Nothing is lost by
  that: those bytes are the template's, not local work, and the next sync replaces them with the
  current copy. The guard exists to stop local work from being silently collected, and a write
  that equals any template version carries none.
- Q: Should the allow say anything? → A: No. The diagnosis says silently, and an allow that talks
  on every file of a first sync is noise the model reads 50 times.

# Spec

Customers open a return within 30 days.

## Scope

In: opening a return. Out: refunds.

## Acceptance criteria

- A return can be opened from day 0 to day 30 after delivery, inclusive; day 31 returns HTTP 422 with code RETURN_WINDOW_CLOSED.
- An opened return appears in the support queue within 60 s.
- A second return for the same order line returns HTTP 409.

## Notes

The register row carries the one-line goal; this file is the source of truth for the behaviour.
Any change to the criteria goes through clarify before plan.

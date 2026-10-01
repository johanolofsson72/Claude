# Spec

Customers pay for a cart.

## Scope

In: card payment via the gateway. Out: invoices.

## Acceptance criteria

- Payment errors are handled gracefully.
- A paid order gets status Paid within 5 s of the gateway's webhook.
- A declined card shows the gateway's decline reason.

## Notes

The register row carries the one-line goal; this file is the source of truth for the behaviour.
Any change to the criteria goes through clarify before plan.

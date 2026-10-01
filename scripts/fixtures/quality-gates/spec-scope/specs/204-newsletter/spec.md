# Spec

Customers opt in or out of the newsletter.

## Scope

In scope: the opt-in checkbox at signup and the toggle on the account page.

Out of scope: sending newsletters, segmentation.

## Acceptance criteria

- The signup form has an unchecked opt-in box; checking it records consent with a timestamp.
- The account page toggle changes consent and records the time of the change.
- An opted-out customer is excluded from the export the mail tool reads.

## Notes

The register row carries the one-line goal; this file is the source of truth for the behaviour.
Any change to the criteria goes through clarify before plan.

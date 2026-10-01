# Spec

Customers manage saved addresses.

## Scope

In scope: adding, editing and deleting up to 5 saved addresses; choosing one at checkout.

Out of scope: address validation against the postal service.

## Acceptance criteria

- A customer can save up to 5 addresses; a sixth returns an error naming the limit.
- Editing an address updates it everywhere it is offered at checkout.
- Deleting the default address makes the oldest remaining one the default.

## Notes

The register row carries the one-line goal; this file is the source of truth for the behaviour.
Any change to the criteria goes through clarify before plan.

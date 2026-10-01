# Spec

Staff see stock per SKU.

## Scope

In: the stock list page. Out: editing stock.

## Acceptance criteria

- The list shows every active SKU with its on-hand count, sorted by SKU ascending.
- A SKU with 0 on hand is shown with the label 'Slut i lager'.
- p95 page load is under 800 ms with 5,000 SKUs.

## Notes

The register row carries the one-line goal; this file is the source of truth for the behaviour.
Any change to the criteria goes through clarify before plan.

# Plan

Stack: .NET 9 Web API + React, SQLite, Docker Swarm (see CLAUDE.md).

## Steps

1. Add the Coupons table + migration (rollback: down migration drops the table; no data yet).
2. CouponService with unit tests for expiry, single use and minimum order.
3. Checkout integration with integration tests against SQLite.
4. Playwright E2E for applying, rejecting and removing a coupon.
5. Deploy via the deploy workflow; verify on staging, then production.

## Notes

Each step lands as its own commit with its tests; the plan is revisited after step 2.
Nothing here changes the public API beyond what the spec names.
Estimated effort: two to three days for one developer, reviewed at the end of each step.

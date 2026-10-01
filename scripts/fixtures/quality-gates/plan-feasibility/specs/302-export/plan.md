# Plan

Stack: .NET 9 Web API + React, SQLite, Docker Swarm (see CLAUDE.md).

## Steps

1. Store export jobs in MongoDB for flexibility.
2. Build the CSV writer with unit tests.
3. Add the admin page with Playwright tests.
4. Deploy behind a feature flag; roll back by turning it off.

## Notes

Each step lands as its own commit with its tests; the plan is revisited after step 2.
Nothing here changes the public API beyond what the spec names.
Estimated effort: two to three days for one developer, reviewed at the end of each step.

# Plan

Stack: .NET 9 Web API + React, SQLite, Docker Swarm (see CLAUDE.md).

## Steps

1. Ratings table + migration with a down migration.
2. RatingsService with unit and property-based tests for the average.
3. API endpoint with integration tests (auth required to post).
4. React stars component with visual-regression baselines.
5. Deploy, watch error rates for one day, roll back by reverting the release if they rise.

## Notes

Each step lands as its own commit with its tests; the plan is revisited after step 2.
Nothing here changes the public API beyond what the spec names.
Estimated effort: two to three days for one developer, reviewed at the end of each step.

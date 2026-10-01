# Plan

Stack: .NET 9 Web API + React, SQLite, Docker Swarm (see CLAUDE.md).

## Steps

1. Add the Points table and EF migration.
2. Implement PointsService (earn on paid order, spend at checkout).
3. Wire the account page in React.
4. Deploy to production.

## Notes

Each step lands as its own commit once it builds cleanly; the plan is revisited after step 2.
Nothing here changes the public API beyond what the spec names.
Estimated effort: two to three days for one developer, reviewed at the end of each step.

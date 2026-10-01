# Acceptance cases — 080-developer-authored-acceptance-cases

**Confirmed:** 2026-10-01 · eda34ea54405 — "Confirmed as written; AC-4 re-confirmed with the 2026-10-02 cutoff (Confirm new AC-4)"

Drafted by Claude, confirmed by the developer through AskUserQuestion. Tests name a case as
`080-AC-<n>`.

## AC-1 — Unconfirmed cases block code
**Given** a full-track active spec with the interview done and 3 well-formed cases but no Confirmed line
**When** Claude edits src/app.ts
**Then** the edit is denied, and the reason says the developer has not confirmed the cases and how to ask them

## AC-2 — Editing a confirmed case re-locks code
**Given** confirmed cases whose digest matches
**When** one case's Then line is changed
**Then** production edits are denied for a digest mismatch until the developer confirms again

## AC-3 — Tests come first
**Given** confirmed cases AC-1..3 where tests name only 080-AC-1 and 080-AC-2
**When** Claude edits a test file, and then production source
**Then** the test edit is allowed and the production edit is denied naming 080-AC-3; once a test names 080-AC-3, production edits are allowed

## AC-4 — Exempt specs pass
**Given** a light row without [hardened], or a full row begun before 080 landed (a ticked task, no acceptance.md, interview.md committed before 2026-10-02)
**When** Claude edits production source
**Then** the edit is allowed

## AC-5 — Band enforced
**Given** 2 cases, 6 cases, or a numbering gap (AC-1, AC-3)
**When** Claude edits production source
**Then** the edit is denied naming the count or the gap

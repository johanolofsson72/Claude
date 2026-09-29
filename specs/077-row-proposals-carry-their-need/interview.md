# Spec interview — 077-row-proposals-carry-their-need

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO with human overflow (hardened by size). Q1–Q4 are the developer's, 2026-09-29.

## Q1 — Scope (developer)
**Q:** How is the convergence stop answered?
**A:** Freeze. The pipeline reports and validates the need behind every proposed row and presents it for approve/decline.

## Q2 — Approval during freeze (overflow)
**Q:** Does an approved proposal become a row during the freeze or wait?
**A:** It becomes a row immediately. Approval is the gate.

## Q3 — Cadence (overflow)
**Q:** When are proposals presented?
**A:** At every spec stop. Plain findings keep the 5-spec review.

## Q4 — Enforcement (overflow, threat surface)
**Q:** Hard deny or report?
**A:** Report and flag violations. No deny hook, because of row 029.

## Q5 — Data model
**Q:** Where does the freeze live?
**A (auto):** One header line in specs/INDEX.md. It is git-tracked, so both lanes and every hook see the same freeze.

## Q6 — Data model
**Q:** How is "added during the freeze" decided?
**A (auto):** A numeric id above `last row`. That is cheap and needs no git history. Carved suffixes such as 078a count as 078.

## Q7 — Tampering (threat surface)
**Q:** Can a row fake approval?
**A (auto):** Only if the tag names a finding resolved as approved in FINDINGS.md. Otherwise it is flagged.

## Q8 — Input tampering (threat surface)
**Q:** Can finding text execute or escape?
**A (auto):** No. It is passed to python via argv and never evaluated, and cited paths containing `..` are refused.

## Q9 — Resource exhaustion (threat surface)
**Q:** Can the review get slow?
**A (auto):** It compares each finding with each row, 11 × 52 today. Acceptable. Row 054 owns ledger scaling.

## Q10 — Information disclosure (threat surface)
**Q:** Does review print anything outside the repo?
**A (auto):** No. Path checks stay under ROOT, and it prints only ledger and register text.

## Q11 — Four states
**Q:** What does review say with nothing open?
**A (auto):** "no open findings". With no ledger it says "no findings recorded". It never prints an empty table.

## Q12 — Error semantics
**Q:** `--propose-row` without `--need`?
**A (auto):** Exit 2: "a row proposal needs --need: who is hurt and where it was observed".

## Q13 — Error semantics
**Q:** `--decline` without a reason?
**A (auto):** Exit 2. A decline without a reason cannot be revisited.

## Q14 — Duplicate check
**Q:** How is overlap measured?
**A (auto):** Jaccard over lowercase words of 5+ letters with stopwords removed, threshold 0.25. It is reported, not gated. Semantic search stays with register-similarity.sh.

## Q15 — Integration
**Q:** Which readers change?
**A (auto):** The orientation hook (banner). project-maintenance flags a freeze violation. lane-catchup is unchanged because it prints the convergence line.

## Q16 — Lift
**Q:** What happens when open rows fall below 40?
**A (auto):** `--freeze` exits 3 and the banner says the freeze can lift. The developer deletes the line. Nothing lifts on its own.

## Q17 — Reversibility
**Q:** How is it undone?
**A (auto):** Delete the Freeze line. Proposals remain ordinary findings.

## Q18 — Acceptance
**Q:** What proves it?
**A (auto):** New self-test cases with sabotage arms, the banner on this repo, and one review pass with explicit decisions.

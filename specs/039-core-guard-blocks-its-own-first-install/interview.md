# Spec interview — 039-core-guard-blocks-its-own-first-install

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. No overflow: no hardened trigger fires (no auth/PII/upload/new surface, no state machine, no new entity, 2 source files). The guard is a protection, but the change only allows writes that leave a CORE file equal to the template's copy.

## Q1 — Scope boundary
**Q:** Which routes into the guard does the spec change?
**A (auto):** Edit, Write and MultiEdit, the routes whose payload carries bytes. The Bash delegation passes a path only and stays a deny; teaching the Bash parser to read a `cp` source is a finding.

## Q2 — Primary actor
**Q:** Who is hurt today?
**A (auto):** A session running a first `/project-update` (or any sync-by-hand) on a project that already has `template-autosync.sh`. Every CORE file it places is refused, and the only way through is the override.

## Q3 — Happy-path outcome
**Q:** What does done look like?
**A (auto):** A Write whose bytes equal `<template>/<rel>` passes with no output. Every write that would change a CORE file away from the template is denied with the same text as today.

## Q4 — What is compared
**Q:** Which bytes are compared?
**A (auto):** The file as it would be after the tool call: Write content, or the current file with the Edit/MultiEdit replacements applied. Not the edit fragment.

## Q5 — Comparison strictness
**Q:** Exact bytes, or normalised (line endings, trailing newline)?
**A (auto):** Exact bytes. The sync copies bytes; a missing trailing newline is a difference the next sync would overwrite, so it is a divergence.

## Q6 — Template source
**Q:** Where does the template copy come from?
**A (auto):** The candidates the deny text already names: `$CLAUDE_TEMPLATE_DIR`, `~/repos/Claude`, `~/repos/claude`, each only if it has `scripts/sync-prompt.md` and `.claude/rules/`. No fetch, no tarball.

## Q7 — Template unresolvable
**Q:** No clone found?
**A (auto):** Deny. Fail closed, as the diagnosis states: with nothing to compare against, nothing proves the write benign.

## Q8 — Template file missing
**Q:** Clone found, but it has no file at `<rel>`?
**A (auto):** Deny. A CORE name with no template file is a classifier/template mismatch, not proof of anything.

## Q9 — Edit semantics
**Q:** How is an Edit applied?
**A (auto):** First occurrence of `old_string` replaced by `new_string`, or every occurrence with `replace_all: true`. In jq with split/join, so offsets are never computed and non-ASCII content is safe.

## Q10 — Edit against a missing file
**Q:** Edit or MultiEdit on a file that does not exist?
**A (auto):** Deny. The tool would fail anyway, and there is no current content to compute from.

## Q11 — Computation failure
**Q:** jq fails, the file is unreadable, a temp file cannot be made?
**A (auto):** Deny as today. The allow must be proven; any failure on the way leaves the old behaviour.

## Q12 — Allow output
**Q:** Should the allow emit additionalContext?
**A (auto):** No. Silent. A first sync writes dozens of CORE files and a line on each is noise.

## Q13 — Deny text
**Q:** Does the deny text change?
**A (auto):** One sentence: a write whose bytes equal the template's copy would have passed, so a sync is never the thing refused. Everything else stays.

## Q14 — Ordering and cost
**Q:** Where does the comparison run, and what does it cost the common case?
**A (auto):** After `--is-core` answers CORE, so non-CORE edits (almost all of them) pay nothing new. The comparison is one jq and one cmp.

## Q15 — Existing behaviour
**Q:** What must not move?
**A (auto):** Arms A1–A12: CORE deny, non-CORE silence, template-repo exemption, no-sync exemption, override message, fail-open classifier, timeout bound, --is-core cost.

## Q16 — Portability
**Q:** Platform constraints?
**A (auto):** bash + jq + cmp, already required; `mktemp` as the guard's siblings use it. Must pass `validate-portability.sh` and run under Git Bash.

## Q17 — Acceptance criteria
**Q:** Measurable definition of done?
**A (auto):** SC-039-01..12 pass in `test-core-machinery-guard.sh`, the allow arms were red on HEAD, A1–A12 still pass, `test-bash-write-guard.sh` still passes.

## Q18 — Reversibility
**Q:** Undo story?
**A (auto):** One revert of the guard change. No state, no migration.

## Q19 — Non-goals
**Q:** What is explicitly not done?
**A (auto):** No Bash-route byte inspection, no fetch of the remote template, no change to `--is-core` or the CORE lists.

# Run log — 105-guard-bypasses

One line per event. Failure memory for a spec resumed in a fresh session.
Append-only, deduped, capped. NOT pipeline input — read the tail, never the whole file.

- 2026-11-17T10:23Z · specify · spec.md written
- 2026-11-17T10:24Z · interview · interview.md written
- 2026-11-17T10:31Z · specify · spec.md written
- 2026-11-17T10:33Z · allium:elicit · spec.allium written
- 2026-11-17T10:33Z · spec, interview, acceptance (07c7dba9fb71), clarify, allium, plan, tasks written; R13 precheck loop fixed (F258), F259 recorded; threat model agent running
- 2026-11-17T10:55Z · R1 R2 R3 R4 R5 R6 R7 R8 R13 built, owning self-tests green (trust-anchor 297, guard-lib 104, core-machinery 56, gc 10, template-identity 53, settings 485, mod 36); threat model 35 items back, triage into spec pending; next R9 R10 R11
- 2026-11-17T11:14Z · specify · spec.md written
- 2026-11-17T11:15Z · all R1-R13 built + owning tests green; threat model triaged into spec (35: adopted/bound/F260-F268); R8 regex reverted to whole-name + nested -c/eval/heredoc re-judge; R10 grandfather rewritten (merge TREESAME simplification); next: full suite, bench, mutation, adversarial review, tla
- 2026-11-17T11:32Z · specify · spec.md written
- 2026-11-17T12:05Z · allium:elicit · spec.allium written
- 2026-11-17T12:43Z · verification: suite green (pre-review); adversarial review 11 items fixed/dismissed; /security-review 3 vulns fixed; TLA AnswerBinding v1 fails, v2/v2del clean (fix: bare token never writes); hand mutants 26/26, shell changed-lines 63/69 (6 equivalent); bench SC-2 unchanged; /simplify applied A-F, shared parser -> finding; final suite running

# Spec interview — 101-guard-parser-dedupe

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. No overflow: spec-only track, no hardened trigger. Three guards keep their verdicts while
one copy of a rule replaces two; no new trust boundary, entity, state machine or external surface.

## Q1 — Scope boundary
**Q:** What is in, what is out?
**A (auto):** In: F153 (one sed purity parser), F154 (by_name per simple command), F132 (Step -1 uses
template_url_matches). Out: `find -exec grep` patterns, the test harnesses' own template detection,
anything that widens what sensitive-file calls a path.

## Q2 — Primary actor
**Q:** Who is hurt today?
**A (auto):** The developer fixing a guard. A fix to one sed parser leaves the other behind, a find on
one command denies a cp on another, and an evil-owner clone at the template path gets fetched by Step -1.

## Q3 — Which sed parser survives
**Q:** Keep `_SED_PURE` or `sed_script_kind`?
**A (auto):** `sed_script_kind`. It reads every sed command, fails closed on anything it does not know,
and two guards already depend on it. The regex only knows one s or y.

## Q4 — Purity semantics for sensitive-file
**Q:** Does "print" count as pure for sensitive-file?
**A (auto):** Yes. A print, delete or move command opens no file; a regex address is a pattern.

## Q5 — Argument walking
**Q:** Who walks sed's options?
**A (auto):** shell_glob, once. It returns (word, script) pairs; `sed_args` keeps its shape for its two
callers. sensitive_paths' own walker is deleted.

## Q6 — -f together with -e
**Q:** With `-f prog -e 'r .env'`, is the -e script still split?
**A (auto):** Yes. The pairs include -e scripts whatever -f says; only `sed_args` maps from_file to None.

## Q7 — Import failure
**Q:** What if shell_glob cannot be imported in a downstream project?
**A (auto):** Plain split of the whole command: stricter, never looser. Same as the missing
destructive_command.py path today.

## Q8 — Is shell_glob shipped with sensitive-file downstream?
**Q:** Does the sync carry shell_glob.py wherever sensitive_paths.py goes?
**A (auto):** Check the sync bundle list; add it to sensitive-file's bundle if absent. Q7 covers an
old project in the meantime.

## Q9 — by_name sources
**Q:** Which by_name sources become per-command?
**A (auto):** Only the tree-command one (find fd xargs rsync tar zip). The cd/-C ones stay line-wide:
every later command runs in that directory.

## Q10 — Redirect targets
**Q:** A tree command's redirect target?
**A (auto):** It gets by_name with its command: `find . > settings.json` is judged by name.

## Q11 — pattern_indices
**Q:** What happens to the grep/rg special case?
**A (auto):** It shrinks to `xargs grep|rg`. A direct grep never has by_name without dots after R3, so
the direct branch is dead and would only breed surviving mutants.

## Q12 — Step -1 URL source
**Q:** `remote get-url` or the raw config value?
**A (auto):** Raw `git config --local --get remote.origin.url`, as template_identity does: get-url
applies insteadOf, which is how a redirect hides behind a good-looking URL.

## Q13 — Missing library in Step -1
**Q:** Clone without scripts/template-identity.sh?
**A (auto):** Warn, do not fetch, use it as is, with the manual `pull --ff-only` hint. Same fail-closed
choice as template-autosync.sh.

## Q14 — Fresh clone path
**Q:** The block clones TEMPLATE_URL itself; does its new clone pass the anchored check?
**A (auto):** Yes, origin is TEMPLATE_URL verbatim. The test redirects it with insteadOf in the fake
HOME instead of rewriting TEMPLATE_URL, so the block runs unmodified.

## Q15 — Error/empty states
**Q:** Empty origin URL, or no git at all?
**A (auto):** Empty URL fails the match → "not a clone of the template repo". Not a git dir → the block
skips the refresh, as today.

## Q16 — Tests
**Q:** Where do new cases go?
**A (auto):** `[101]` cases in test-sensitive-file-guard.sh (print scripts pass, -f plus -e r still
denies, BSD `-i .bak`), test-settings-edit-guard.sh (find on one command does not by-name another;
`find > settings.json` still denies; xargs grep pattern still passes), test-sync-prompt-bootstrap.sh
(insteadOf fixture, evil owner, missing library).

## Q17 — Sabotage arms
**Q:** The sensitive-file sabotage arm seds the `_SED_PURE` line. After R1?
**A (auto):** Retarget it to the new purity line, so the arm still proves the rule is observable.

## Q18 — Mutation gate
**Q:** What is measured?
**A (auto):** `--lines` over the changed lines of shell_glob.py, sensitive_paths.py and
settings_guard.py; ≥ 80%, no timeout counted as a kill. Survivors become findings.

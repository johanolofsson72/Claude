# Spec interview — 070-freshness-audits-npm-only

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. Spec-only, no hardening trigger (one CORE script and its self-test; no entity, no surface, no auth), so no overflow.

## Q1 — Scope boundary
**Q:** What is in, what is out?
**A (auto):** In: a coverage pass that lists non-npm, non-.NET manifests and says per manifest whether anything audited it; the SUMMARY/RESULT wording; the osv skip line. Out: new auditors, self-installing osv-scanner, changing passes 3–5's verdict logic.

## Q2 — Primary actor
**Q:** Who is hurt today?
**A (auto):** A developer or a checkpoint (H1) reading the freshness SUMMARY on a polyglot project. ekofak's Maven backend was never looked at and the report read as complete.

## Q3 — Happy path
**Q:** What does done look like?
**A (auto):** Every Maven/Gradle/Cargo/Go/pip/Ruby/PHP/Elixir/Dart manifest in the project appears once, as `[OK] … — osv-scanner (…)` or `[SKIP] … — no auditor: <why>`, and the SUMMARY counts them.

## Q4 — Which ecosystems
**Q:** Which manifests are inventoried?
**A (auto):** pom.xml, build.gradle(.kts), Cargo.toml, go.mod, pyproject.toml, requirements.txt, Pipfile, Gemfile, composer.json, mix.exs, pubspec.yaml. These are the ecosystems osv-scanner documents support for.

## Q5 — Why leave out package.json and .csproj
**Q:** Why not inventory npm and .NET too?
**A (auto):** Passes 3 and 5 already print one line per manifest with a verdict. Repeating them adds noise, not information.

## Q6 — Covered rule
**Q:** When does a manifest count as covered?
**A (auto):** osv-scanner gave a verdict (exit 0/1) and reads a file for it: the manifest itself for pom.xml / go.mod / requirements.txt, otherwise the ecosystem's lockfile in its dir or an ancestor up to the root.

## Q7 — Ancestor lockfiles
**Q:** Why search ancestors?
**A (auto):** Cargo, uv, mix umbrella and Gradle multi-project builds keep one lockfile at the workspace root. A member without its own lock is still covered.

## Q8 — osv-scanner absent
**Q:** What does a manifest say when osv-scanner is not installed?
**A (auto):** `[SKIP] <rel> — no auditor: osv-scanner not installed (install: <hint>)`.

## Q9 — osv-scanner errors or exits 128
**Q:** And when osv-scanner ran but gave no verdict?
**A (auto):** `[SKIP] <rel> — no auditor: osv-scanner gave no verdict (exit N)`. A scanner that errored vouched for nothing.

## Q10 — Missing lockfile advice
**Q:** What fix does a lockless manifest get?
**A (auto):** The ecosystem's own lock command: `./gradlew dependencies --write-locks` (after enabling dependency locking), `cargo generate-lockfile`, `poetry lock` / `uv lock`, `pipenv lock`, `bundle lock`, `composer update --lock`, `mix deps.get`, `dart pub get`.

## Q11 — Exit code
**Q:** Does an unchecked manifest change the exit code?
**A (auto):** No. It is not-scanned, the third state: RESULT says "NOT SCANNED … That is not clean", exit stays 0, as for trufflehog failures today.

## Q12 — Summary wording
**Q:** What do the SUMMARY lines say?
**A (auto):** `npm:` replaces `Deps:` (it was only ever npm's verdict). New `Other:` line: `none found` / `all N covered by osv-scanner` / `N of M UNCHECKED — <rel>; …`.

## Q13 — Exclusions
**Q:** Which directories are skipped?
**A (auto):** The shared ones (node_modules, bin, obj, .claude/worktrees, git-ignored) plus target, build, .gradle, vendor, .venv, venv, _build, deps, .dart_tool. `target/` holds Maven's copied pom files and must never be listed.

## Q14 — Outside git
**Q:** What happens outside a git repo?
**A (auto):** The ignore oracle is inert, only the path exclusions apply, same as the other walks.

## Q15 — Network and installs
**Q:** Does the pass reach the network or install anything?
**A (auto):** No. It only runs `find` and file tests. osv-scanner stays optional and never self-installed.

## Q16 — Portability
**Q:** Platforms?
**A (auto):** bash 3.2 (macOS), Linux, Git Bash. No associative arrays, no mapfile, no GNU-only find flags.

## Q17 — Acceptance / sabotage
**Q:** How do we know the tests bite?
**A (auto):** Two sabotage arms: "osv present = covered" ignoring the lockfile rule must turn the Gradle case red; dropping the NOT_SCANNED join must turn the Maven-without-osv RESULT case red.

## Q18 — Non-goals
**Q:** What is explicitly not promised?
**A (auto):** That osv-scanner's verdict is complete (a pom.xml resolved offline misses transitive deps; that is osv's contract), or that the other passes change behaviour.

## Q19 — Reversibility
**Q:** Rollback story?
**A (auto):** Revert the commit; the pass is additive and output-only. The label rename touches only the self-test.

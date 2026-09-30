# 070 — freshness-audits-npm-only

Track: spec-only. A fix to one CORE script and its self-test (`scripts/project-freshness.sh`,
`scripts/test-project-freshness.sh`). No entity, no state machine, no new external surface. No
hardening trigger.

Evidence: ekofak H1 (2026-09-28). Diagnosis in `specs/INDEX.pending.md`.

## The defect

The diagnosis says the script runs `npm audit` and nothing else. That was true of ekofak's copy
when H1 ran. The template has since gained an osv-scanner pass and a `dotnet list package
--vulnerable` pass (073). The part of the defect that is still live:

1. **Nothing inventories the manifests.** Pass 3 finds `package.json`, pass 5 finds
   `.sln/.slnx/.csproj`. Pass 4 hands the tree to osv-scanner and reports its exit code. No pass
   looks for `pom.xml`, `build.gradle`, `Cargo.toml`, `go.mod`, `pyproject.toml`,
   `requirements.txt`, `Gemfile`, `composer.json`, `mix.exs` or `pubspec.yaml`, so none can say
   one went unchecked.
2. **osv-scanner absent → the backend is not named.** The skip line says "NuGet/pub lockfiles
   unscanned". A Maven backend reads as out of scope rather than as unchecked.
3. **osv-scanner present but blind → silent.** osv-scanner reads `pom.xml` but not
   `build.gradle(.kts)`, `Cargo.toml`, `pyproject.toml`, `Gemfile` or `composer.json`. It needs
   the lockfile. A Gradle project with no `gradle.lockfile` scans "clean".
4. **The summary line `Deps:` is npm's verdict** and reads like the whole dependency surface
   ("Deps: advisories — frontend/").

## Requirements

- **FR-01** A sixth pass, *dependency coverage*, runs with the dependency passes (`--deps` and
  default). It lists every project manifest of these ecosystems: Maven `pom.xml`, Gradle
  `build.gradle` / `build.gradle.kts`, Rust `Cargo.toml`, Go `go.mod`, Python `pyproject.toml` /
  `requirements.txt` / `Pipfile`, Ruby `Gemfile`, PHP `composer.json`, Elixir `mix.exs`, Dart
  `pubspec.yaml`. npm and .NET manifests are left out because passes 3 and 5 own them and already
  report each one.
- **FR-02** The walk uses the same exclusions as the other walks (node_modules, bin, obj,
  .claude/worktrees, git-ignored) plus the build and vendor directories of these ecosystems
  (`target`, `build`, `.gradle`, `vendor`, `.venv`, `venv`, `_build`, `deps`, `.dart_tool`).
- **FR-03** A manifest is **covered** only when osv-scanner ran and gave a verdict (exit 0 or 1)
  **and** osv-scanner reads a file for it: the manifest itself (`pom.xml`, `go.mod`,
  `requirements.txt`), or its lockfile in the manifest's directory or an ancestor up to the root
  (`gradle.lockfile` / `gradle/verification-metadata.xml`, `Cargo.lock`, `poetry.lock` /
  `uv.lock` / `pdm.lock` / `pylock.toml`, `Pipfile.lock`, `Gemfile.lock`, `composer.lock`,
  `mix.lock`, `pubspec.lock`). Covered prints `[OK] <rel> — osv-scanner (<file rel>)`.
- **FR-04** Every other manifest prints `[SKIP] <rel> — no auditor: <why>`, with a why that names
  the fix: osv-scanner not installed (+ install hint), osv-scanner errored / found nothing
  (exit N), or no lockfile osv-scanner reads (+ the ecosystem's lock command).
- **FR-05** An unchecked manifest is not a finding and not clean: it joins `NOT_SCANNED`, so
  RESULT reads "no findings, but NOT SCANNED … That is not clean." Exit code stays 0 (unchanged
  semantics for not-scanned).
- **FR-06** SUMMARY gains `Other:` with `none found`, `all N covered by osv-scanner`, or `N of M
  UNCHECKED — <rel>; …`. The `Deps:` label becomes `npm:`.
- **FR-07** The osv-scanner skip line names the ecosystems it would cover (`NuGet/pub/Maven/
  Gradle/Cargo/Go/pip/… lockfiles unscanned`).
- **FR-08** No auditor is self-installed and no network tool is added (osv-scanner stays
  optional). bash 3.2-safe.

## Acceptance

- AC1 A repo with `backend/pom.xml` and osv-scanner absent: `[SKIP] backend/pom.xml — no
  auditor: osv-scanner not installed`, `Other:    1 of 1 UNCHECKED`, RESULT says NOT SCANNED.
- AC2 Same repo, osv-scanner stub exit 0: `[OK] backend/pom.xml — osv-scanner`, `Other: all 1
  covered`, RESULT clean.
- AC3 `build.gradle` with no lockfile, osv exit 0: SKIP "no lockfile osv-scanner reads".
  With `gradle.lockfile` alongside: OK.
- AC4 `Cargo.toml` in a workspace member, `Cargo.lock` at the workspace root: OK (ancestor rule).
- AC5 osv-scanner exit 127: the manifest is SKIP "osv-scanner errored (exit 127)".
- AC6 A `pom.xml` under `target/` or a gitignored dir is not listed.
- AC7 No such manifests: `Other:   none found`, no NOT SCANNED from this pass.
- AC8 SUMMARY prints `npm:` and no longer `Deps:`; section headers read `/6`.
- AC9 Sabotage: treating "osv present" as covered regardless of lockfile turns AC3 red; dropping
  the NOT_SCANNED join turns AC1's RESULT assertion red.

## Clarifications

### Session 2026-09-30

- Q: Run Maven's own OWASP dependency-check, `cargo audit`, `pip-audit`, `govulncheck`? → A: No.
  Each is a separate install, OWASP needs an NVD key and minutes per run, and osv-scanner
  already reads every one of these ecosystems from its lockfile. One optional tool, one install
  hint. The coverage pass makes its absence visible per manifest.
- Q: Should an unchecked manifest make the run exit 1? → A: No. Exit 1 means findings to act on
  and existing callers (`project-maintenance.sh`) treat it that way. Not-scanned already has its
  own RESULT line; the pass joins it.
- Q: Parse osv-scanner's output to prove which files it scanned? → A: No. Its text format is not
  a contract. The lockfile rule is derived from osv-scanner's documented supported-files list,
  and the rule is what the harness pins.
- Q: List package.json / .csproj in the coverage pass too? → A: No; passes 3 and 5 already print
  a line per manifest. Repeating them would double the noise without adding a verdict.

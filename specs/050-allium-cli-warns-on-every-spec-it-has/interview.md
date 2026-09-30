# Spec interview — 050-allium-cli-warns-on-every-spec-it-has

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. Spec-only, no hardening trigger, so no overflow.

## Q1 — Scope boundary
**Q:** What is in, what is out?
**A (auto):** In: a version note in `allium-check-hook.sh`, its test arms, the allium skill's hint
and F089 guidance, the allium rule's Validation text, the install line in `sync-prompt.md`, and an
upstream issue draft. Out: rewriting product specs, upgrading the installed CLI, filing upstream.

## Q2 — Primary actor
**Q:** Who is hurt today?
**A (auto):** An agent reading `allium check` output in a project whose CLI predates 3.3.0. Every
spec warns, so warnings get skipped wholesale (ighweld F080). Second: an agent that follows the
skill's example and writes a bare `deferred`, which warns correctly on any CLI.

## Q3 — Happy path
**Q:** What does done look like?
**A (auto):** On a pre-3.3 CLI, the first `.allium` write of a session carries one model-facing
note: "allium 3.2.3 is older than 3.3.0; its deferred location-hint lint cannot be satisfied —
upgrade". On 3.3.0+, nothing new appears, and a `deferred X -- see: path` line written from the
skill's example checks clean.

## Q4 — Is the lint really unsatisfiable, or did ighweld miss a spelling?
**Q:** Before blaming the CLI, is there a spelling 3.2.3 accepts?
**A (auto):** No. Twelve spellings tried on 3.2.3, including the documented `-- see:`. All warn or
fail to parse. Upstream's parity doc §6 explains why: the old checker read the parsed path, which
drops comments.

## Q5 — Version floor
**Q:** Which version is the floor?
**A (auto):** 3.3.0, the first release where `-- see:` satisfies the lint (3.2.4 still warns;
3.3.0, 3.4.0, 3.5.0, 3.6.1 do not).

## Q6 — Version parsing
**Q:** How is the version read, and what if it cannot be?
**A (auto):** `$ALLIUM_BIN --version`, first line, first `N.N.N`. No match → no note (FR-02). The
note is advice; a missing verdict must not be turned into a false one.

## Q7 — The four observable states
**Q:** Success / error / empty / loading for a hook?
**A (auto):** Success: silent on a current CLI and a clean file. Error: block JSON with `line:col`
lines, unchanged. Empty: not a `.allium` file or missing file → silent, unchanged. Loading: N/A for
a synchronous hook; the existing timeout arm covers a hung CLI.

## Q8 — Output channel
**Q:** Who is the note for?
**A (auto):** The model, via `notice_once` (additionalContext). The developer sees nothing new. That
follows `hook-notice.sh`'s rule that an advisory for the model does not go on the person's channel.

## Q9 — Two JSON objects
**Q:** What if the CLI is old and the file also has errors?
**A (auto):** The note is appended to the block reason. The hook prints one JSON object (FR-03).

## Q10 — Frequency
**Q:** Once per session, or every write?
**A (auto):** Once per session, keyed `allium-cli-old`. A block reason carries it every time because
a block is rare and the model is already reading that output.

## Q11 — Performance
**Q:** Does an extra `--version` call cost anything that matters?
**A (auto):** One fork per `.allium` write, milliseconds. Skipping it after the first notice would
need a second state key and saves nothing measurable. YAGNI.

## Q12 — Cross-platform
**Q:** Does the parse work under macOS bash 3.2, Linux and Git Bash?
**A (auto):** `sed -n` with a POSIX bracket expression and `read` into three variables. No `=~`, no
`${x,,}`, no associative arrays.

## Q13 — F089 root cause
**Q:** Is F089 the binding form, as ighweld read it?
**A (auto):** No. Measured: it needs two entities sharing a field name plus an untyped trigger
parameter. One entity, or distinct names, is clean on 3.2.3 and 3.6.1.

## Q14 — F089 workaround
**Q:** Which workaround does the skill teach?
**A (auto):** Distinct field names per entity. It works on every version and needs no undocumented
syntax. The typed-`provides` form that silences it on 3.6.1 is not in the language reference, and
the skill already forbids typed trigger params.

## Q15 — Existing product specs
**Q:** Do we rewrite ighweld's 116 warning lines?
**A (auto):** No, that belongs to the product repo. The skill now names the spelling, so the next
edit of each spec fixes its own lines.

## Q16 — Upstream
**Q:** File F089 on juxt/allium-tools?
**A (auto):** Draft it in the spec dir with the minimal repro. Filing is outward-facing, so it waits
for the developer.

## Q17 — Acceptance criteria
**Q:** What proves it?
**A (auto):** Test arms: an old fake CLI → one note and validation unchanged; the same note is not
repeated in-session; a current fake CLI → no note; an unparseable version → no note; old CLI plus
errors → one JSON with both. Real 3.6.1 binary on the skill's new example → no location-hint warning.
Sabotage: flip the comparison and the old/new arms must go red.

## Q18 — Reversibility
**Q:** Rollback?
**A (auto):** One revert. No state beyond a per-session notice stamp in TMPDIR.

## Q19 — Non-goals and assumptions
**Q:** What is assumed?
**A (auto):** The `allium N.N.N (…)` version line is stable across 3.x (true for 3.2.3 → 3.6.1). If
it changes, FR-02 makes the note go quiet instead of wrong.

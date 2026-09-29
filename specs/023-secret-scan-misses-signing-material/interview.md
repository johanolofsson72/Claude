# Spec interview — 023-secret-scan-misses-signing-material

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO with human overflow (hardened: secrets risk domain and the `[hardened]` tag). The
developer answered Q1–Q3 on 2026-09-29.

## Q1 — Encrypted key material (overflow, threat surface)
**Q:** Is a Data Protection key with `<encryptedSecret>`, or a passphrase-encrypted PEM, a finding or a note?
**A:** A note. It is usable only if the wrapping key leaks as well.

## Q2 — Suppressing fixtures (overflow, threat surface)
**Q:** How does a project silence a known-harmless hit?
**A:** Through the `.secret-shapes-allow` file at the root, one `<glob>  # <reason>` per line. A line with no reason is ignored and warned about. Allowed hits print as `[ALLOWED]`.

## Q3 — History-only keys (overflow)
**Q:** Does a key that exists only in history fail the pass?
**A:** Yes. It is a finding labelled "history only", and the remedy is rotation because untracking does not un-leak it.

## Q4 — Scope boundary
**Q:** Which families are in?
**A (auto):** The families the filing named: Data Protection XML, PEM/PKCS#1/PKCS#8/EC/DSA/OpenSSH private keys, and `.pfx`/`.p12`. `.snk` and JKS are out (non-goals).

## Q5 — Where it lives
**Q:** A new script, or an arm of `project-freshness.sh`?
**A (auto):** An arm of `project-freshness.sh`, inside the `--secrets` scope. The finding was that this script's SUMMARY lies, so the fix belongs in the same place.

## Q6 — Dependency on trufflehog
**Q:** Does the shape arm run when trufflehog is missing?
**A (auto):** Yes. It needs only git, awk and grep, and it is the half that works offline.

## Q7 — History depth
**Q:** HEAD, or all refs?
**A (auto):** All refs (`rev-list --all`). Both real cases are history-only.

## Q8 — Name vs content
**Q:** Match by name, by content, or both?
**A (auto):** Both. Names catch binary containers and renamed key rings. Content (pickaxe) catches keys pasted into config or code.

## Q9 — False-positive guard
**Q:** How is a marker string in a test told apart from a key?
**A (auto):** By a body of at least 120 base64 characters. The smallest real key (EC P-256 SEC1) has about 164. rocky's marker-only fixtures fall under it.

## Q10 — Public certificates
**Q:** Is a `.pem` holding only `BEGIN CERTIFICATE` flagged?
**A (auto):** No. Name candidates are still classified by content, and a certificate is public (fundit's `cert.pem`).

## Q11 — Output safety
**Q:** What may the report print?
**A (auto):** Path, label, location, commit and date. Never bytes of the key (FR-06), and a test enforces it.

## Q12 — Error / empty / success states
**Q:** What does each state look like?
**A (auto):** Success: `[OK] no key material in history or working tree`. Finding: a `[FINDING]` line per path plus the remedy, exit 1. Empty repo or no commits: the scan still runs the untracked and non-git arms, and says what it looked at. Git failure: `[WARN] … not scanned`, and the SUMMARY says unscanned, never clean.

## Q13 — Dedup
**Q:** A key that changed ten times in history: how many lines?
**A (auto):** One per path, and the worst verdict wins.

## Q14 — Location label
**Q:** How is "history only" decided?
**A (auto):** The path is not in `git ls-files`. The add commit comes from `git log --all --diff-filter=A -1`.

## Q15 — Large blobs
**Q:** What happens with a 500 MB `.key`?
**A (auto):** It is not read. It becomes a NOTE, "not inspected (> 1 MiB)", sized with `git cat-file -s`.

## Q16 — Paths with spaces
**Q:** Must `My Project/~BROMIUM/x.pfx` work?
**A (auto):** Yes, it is in ighweld. Read with `IFS= read -r`, and cut the first field from rev-list output with a parameter expansion, never `awk '{print $2}'`.

## Q17 — Cross-platform
**Q:** Which awk and bash?
**A (auto):** bash 3.2 and POSIX awk (BWK awk on macOS, gawk on Git Bash and Linux). No gensub or IGNORECASE, and `LC_ALL=C` on every awk call.

## Q18 — Exit code interplay
**Q:** Does a shape FINDING use the same exit 1 as the other findings?
**A (auto):** Yes. Exit 2 stays reserved for a failed `--fix`.

## Q19 — Test seam
**Q:** How does the self-test avoid running the real trufflehog?
**A (auto):** `FRESHNESS_TRUFFLEHOG` names the binary, the same as the osv and dotnet seams.

## Q20 — Reversibility
**Q:** How is this undone?
**A (auto):** It is additive. Revert the commit. Projects receive it through autosync, and the allow file is theirs.

# 023 — secret scan misses signing material

Track: full [hardened]. Hardened by the register tag and by the risk domain (secrets). No entity and
no state machine. The new surface is a local scanner that reads git history and prints paths.

Filed 2026-09-03 (commit 4bd4ef9): "Two of seven projects commit an ASP.NET Data Protection key, and
project-freshness.sh reports 'no verified secrets' on both."

## What was measured (2026-09-29, 99 repos under ~/repos)

1. **The two repos are consultpilot and ighweld-web-license.** Both committed a Data Protection key
   file (`key-<guid>.xml`). Both untracked it on 2026-09-03 (consultpilot 9ee33d7, ighweld-web-license
   d09d244). Both keys are **still in git history**. The consultpilot key holds its master key in
   plaintext (`<!-- Warning: the key below is in an unencrypted form. -->`) and does not expire until
   2026-10-29.
2. **trufflehog is not wrong, it answers a different question.** `--only-verified` keeps only
   credentials it can check against a provider. An XML key ring, a `.pfx` and an unregistered private
   key match no provider, so the pass prints `[OK] No verified secrets in git history.` The SUMMARY
   then says `Secrets: clean`, which a reader takes to mean "no secrets in this repo".
3. **Other signing material in the fleet, same blind spot:** `.pfx` files in fundit (both copies),
   ighweld, ighweld-2026 (ClickOnce temporary keys) and learnways-sll (a real certificate for an
   `sll.se` host). fundit's `cert.pem` is a public certificate only, so it must **not** be flagged.
4. **Fixtures exist.** rocky has five files with PEM private-key markers in tests and a spec. Most
   are marker strings with no key body behind them. noisycricket-open-fundit has a service-account
   JSON template whose `private_key` is empty, so it must not be flagged either.
5. **Cost.** A pickaxe search for PEM markers over all of rocky's 2683 commits takes 5.8 s. That is
   acceptable for a maintenance pass that already runs trufflehog.

## Decision

Add a second, independent arm to the secrets scope of `project-freshness.sh`: a **key-shape scan**.
It matches key material by file name and content shape, not by verifiability. It covers the whole
git history, not only HEAD. It never prints key bytes. It runs whether or not trufflehog is
installed, because it needs only git, grep and awk.

## Functional requirements

- **FR-01** In the `--secrets` scope (and the default run), a pass `key-shape scan` runs after
  trufflehog. It needs only git, grep, tr and awk. A missing trufflehog does not skip it.
- **FR-02** Candidates in a git repo:
  - every blob reachable from any ref (`rev-list --all --objects` plus `log --all --raw`, so a blob
    counts at every path it ever had) whose path has a key-shaped name;
  - every blob of every path that a pickaxe search (`log --all -G`) finds with a content marker;
  - every staged blob;
  - every untracked, not-ignored file.
  A flagged blob is then reported at every path it ever had, so a renamed key is found under its
  new name as well. When a `.gitattributes` switches diffs off (`-diff`, `binary`, `diff=`), the
  pickaxe runs with `--text`. Outside git, the candidates are a `find` over the working tree,
  relative to the root, with the deps walk's structural exclusions.
- **FR-03** Key-shaped names: `key-<guid>.xml`, `*.pem`, `*.key`, `*.pfx`, `*.p12`, `*.ppk`, and
  `id_rsa` / `id_dsa` / `id_ecdsa` / `id_ed25519`. The match is case-insensitive. The content
  markers are `BEGIN … PRIVATE KEY`, `<masterKey`, `PuTTY-User-Key-File-`, and `LS0tLS1CRUdJTi`
  (base64 of `-----BEGIN`).
- **FR-04** Classification is by content, and the verdict is FINDING, NOTE or nothing. JSON, C# and
  PHP escapes (`\n`, `\r`, `\/`, `\u002B`, `\u002F`, `\u003D`) and CRLF are decoded first. A key
  body is the text between a BEGIN marker and its END marker (or the contiguous base64 run when there
  is no END). It is measured as the sum of its base64 tokens of 40 or more characters, so comment
  prefixes do not break a body and prose never adds up to one.
  - Data Protection: `<masterKey` with a `<value>` whose body is 40 or more is a FINDING. `<masterKey`
    with `<encryptedSecret` inside a `<key id=…>` ring is a NOTE.
  - PEM `BEGIN <T> PRIVATE KEY` with a body of 60 or more is a FINDING, labelled RSA / EC / DSA /
    PKCS#8 / other. The floor is 60 because an Ed25519 PKCS#8 body is 64. It is a NOTE when the key is
    passphrase-encrypted: `ENCRYPTED PRIVATE KEY`, a `Proc-Type: 4,ENCRYPTED` header, or `DEK-Info:`.
    Any other header text does not count.
  - OpenSSH is a FINDING when its body starts with the base64 of `openssh-key-v1\0` + cipher `none`,
    and a NOTE otherwise.
  - `PGP PRIVATE KEY BLOCK` is a FINDING.
  - PuTTY (`Private-Lines:` present) is a FINDING with `Encryption: none`, and a NOTE otherwise.
  - A base64-wrapped PEM of 150 characters or more whose prefix encodes a private-key BEGIN marker
    is a FINDING, and a NOTE for the ENCRYPTED one. A wrapped certificate is nothing.
  - `*.pfx` / `*.p12` is a FINDING by name, but only for a blob (never a directory).
  - A non-empty binary blob under a `.key`, `.pem`, `.ppk` or `id_*` name is a NOTE (DER).
  - A missing object (shallow or partial clone) is a NOTE, "not inspected".
  - **There is no size gate.** Every blob streams through one `git cat-file --batch` into one awk,
    which buffers only up to 200 lines after a marker, capped at 64 KiB per object. Padding a key
    therefore cannot turn it into a NOTE.
- **FR-05** One line per path. The worst verdict wins, and a live copy wins over history. Location
  is decided per **blob**, not per path:
  - `at HEAD` means this blob is at this path in HEAD's tree;
  - `staged, not committed`;
  - `untracked (not ignored)`, or `working tree` outside git;
  - otherwise `history only (untracked at HEAD; added <sha> <date>)`, or `history only (the path is
    tracked; this content is not at HEAD; …)` for a key that was scrubbed from a file that still
    exists. `added` comes from `--find-object` and is looked up for the first 20 history hits.
  A history-only key is still a FINDING (developer decision Q3).
- **FR-06** No output line ever contains key bytes. The PEM type label is whitelisted, so it cannot
  carry arbitrary text either. Control characters in printed paths and reasons are shown as `?`.
- **FR-07** Allow file `.secret-shapes-allow` at the project root, read from the working tree. Each
  line is `<path-glob>  # <reason>`. A matching hit prints as `[ALLOWED] <path> — … — <reason>` and
  does not count. A line whose reason is missing or blank is ignored, and a `[WARN]` names its line
  number. Blank lines and `#` lines are comments.
- **FR-08** A FINDING sets the exit code to 1. The pass prints the remedy: rotate the key, because
  untracking does not un-leak it. For a Data Protection key it also says to move the key ring out of
  the repo. A history purge is optional and comes after rotation.
- **FR-09** The SUMMARY has `Secrets:` (trufflehog, now worded as "no *verified credentials*") and
  `Keys:` (the shape scan, with its counts). A scan that could not complete (a git failure, a
  shallow clone) prints `[WARN] … incomplete` and `Keys: INCOMPLETE`. Whenever trufflehog or the
  key scan did not run to completion, the RESULT line says `NOT SCANNED`, never `clean`.
- **FR-10** Test seam `FRESHNESS_TRUFFLEHOG` names the trufflehog binary. A seam-named binary is never
  self-installed.

## Non-goals

`.snk` strong-name keys (routinely committed on purpose by open-source .NET), JKS/keystore, `.der`
containers other than the binary NOTE, cloud credential JSON without a PEM body, content that exists
only in a merge resolution (the pickaxe skips merge diffs), Git LFS pointers (the object is not in
git), submodule contents, and paths containing a newline. The per-edit
`local-llm-secret-scan-hook.sh` is unchanged (it stays unwired, row 020). Rotating the keys found is
the projects' work, not this spec's.

## Threat model

Trust boundary: the scanned repository's history and working tree, including its
`.secret-shapes-allow`. Whoever controls the repo may be careless, or may want a clean report.

- **S** — none. There is no identity. The scan runs as the local developer.
- **T** — the allow file can silence anything (`*  # fine`). Mitigation: every allowed hit is still
  printed with its reason, and the SUMMARY counts allowed hits, so suppression is never silent. A
  line with no reason is ignored. The repo can also try to hide a file from the pickaxe with
  `.gitattributes` (FR-02: then it diffs as text), pad a key past a size limit (FR-04: there is no
  limit), or add a header saying `ENCRYPTED` (FR-04: only Proc-Type and DEK-Info count).
- **R** — the allow file is git-tracked, so who allowed what and when is in `git log`.
- **I** — the report itself could leak the key: output is pasted into chats, logs and PR comments.
  Mitigation: FR-06. Only metadata is printed, and a test asserts that key bytes never appear.
- **D** — huge blobs, huge histories, pathological files. Mitigation: one `cat-file --batch` and one
  awk for all candidates; per object, a capture window of at most 200 lines and 64 KiB; at most 64
  markers per object. Pickaxe cost is linear in history: 29 s on fundit's 197 MB `.git`, and 70 s
  with `--text`, which is why `--text` is used only when a `.gitattributes` asks for it. The stress
  run (2000 distinct certificates, 300 commits, a 20 MB single line) takes 4.2 s at 178 MB RSS.
- **E** — file names come from git and the working tree and pass through shell variables. They are
  always quoted and never `eval`'d. Git output is `-z` and becomes one line per path. Internal files
  keep the path as the last field, so a tab cannot shift a verdict. Grep file arguments follow `--`.
  Awk never receives a path as an argument (it reads the batch stream), so `a=b` is not an
  assignment. The allow globs are used as `case` patterns (the project's own), never evaluated.
  Terminal control characters are neutralised on output (FR-06).

## Acceptance

- `test-project-freshness.sh` passes, with key cases K1–K28 covering every FR. They include
  negatives (public cert, empty template, marker-only fixture, prose, wrapped certificate, a 250 KB
  text bundle), every verdict family, allow and no-reason, odd names (spaces, non-ASCII, tab, `-q`,
  `a=b`, ESC, a directory named `.pfx`), history-only, scrubbed and renamed keys, staged, untracked,
  non-git, `.gitattributes -diff`, a broken ref, a shallow clone, and the FR-06 leak assertion
  (including real `ssh-keygen` and `openssl` keys). Thirty sabotage arms, one per defence, must each
  turn the suite red.
- A live run reports consultpilot's and ighweld-web-license's Data Protection keys as `history only`
  FINDINGs, reports fundit's `.pfx` and not its `cert.pem`, and finds this template repo clean.

## Clarifications

### Session 2026-09-29

- Q: encrypted key material → A: NOTE, not FINDING (developer).
- Q: suppressing fixtures → A: `.secret-shapes-allow`, reason required (developer).
- Q: history-only keys → A: FINDING labelled history only (developer).
- Q: OpenSSH encryption test → A (auto): body prefix `b3BlbnNzaC1rZXktdjEAAAAABG5vbmU` (base64 of
  `openssh-key-v1\0` + cipher `none`). Checked against ssh-keygen: ed25519 and rsa without a
  passphrase carry it, ed25519 with one does not (`…CmFlczI1Ni1jdHI…`, aes256-ctr).
- Q: Allium → A (auto): skipped. There is no entity and no state machine, just a pure classifier
  from blob to verdict. Its rules are expressed as test cases, per the triage table's "express the
  constraint as a test".

### Review round 2026-09-29 (code review + adversarial security review + stress)

- Location per blob, not per path (the review's must-fix #2). K10 used to assert a bug.
- Staged blobs, honest RESULT (`NOT SCANNED`), shallow clone reported as incomplete, and missing
  objects reported as NOTEs, never dropped.
- Threshold 120 → 60 in 40+ tokens, because an Ed25519 PKCS#8 key has 64 characters and was missed.
  The body is now bounded by the END marker, so comment prefixes do not break it.
- New arms: escape decoding (`\u002B`, `\/`), base64-wrapped PEM, PGP, PuTTY.
- The 1 MiB NOTE gate was removed (padding downgraded a key). Replaced by streaming through one
  `cat-file --batch` into one awk, bounded by a capture window. This also fixed a SIGPIPE false
  "binary" NOTE and cut 2000 candidates from 158 s to 4.2 s.
- `-z` everywhere, path last in internal files, `--` before grep files, terminal sanitising,
  directories named `*.pfx` skipped, `--text` under `.gitattributes -diff`, and `find` relative to
  the root.

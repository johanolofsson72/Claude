---- MODULE SandboxInterlock ----
\* 010 (landed from consultpilot H7bm) — the sandbox interlock in scripts/template-autosync.sh.
\*
\* The property under verification is not "does the check compare paths correctly" — a shell test
\* answers that better than TLC can. It is ORDERING: is there any reachable path through this
\* script's phases on which a write, stage, commit or push happens without the interlock having
\* first agreed? The 2026-08-30 incident was exactly such a path, and it existed because nobody had
\* drawn the machine.
\*
\* The nine environment booleans are fixed at Init, because that is what they are in a run: the caller's environment does not change under the script's feet. The one place
\* they can change mid-run — a symlink swapped between the check and the writes — is deliberately
\* NOT modelled; it is recorded in the spec's threat model as accepted (it needs local filesystem
\* race capability, a different threat model from the misconfiguration this row targets), and
\* modelling it here would prove a violation everyone already agreed to live with.

EXTENDS Naturals

\* The environment is chosen NON-DETERMINISTICALLY at Init and never changes, so one TLC run
\* explores all 2^9 = 512 environments rather than the single assignment a CONSTANTS block would
\* pin. That matters here: the incident was one particular environment nobody had thought to try.
\*
\*   Declared      CLAUDE_TEMPLATE_SYNC_SANDBOX is set (spec 010: an empty value counts)
\*   SbxExists     ...and names an existing directory (false for an empty value)
\*   SbxIsRoot     ...and that directory is "/"
\*   RootInside    the resolved project root is inside the declared sandbox
\*   IsCore        the run is --is-core (returns above project-root resolution)
\*   InGitRepo     a project root was found at all
\*   HasClaudeDir  the project root has .claude/
\*   WillCommit    the mode commits (not --check/--dry-run/--no-commit)
\*   HasUpstream   there is an upstream to push to

VARIABLES phase, wrote,
          Declared, SbxExists, SbxIsRoot, RootInside, IsCore,
          InGitRepo, HasClaudeDir, WillCommit, HasUpstream

env  == <<Declared, SbxExists, SbxIsRoot, RootInside, IsCore,
          InGitRepo, HasClaudeDir, WillCommit, HasUpstream>>
vars == <<phase, wrote, Declared, SbxExists, SbxIsRoot, RootInside, IsCore,
          InGitRepo, HasClaudeDir, WillCommit, HasUpstream>>

Phases == {"started", "resolved", "verified", "refused",
           "writing", "committed", "pushed", "finished"}

TypeOK ==
    /\ phase \in Phases
    /\ wrote \in BOOLEAN
    /\ \A b \in {Declared, SbxExists, SbxIsRoot, RootInside, IsCore,
                 InGitRepo, HasClaudeDir, WillCommit, HasUpstream} : b \in BOOLEAN

\* "/" is an existing directory, always. A model in which SbxIsRoot holds while SbxExists does not
\* would let TLC "prove" the root case safe through a state the filesystem cannot produce.
EnvConsistent == SbxIsRoot => SbxExists

Init ==
    /\ phase = "started"
    /\ wrote = FALSE
    /\ Declared \in BOOLEAN     /\ SbxExists \in BOOLEAN
    /\ SbxIsRoot \in BOOLEAN    /\ RootInside \in BOOLEAN
    /\ IsCore \in BOOLEAN       /\ InGitRepo \in BOOLEAN
    /\ HasClaudeDir \in BOOLEAN /\ WillCommit \in BOOLEAN
    /\ HasUpstream \in BOOLEAN
    /\ EnvConsistent

\* --is-core returns above the project-root resolution (template-autosync.sh:531 < 536).
\* It never resolves a root, so it can never write.
IsCoreReturns ==
    /\ phase = "started"
    /\ IsCore
    /\ phase' = "finished"
    /\ UNCHANGED <<wrote, env>>

\* Not in a git repository: the pre-existing quiet skip. Exit 0, nothing written. The interlock
\* must not turn this into a hard failure — the SessionStart hook runs in whatever directory a
\* session opens in.
SkipNoRepo ==
    /\ phase = "started"
    /\ ~IsCore
    /\ ~InGitRepo
    /\ phase' = "finished"
    /\ UNCHANGED <<wrote, env>>

ResolveRoot ==
    /\ phase = "started"
    /\ ~IsCore
    /\ InGitRepo
    /\ phase' = "resolved"
    /\ UNCHANGED <<wrote, env>>

\* THE INTERLOCK. Three ways to leave "resolved", and they are exhaustive by construction:
\* the declaration is unusable, the root is outside it, or it is fine.
RefuseUnusable ==
    /\ phase = "resolved"
    /\ Declared
    /\ ~SbxExists
    /\ phase' = "refused"
    /\ UNCHANGED <<wrote, env>>

\* The finding the adversarial review produced: "/" is an existing directory, so the first
\* implementation accepted it — and every path is inside "/", so the interlock reported that it had
\* verified a sandbox while permitting exactly what it exists to prevent.
RefuseRoot ==
    /\ phase = "resolved"
    /\ Declared
    /\ SbxExists
    /\ SbxIsRoot
    /\ phase' = "refused"
    /\ UNCHANGED <<wrote, env>>

RefuseOutside ==
    /\ phase = "resolved"
    /\ Declared
    /\ SbxExists
    /\ ~SbxIsRoot
    /\ ~RootInside
    /\ phase' = "refused"
    /\ UNCHANGED <<wrote, env>>

Verify ==
    /\ phase = "resolved"
    /\ (~Declared \/ (SbxExists /\ ~SbxIsRoot /\ RootInside))
    /\ phase' = "verified"
    /\ UNCHANGED <<wrote, env>>

\* The .claude/ skip sits below the interlock, so a mismatch refuses even when the wrongly-resolved
\* repository happens to lack .claude/.
SkipNoClaude ==
    /\ phase = "verified"
    /\ ~HasClaudeDir
    /\ phase' = "finished"
    /\ UNCHANGED <<wrote, env>>

Write ==
    /\ phase = "verified"
    /\ HasClaudeDir
    /\ phase' = "writing"
    /\ wrote' = TRUE
    /\ UNCHANGED env

StopAfterWrite ==      \* --no-commit
    /\ phase = "writing"
    /\ ~WillCommit
    /\ phase' = "finished"
    /\ UNCHANGED <<wrote, env>>

Commit ==
    /\ phase = "writing"
    /\ WillCommit
    /\ phase' = "committed"
    /\ UNCHANGED <<wrote, env>>

StopAfterCommit ==     \* no upstream
    /\ phase = "committed"
    /\ ~HasUpstream
    /\ phase' = "finished"
    /\ UNCHANGED <<wrote, env>>

Push ==
    /\ phase = "committed"
    /\ HasUpstream
    /\ phase' = "pushed"
    /\ UNCHANGED <<wrote, env>>

Done ==
    /\ phase = "pushed"
    /\ phase' = "finished"
    /\ UNCHANGED <<wrote, env>>

Terminal ==            \* stutter in the absorbing states so TLC's deadlock check stays meaningful
    /\ phase \in {"finished", "refused"}
    /\ UNCHANGED vars

Next ==
    \/ IsCoreReturns \/ SkipNoRepo \/ ResolveRoot
    \/ RefuseUnusable \/ RefuseRoot \/ RefuseOutside \/ Verify
    \/ SkipNoClaude \/ Write
    \/ StopAfterWrite \/ Commit \/ StopAfterCommit \/ Push \/ Done
    \/ Terminal

Spec == Init /\ [][Next]_vars /\ WF_vars(Next)

\* ---------------------------------------------------------------- safety

\* THE property this row exists for. A declared run may only have written if the root really was
\* inside a usable, non-root sandbox.
NoWriteOutsideADeclaredSandbox ==
    (wrote /\ Declared) => (SbxExists /\ ~SbxIsRoot /\ RootInside)

\* A refusal must be a refusal: nothing written, ever, on that path.
RefusalPrecedesEveryWrite ==
    (phase = "refused") => ~wrote

\* --is-core pays nothing and writes nothing. It is called from a PreToolUse hook before every edit.
IsCoreNeverWrites ==
    IsCore => ~wrote

\* FR-006, the load-bearing non-event: an undeclared run must be able to reach every phase it could
\* reach before this row existed. Stated as "the interlock never refuses an undeclared run".
UndeclaredIsNeverRefused ==
    (phase = "refused") => Declared

\* The pre-existing quiet skips stay quiet — they end at "finished", never at "refused".
QuietSkipsStayQuiet ==
    ((~InGitRepo \/ ~HasClaudeDir) /\ ~Declared) => (phase # "refused")

\* ---------------------------------------------------------------- liveness

\* No run gets stuck: every behaviour reaches an absorbing state.
EventuallyTerminates == <>(phase \in {"finished", "refused"})

====

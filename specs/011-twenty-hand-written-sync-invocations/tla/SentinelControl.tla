---- MODULE SentinelControl ----
\* CONTROL (must FAIL): the design rejected in interview Q18. An EMPTY sandbox on the writing entry
\* point is read as "nothing to constrain" and the run starts — nothing checks argv. Same invariants.
\* 011 — one way in: scripts/drive-sync.sh. Ported from consultpilot H7bo's OneWayIn, with the two
\* template differences modelled rather than assumed:
\*
\*   - the write-free proof is ANY of four query modes in argv, not --is-core alone;
\*   - a sandbox that CONTAINS the helper's own repository is refused. consultpilot added that check
\*     after its model was written, so its model never covered it. Here it is a ninth fact.
\*
\* WHAT IS WORTH CHECKING. The phase machine is trivial (called -> refused | running -> finished).
\* The predicate space in front of it is not: nine independent facts about the arguments and the entry
\* point, and the question whether any of the 2^9 combinations lets a run start with a sandbox that
\* does not constrain it. That is the 2026-08-30 incident's shape — one environment nobody tried —
\* which is why the booleans are chosen at Init: one run covers all 512.

EXTENDS Naturals

VARIABLES
  ProjOk,          \* project exists and is a directory
  SbxNonEmpty,     \* the sandbox argument is a non-empty string
  SbxAbsolute,     \* ...and starts with /
  SbxIsRoot,       \* ...and is exactly "/"
  SbxExists,       \* ...and names an existing directory
  SbxHoldsRepo,    \* ...and physically contains the helper's own repository ($HOME, the parent)
  ScriptOk,        \* DRIVE_SYNC_SCRIPT is set, exists and is readable
  ReadOnlyEntry,   \* the call went to drive_sync_readonly rather than drive_sync
  ArgvHasQuery,    \* one of --is-core, --list-core-scripts, --list-core-rules, --template-dir

  phase,           \* called | refused | running | finished
  started,         \* did a sync process actually start
  sandboxInForce   \* did that process run under a sandbox that constrains it

env == <<ProjOk, SbxNonEmpty, SbxAbsolute, SbxIsRoot, SbxExists, SbxHoldsRepo, ScriptOk,
         ReadOnlyEntry, ArgvHasQuery>>
vars == <<phase, started, sandboxInForce, env>>

TypeOk ==
  /\ ProjOk \in BOOLEAN /\ SbxNonEmpty \in BOOLEAN /\ SbxAbsolute \in BOOLEAN
  /\ SbxIsRoot \in BOOLEAN /\ SbxExists \in BOOLEAN /\ SbxHoldsRepo \in BOOLEAN
  /\ ScriptOk \in BOOLEAN /\ ReadOnlyEntry \in BOOLEAN /\ ArgvHasQuery \in BOOLEAN
  /\ phase \in {"called", "refused", "running", "finished"}
  /\ started \in BOOLEAN /\ sandboxInForce \in BOOLEAN

\* The helper's sandbox validation, as drive-sync.sh spells it. `/` is refused explicitly, and so is
\* every other ancestor of the repository: each satisfies "absolute and existing" while permitting
\* writes to the repository the interlock exists to protect.
SandboxUsable ==
  /\ SbxNonEmpty /\ SbxAbsolute /\ ~SbxIsRoot /\ SbxExists /\ ~SbxHoldsRepo

\* A run that cannot write: the four query modes return above the project-root resolution in
\* template-autosync.sh (asserted per mode by test-validate-sync-sandbox-declarations.sh AC-12/12b).
CannotWrite == ArgvHasQuery

Init ==
  /\ ProjOk \in BOOLEAN /\ SbxNonEmpty \in BOOLEAN /\ SbxAbsolute \in BOOLEAN
  /\ SbxIsRoot \in BOOLEAN /\ SbxExists \in BOOLEAN /\ SbxHoldsRepo \in BOOLEAN
  /\ ScriptOk \in BOOLEAN /\ ReadOnlyEntry \in BOOLEAN /\ ArgvHasQuery \in BOOLEAN
  \* A filesystem cannot produce these, and a model that explores them proves things about nothing.
  /\ (SbxIsRoot => (SbxNonEmpty /\ SbxAbsolute /\ SbxExists /\ SbxHoldsRepo))
  /\ (SbxExists => (SbxNonEmpty /\ SbxAbsolute))
  /\ (SbxHoldsRepo => SbxExists)
  /\ phase = "called" /\ started = FALSE /\ sandboxInForce = FALSE

RefuseWriting ==
  /\ phase = "called" /\ ~ReadOnlyEntry
  /\ ~(ProjOk /\ SandboxUsable /\ ScriptOk)
  /\ phase' = "refused" /\ UNCHANGED <<started, sandboxInForce, env>>

RunWriting ==
  /\ phase = "called" /\ ~ReadOnlyEntry
  /\ ProjOk /\ SandboxUsable /\ ScriptOk
  /\ phase' = "running" /\ started' = TRUE /\ sandboxInForce' = TRUE
  /\ UNCHANGED env

\* The write-free entry point READS argv rather than trusting the caller (developer, Q18).
RefuseReadOnly ==
  /\ phase = "called" /\ ReadOnlyEntry
  /\ ~(ProjOk /\ ScriptOk /\ ArgvHasQuery)
  /\ phase' = "refused" /\ UNCHANGED <<started, sandboxInForce, env>>

RunReadOnly ==
  /\ phase = "called" /\ ReadOnlyEntry
  /\ ProjOk /\ ScriptOk /\ ArgvHasQuery
  /\ phase' = "running" /\ started' = TRUE /\ sandboxInForce' = FALSE
  /\ UNCHANGED env

Finish ==
  /\ phase = "running"
  /\ phase' = "finished" /\ UNCHANGED <<started, sandboxInForce, env>>

SentinelRun ==
  /\ phase = "called" /\ ~ReadOnlyEntry /\ ~SbxNonEmpty /\ ProjOk /\ ScriptOk
  /\ phase' = "running" /\ started' = TRUE /\ sandboxInForce' = FALSE /\ UNCHANGED env

Next == SentinelRun \/ RefuseWriting \/ RunWriting \/ RefuseReadOnly \/ RunReadOnly \/ Finish

Spec == Init /\ [][Next]_vars /\ WF_vars(Next)

\* THE property. Every started run is under a sandbox that constrains it, or provably cannot write.
NoUnconstrainedRun == started => (sandboxInForce \/ CannotWrite)

\* The two declarations that satisfy every presence check and bind nothing.
RootIsNeverASandbox == (started /\ sandboxInForce) => ~SbxIsRoot
RepoAncestorIsNeverASandbox == (started /\ sandboxInForce) => ~SbxHoldsRepo

\* A refusal starts nothing (the implementation also gives it exit 64, distinct from 0/1/2).
RefusalStartsNothing == (phase = "refused") => ~started

\* The write-free path is reachable only with the proof in argv, never by omitting a sandbox.
ReadOnlyNeedsItsProof == (started /\ ~sandboxInForce) => ArgvHasQuery

\* No environment leaves a call hanging.
Terminates == <>(phase = "refused" \/ phase = "finished")
====

---- MODULE ConfirmTrust ----
\* Spec 091 R8 + R9: can the gate open on a Confirmed line whose cases the developer never confirmed?
\*
\* Versions stand for case texts; a version's digest is the version itself. The agent edits the cases,
\* asks questions, writes the Confirmed line by a route no guard reads (a script file: F107), commits.
\* The developer answers: Confirm to the --question text of the cases on disk (approved, a ghost), or
\* No to anything else (an unrelated question that shows the digest: F104). Pushing is the developer's
\* route here; an agent pushing a forged line for real is the recorded residual.
\*   RECORD   "any"   a digest in the question binds whatever the answer (before 091)
\*            "canon" only Confirm, to the exact --question text of the cases on disk (R8)
\*   SHORTCUT "head"  a Confirmed line equal to HEAD's is trusted (before 091)
\*            "up"    only a line equal to the upstream's (R9)
EXTENDS FiniteSets

CONSTANTS Versions, RECORD, SHORTCUT

VARIABLES cases, bound, approved, line, head, up

vars == <<cases, bound, approved, line, head, up>>

None == "none"

Init ==
    /\ cases \in Versions
    /\ bound = {}  /\ approved = {}
    /\ line = None /\ head = None /\ up = None

AgentEdits(v) == /\ cases' = v /\ UNCHANGED <<bound, approved, line, head, up>>

\* The developer confirms the cases on disk, shown by --question.
DevConfirms ==
    /\ bound' = bound \cup {cases}
    /\ approved' = approved \cup {cases}
    /\ UNCHANGED <<cases, line, head, up>>

\* The developer says No to a question that shows digest v (any v the agent puts in the text).
DevSaysNo(v) ==
    /\ bound' = IF RECORD = "any" THEN bound \cup {v} ELSE bound
    /\ UNCHANGED <<cases, approved, line, head, up>>

\* --confirm writes the line only for a bound digest.
Confirm == /\ cases \in bound /\ line' = cases /\ UNCHANGED <<cases, bound, approved, head, up>>

\* A script file writes any line; no guard reads it.
Forge(v) == /\ line' = v /\ UNCHANGED <<cases, bound, approved, head, up>>

Commit == /\ head' = line /\ UNCHANGED <<cases, bound, approved, line, up>>

\* The developer pushes only what they confirmed.
DevPush == /\ head \in approved /\ up' = head /\ UNCHANGED <<cases, bound, approved, line, head>>

Next ==
    \/ \E v \in Versions : AgentEdits(v) \/ DevSaysNo(v) \/ Forge(v)
    \/ DevConfirms \/ Confirm \/ Commit \/ DevPush

Spec == Init /\ [][Next]_vars

Shortcut == IF SHORTCUT = "head" THEN head ELSE up

GateOpens == line = cases /\ (cases \in bound \/ Shortcut = line)

TypeOK == cases \in Versions /\ line \in Versions \cup {None}

NoUnconfirmedCode == GateOpens => cases \in approved
====

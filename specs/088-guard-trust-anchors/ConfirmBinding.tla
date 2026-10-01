---- MODULE ConfirmBinding ----
\* Spec 088 R3-R5: can the gated agent end with a Confirmed line the developer never approved?
\*
\* Versions stand for case texts; a version's digest is the version itself. The agent edits the cases,
\* asks questions whose text shows any set of digests it chooses, and runs --confirm. The developer
\* answers a question about the cases on disk at that moment (approved, a ghost variable). Writes of
\* the Confirmed line or the store by the agent's tools are denied by the guard (R3), so they are not
\* actions. FILTER models what the hook records from a question's digests:
\*   "all"    every 12-hex token in the question (the first implementation)
\*   "ondisk" only tokens equal to a digest of an acceptance.md on disk at answer time
EXTENDS FiniteSets

CONSTANTS Versions, FILTER

VARIABLES cases, words, approved, confirmed

vars == <<cases, words, approved, confirmed>>

Init ==
    /\ cases \in Versions
    /\ words = {}
    /\ approved = {}
    /\ confirmed = "none"

AgentEdits(v) ==
    /\ cases' = v
    /\ UNCHANGED <<words, approved, confirmed>>

\* The agent asks; the developer answers yes about the cases on disk. S is what the question text shows.
AskAndAnswer(S) ==
    /\ S # {}
    /\ words' = words \cup {IF FILTER = "all" THEN S ELSE S \cap {cases}}
    /\ approved' = approved \cup {cases}
    /\ UNCHANGED <<cases, confirmed>>

\* --confirm: writes only when some recorded answer carries the current digest (R5).
Confirm ==
    /\ \E w \in words : cases \in w
    /\ confirmed' = cases
    /\ UNCHANGED <<cases, words, approved>>

Next ==
    \/ \E v \in Versions : AgentEdits(v)
    \/ \E S \in SUBSET Versions : AskAndAnswer(S)
    \/ Confirm

Spec == Init /\ [][Next]_vars

TypeOK ==
    /\ cases \in Versions
    /\ confirmed \in Versions \cup {"none"}

\* The gate unlocks on a Confirmed line whose digest matches the cases. It must be a version the
\* developer was shown when they answered.
NoSelfConfirmation ==
    (confirmed # "none" /\ confirmed = cases) => confirmed \in approved
====

---- MODULE AnswerBinding ----
\* Spec 105 R9 (F173, developer O4): which Confirm answer may back which spec's Confirmed line.
\* The developer answers Confirm to ONE spec's question, showing that spec's cases. The agent may copy
\* cases between specs, edit them, or delete a spec. A Confirmed line counts when Bound(s) holds.
\*   RULE = "v1": pre-105, a token is a bare digest, matched by digest alone.
\*   RULE = "v2": R9, a token names its spec; a bare legacy token binds only while its digest is unique
\*                on disk (O4).
\* ALLOW_DELETE: whether the agent may delete a spec (the F264 window).
EXTENDS Naturals, FiniteSets
CONSTANTS Specs, Digests, RULE, ALLOW_DELETE
None == "none"
Bare == "bare"
VARIABLES cases, asked, confirmed, store
vars == <<cases, asked, confirmed, store>>

Token(d, s) == [d |-> d, s |-> s]
Carrying(d) == {t \in Specs : cases[t] = d}

Bound(s) ==
  LET d == cases[s] IN
    /\ d # None
    /\ IF RULE = "v1"
         THEN \E t \in Specs \cup {Bare} : Token(d, t) \in store
         ELSE \/ Token(d, s) \in store
              \/ (Token(d, Bare) \in store /\ Carrying(d) = {s})

\* One spec, A, was confirmed before R9: its answer is a bare legacy token.
Init ==
  \E a \in Specs, d \in Digests :
    /\ cases = [t \in Specs |-> IF t = a THEN d ELSE None]
    /\ asked = [t \in Specs |-> IF t = a THEN {d} ELSE {}]
    /\ confirmed = [t \in Specs |-> t = a]
    /\ store = {Token(d, Bare)}

\* The agent writes cases (a fresh draft, or a verbatim copy of another spec's). A Confirmed line whose
\* digest no longer matches is no confirmation.
Write(s, d) ==
  /\ cases' = [cases EXCEPT ![s] = d]
  /\ confirmed' = [confirmed EXCEPT ![s] = FALSE]
  /\ UNCHANGED <<asked, store>>

Delete(s) ==
  /\ ALLOW_DELETE
  /\ cases[s] # None
  /\ cases' = [cases EXCEPT ![s] = None]
  /\ confirmed' = [confirmed EXCEPT ![s] = FALSE]
  /\ UNCHANGED <<asked, store>>

\* The developer picks Confirm on s's own question (record_answers binds it to s under v2).
Answer(s) ==
  /\ cases[s] # None
  /\ asked' = [asked EXCEPT ![s] = @ \cup {cases[s]}]
  /\ store' = store \cup {IF RULE = "v1" THEN Token(cases[s], Bare) ELSE Token(cases[s], s)}
  /\ UNCHANGED <<cases, confirmed>>

\* --confirm writes the line only when the store backs it. v2: only a token naming s; a bare legacy token
\* keeps an existing line valid at the gate (Bound) but never writes a new one (found by TLC on the first
\* v2 model: copy B's cases to A, edit B, and A's digest is unique).
BoundToWrite(s) == IF RULE = "v1" THEN Bound(s) ELSE Token(cases[s], s) \in store

Confirm(s) ==
  /\ cases[s] # None
  /\ BoundToWrite(s)
  /\ confirmed' = [confirmed EXCEPT ![s] = TRUE]
  /\ UNCHANGED <<cases, asked, store>>

Next == \E s \in Specs : \/ \E d \in Digests : Write(s, d)
                         \/ Delete(s)
                         \/ Answer(s)
                         \/ Confirm(s)

Spec == Init /\ [][Next]_vars

TypeOK ==
  /\ cases \in [Specs -> Digests \cup {None}]
  /\ asked \in [Specs -> SUBSET Digests]
  /\ confirmed \in [Specs -> BOOLEAN]

\* A spec is confirmed only for cases the developer was shown FOR THAT SPEC (asked: every digest ever shown
\* in s's own question).
ConfirmedMeansAsked == \A s \in Specs : confirmed[s] => cases[s] \in asked[s]

\* The gate unlocks code for s when its line stands and the store backs it.
GateSafe == \A s \in Specs : (confirmed[s] /\ Bound(s)) => cases[s] \in asked[s]
====

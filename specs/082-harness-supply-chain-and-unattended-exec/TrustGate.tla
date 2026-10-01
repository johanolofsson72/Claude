---- MODULE TrustGate ----
\* Spec 082 R5 + adversarial finding 17: the unattended trust gate against a concurrent write to
\* the repository file. UseCopy = TRUE is the shipped design (hash a private copy, execute that copy:
\* ratchets, the mutation runner, the suite string held in one variable). UseCopy = FALSE is the
\* shape that still exists for `npm test`, which re-reads package.json after the hash check.
\* Safety: an unattended run only executes bytes whose hash is in the trust store.
EXTENDS Naturals

CONSTANTS UseCopy

VARIABLES repo, copy, pc, executed

vars == <<repo, copy, pc, executed>>
Trusted == {"good"}

Init == repo = "good" /\ copy = "none" /\ pc = "check" /\ executed = "none"

Write == pc /= "done" /\ repo' = "evil" /\ UNCHANGED <<copy, pc, executed>>

Check ==
  /\ pc = "check"
  /\ copy' = repo
  /\ pc' = IF repo \in Trusted THEN "run" ELSE "done"
  /\ UNCHANGED <<repo, executed>>

Run ==
  /\ pc = "run"
  /\ executed' = IF UseCopy THEN copy ELSE repo
  /\ pc' = "done"
  /\ UNCHANGED <<repo, copy>>

Next == Write \/ Check \/ Run \/ (pc = "done" /\ UNCHANGED vars)
Spec == Init /\ [][Next]_vars

OnlyTrustedRuns == executed \in Trusted \cup {"none"}
====

---- MODULE GitUnsure ----
\* Spec 098 R4: _guard_git classification and the guards' reaction.
EXTENDS Naturals
VARIABLES rc, guard, neededGit, exempt
Codes == {0, 1, 2, 124, 128, 129, 137, 142, 143}
vars == <<rc, guard, neededGit, exempt>>
Init == /\ rc \in Codes /\ guard \in {"pipeline", "core"} /\ neededGit \in BOOLEAN /\ exempt \in BOOLEAN
Next == UNCHANGED vars
Answered == rc \in {0, 1, 128, 129}
Unsure == neededGit /\ ~Answered
Verdict == IF guard = "pipeline"
             THEN (IF Unsure THEN "deny" ELSE IF exempt THEN "allow" ELSE "judge")
             ELSE (IF Unsure THEN "announce_allow" ELSE "judge")
\* Ground truth: a git killed or cut off told the walk nothing.
GitToldNothing == neededGit /\ rc \in {2, 124, 137, 142, 143}
PipelineNeverExemptsOnGuess == (guard = "pipeline" /\ GitToldNothing) => Verdict = "deny"
CoreNeverSilentOnGuess == (guard = "core" /\ GitToldNothing) => Verdict = "announce_allow"
CommonPathUnchanged == ~neededGit => Verdict # "announce_allow" /\ (guard = "pipeline" => Verdict # "deny")
====

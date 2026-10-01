---- MODULE PassLockOS ----
\* Spec 020 after GAP-1: an OS lock (flock / msvcrt.locking). Acquiring is one atomic try; the
\* kernel releases the lock when the holder finishes OR dies. No pid, no takeover step.
EXTENDS Naturals, FiniteSets
CONSTANT Procs
VARIABLES pc, holder
vars == <<pc, holder>>
None == 0
Init == pc = [p \in Procs |-> "idle"] /\ holder = None
TryLock(p) == /\ pc[p] = "idle"
              /\ IF holder = None THEN holder' = p /\ pc' = [pc EXCEPT ![p] = "running"]
                 ELSE pc' = [pc EXCEPT ![p] = "gone"] /\ UNCHANGED holder
Finish(p) == pc[p] = "running" /\ holder' = None /\ pc' = [pc EXCEPT ![p] = "gone"]
Crash(p)  == pc[p] = "running" /\ holder' = None /\ pc' = [pc EXCEPT ![p] = "dead"]   \* kernel releases
Respawn(p) == pc[p] \in {"dead", "gone"} /\ pc' = [pc EXCEPT ![p] = "idle"] /\ UNCHANGED holder
Next == \E p \in Procs : TryLock(p) \/ Finish(p) \/ Crash(p) \/ Respawn(p)
Mutex == Cardinality({p \in Procs : pc[p] = "running"}) <= 1
HolderRuns == holder # None => pc[holder] = "running"
Spec == Init /\ [][Next]_vars /\ WF_vars(\E p \in Procs : TryLock(p))
====

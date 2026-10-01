---- MODULE PassLock ----
\* Spec 020: the quality-gate pass lock as implemented: mkdir lock (atomic), else read the pid file;
\* a dead holder is "stale" and the reader takes over by writing its own pid (read and write are
\* separate steps). A pass can die while running. Mutual exclusion is the property.
EXTENDS Naturals, FiniteSets
CONSTANT Procs
VARIABLES pc, holder, alive, seen
vars == <<pc, holder, alive, seen>>
None == 0

Init == /\ pc = [p \in Procs |-> "idle"] /\ holder = None
        /\ alive = [p \in Procs |-> TRUE] /\ seen = [p \in Procs |-> None]

Mkdir(p) == /\ pc[p] = "idle" /\ alive[p] /\ holder = None
            /\ holder' = p /\ pc' = [pc EXCEPT ![p] = "running"] /\ UNCHANGED <<alive, seen>>
ReadPid(p) == /\ pc[p] = "idle" /\ alive[p] /\ holder # None
              /\ seen' = [seen EXCEPT ![p] = holder] /\ pc' = [pc EXCEPT ![p] = "decide"]
              /\ UNCHANGED <<holder, alive>>
Decide(p) == /\ pc[p] = "decide"
             /\ IF alive[seen[p]] THEN pc' = [pc EXCEPT ![p] = "gone"] /\ UNCHANGED holder
                ELSE /\ holder' = p /\ pc' = [pc EXCEPT ![p] = "running"]  \* takeover
             /\ UNCHANGED <<alive, seen>>
Finish(p) == /\ pc[p] = "running" /\ alive[p]
             /\ holder' = IF holder = p THEN None ELSE holder           \* rmtree only if mine
             /\ pc' = [pc EXCEPT ![p] = "gone"] /\ UNCHANGED <<alive, seen>>
Crash(p) == /\ pc[p] = "running" /\ alive[p]
            /\ alive' = [alive EXCEPT ![p] = FALSE] /\ pc' = [pc EXCEPT ![p] = "dead"]
            /\ UNCHANGED <<holder, seen>>
\* A crashed pass's pid can be reused by a NEW process (a fresh run of the nightly job).
Respawn(p) == /\ pc[p] \in {"dead", "gone"} /\ alive' = [alive EXCEPT ![p] = TRUE]
              /\ pc' = [pc EXCEPT ![p] = "idle"] /\ UNCHANGED <<holder, seen>>

Next == \E p \in Procs : Mkdir(p) \/ ReadPid(p) \/ Decide(p) \/ Finish(p) \/ Crash(p) \/ Respawn(p)
Mutex == Cardinality({p \in Procs : pc[p] = "running" /\ alive[p]}) <= 1
====

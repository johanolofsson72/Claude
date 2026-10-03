---- MODULE ModGuard ----
\* 095a: an agent write into folder F is judged at check time by R1, and lands later. R1 (c) reads the
\* disk: F is a plugin folder once it holds a marker (.claude-plugin or hooks/hooks.json). Only the
\* developer can create a marker (R1 (a), (b) deny the agent at any time). NoAgentWriteIntoMod: an agent
\* write never lands in F while F is a plugin folder. Parallel tool calls give the agent many pending writes.
\* MarkerRecheck models a harness (or guard) that re-judges the parent folder at write time.
EXTENDS TLC, Naturals
CONSTANTS MaxPending, MarkerRecheck
VARIABLES marked, pending, landedInMod

vars == <<marked, pending, landedInMod>>

Init == /\ marked = FALSE /\ pending = 0 /\ landedInMod = FALSE

DevMark   == /\ ~marked /\ marked' = TRUE  /\ UNCHANGED <<pending, landedInMod>>
DevUnmark == /\ marked  /\ marked' = FALSE /\ UNCHANGED <<pending, landedInMod>>

\* The verdict: a write into F passes only while F holds no marker.
AgentCheck == /\ pending < MaxPending /\ ~marked
              /\ pending' = pending + 1 /\ UNCHANGED <<marked, landedInMod>>

AgentLand == /\ pending > 0 /\ pending' = pending - 1
             /\ IF MarkerRecheck /\ marked THEN landedInMod' = landedInMod
                ELSE landedInMod' = (landedInMod \/ marked)
             /\ UNCHANGED marked

Next == DevMark \/ DevUnmark \/ AgentCheck \/ AgentLand
Spec == Init /\ [][Next]_vars

NoAgentWriteIntoMod == ~landedInMod
====

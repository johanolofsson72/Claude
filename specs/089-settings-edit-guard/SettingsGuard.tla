---- MODULE SettingsGuard ----
\* 089: an agent Write is judged on the bytes at check time and applied later. Between the two the
\* developer may edit the file by hand. GuardedKeysOnlyChangeByHand (spec.allium) must still hold.
\* StaleCheck models the harness refusing a Write/Edit whose file changed since it was read.
EXTENDS TLC
CONSTANTS Vals, StaleCheck
VARIABLES disk, authorized, pending, snapshot

None == "none"
vars == <<disk, authorized, pending, snapshot>>

Init == /\ disk \in Vals /\ authorized = disk /\ pending = None /\ snapshot = None

DevEdit == \E v \in Vals : /\ disk' = v /\ authorized' = v /\ UNCHANGED <<pending, snapshot>>

\* The guard allows only a write whose guarded keys equal the file's current ones.
AgentPropose == /\ pending = None
                /\ \E v \in Vals : /\ v = disk
                                   /\ pending' = v /\ snapshot' = disk
                /\ UNCHANGED <<disk, authorized>>

AgentApply == /\ pending # None
              /\ IF StaleCheck /\ disk # snapshot THEN disk' = disk ELSE disk' = pending
              /\ pending' = None /\ snapshot' = None
              /\ UNCHANGED authorized

Next == DevEdit \/ AgentPropose \/ AgentApply
Spec == Init /\ [][Next]_vars

GuardedKeysOnlyChangeByHand == disk = authorized
====

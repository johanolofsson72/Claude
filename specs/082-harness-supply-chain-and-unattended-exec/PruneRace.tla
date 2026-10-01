---- MODULE PruneRace ----
\* Spec 082 R10 + adversarial finding 8: prune-agent-worktrees.sh against a live agent.
\* One worktree, one agent, one prune pass. The prune reads activity, then status, decides,
\* re-reads status (F8c) and removes. The agent can act at any point in between.
\* Safety: a removal never destroys work (unique commits, modified or untracked files).
EXTENDS Naturals

CONSTANTS UseGrace, UseRecheck, UseForce

VARIABLES work, recent, locked, pc, seen, removed, lost

vars == <<work, recent, locked, pc, seen, removed, lost>>

Init ==
  /\ work = FALSE          \* unique commits / modified / untracked outside agent-memory
  /\ recent \in BOOLEAN    \* activity within PRUNE_GRACE_HOURS
  /\ locked = FALSE        \* lock held by a live agent pid
  /\ pc = "start"
  /\ seen = FALSE
  /\ removed = FALSE
  /\ lost = FALSE

\* Agent: writes work (which is activity), takes a lock, or goes idle long enough to age out.
AgentWrite == ~removed /\ work' = TRUE /\ recent' = TRUE /\ UNCHANGED <<locked, pc, seen, removed, lost>>
AgentLock  == ~removed /\ locked' = TRUE /\ recent' = TRUE /\ UNCHANGED <<work, pc, seen, removed, lost>>
AgentIdle  == recent /\ recent' = FALSE /\ UNCHANGED <<work, locked, pc, seen, removed, lost>>

PruneGrace ==
  /\ pc = "start"
  /\ IF UseGrace /\ recent THEN pc' = "kept" ELSE pc' = "status"
  /\ UNCHANGED <<work, recent, locked, seen, removed, lost>>

PruneStatus ==
  /\ pc = "status"
  /\ IF work \/ locked THEN pc' = "kept" ELSE pc' = "recheck"
  /\ seen' = work
  /\ UNCHANGED <<work, recent, locked, removed, lost>>

PruneRecheck ==
  /\ pc = "recheck"
  /\ IF UseRecheck /\ (work /= seen \/ locked) THEN pc' = "kept" ELSE pc' = "remove"
  /\ UNCHANGED <<work, recent, locked, seen, removed, lost>>

\* UseForce = FALSE is the shipped design (GAP-1 fix): plain `git worktree remove` checks for
\* modified and untracked files itself and refuses. Modelled as atomic; git's own check-then-delete
\* inside one process is the remaining (sub-millisecond) residual.
PruneRemove ==
  /\ pc = "remove"
  /\ IF ~UseForce /\ work
       THEN /\ pc' = "kept" /\ UNCHANGED <<removed, lost>>
       ELSE /\ removed' = TRUE /\ lost' = work /\ pc' = "done"
  /\ UNCHANGED <<work, recent, locked, seen>>

Next == AgentWrite \/ AgentLock \/ AgentIdle \/ PruneGrace \/ PruneStatus \/ PruneRecheck \/ PruneRemove
        \/ (pc \in {"kept", "done"} /\ UNCHANGED vars)

Spec == Init /\ [][Next]_vars

NoWorkLost == ~lost
====

---- MODULE RunnerPool ----
\* 085: the worker pool of scripts/run-mutation-gate.sh. Workers own disjoint mutants (index mod
\* jobs) and one copy each; a verdict is written only for a measured mutant (infra writes none);
\* the report scores only when every mutant has a verdict; a signal at any point runs the cleanup,
\* which stops the workers and removes the run dir. Allium: Run.RedBaselineIsUnmeasured,
\* Run.LeavesNothing, Mutant.TimeoutIsNotKill.
EXTENDS Naturals, FiniteSets, TLC

CONSTANTS Workers, Mutants, Owner      \* Owner: Mutants -> Workers

Outcomes == {"killed", "survived", "timeout", "infra"}

VARIABLES phase,      \* "work" | "report" | "cleanup" | "gone"
          wstate,     \* worker -> "running" | "done" | "stopped"
          verdict,    \* mutant -> "none" | "killed" | "survived" | "timeout"
          tried,      \* mutants a worker has finished with (verdict or infra)
          copies,     \* BOOLEAN: the run dir and its copies exist
          scored,     \* BOOLEAN: a `mutation score` line was printed
          exitcode    \* 0..2, or 99 = not exited yet

vars == <<phase, wstate, verdict, tried, copies, scored, exitcode>>

TypeOK ==
  /\ phase \in {"work", "report", "cleanup", "gone"}
  /\ wstate \in [Workers -> {"running", "done", "stopped"}]
  /\ verdict \in [Mutants -> {"none", "killed", "survived", "timeout"}]
  /\ tried \subseteq Mutants
  /\ copies \in BOOLEAN /\ scored \in BOOLEAN
  /\ exitcode \in {0, 1, 2, 99}

Init ==
  /\ phase = "work"
  /\ wstate = [w \in Workers |-> "running"]
  /\ verdict = [m \in Mutants |-> "none"]
  /\ tried = {}
  /\ copies = TRUE /\ scored = FALSE /\ exitcode = 99

\* A worker measures its next own mutant. Infra writes no verdict (review #3).
Measure(w, m, o) ==
  /\ phase = "work" /\ wstate[w] = "running"
  /\ Owner[m] = w /\ m \notin tried
  /\ tried' = tried \cup {m}
  /\ verdict' = IF o = "infra" THEN verdict ELSE [verdict EXCEPT ![m] = o]
  /\ UNCHANGED <<phase, wstate, copies, scored, exitcode>>

Finish(w) ==
  /\ phase = "work" /\ wstate[w] = "running"
  /\ \A m \in Mutants : Owner[m] = w => m \in tried
  /\ wstate' = [wstate EXCEPT ![w] = "done"]
  /\ UNCHANGED <<phase, verdict, tried, copies, scored, exitcode>>

\* `wait`, then `py report`.
Report ==
  /\ phase = "work" /\ \A w \in Workers : wstate[w] = "done"
  /\ phase' = "report"
  /\ IF \A m \in Mutants : verdict[m] # "none"
       THEN /\ scored' = TRUE
            /\ exitcode' \in {0, 1}           \* against the break
       ELSE /\ scored' = FALSE /\ exitcode' = 2  \* "no verdict; nothing scored"
  /\ UNCHANGED <<wstate, verdict, tried, copies>>

\* INT/TERM/HUP while working: the trap exits, and EXIT runs cleanup.
Signal ==
  /\ phase = "work"
  /\ phase' = "cleanup"
  /\ exitcode' = 2                            \* 130/143/129, modelled as "not a score"
  /\ UNCHANGED <<wstate, verdict, tried, copies, scored>>

\* cleanup: kill_tree every worker, wait, rm -rf the run dir. The EXIT trap also runs after Report.
Cleanup ==
  /\ phase \in {"report", "cleanup"}
  /\ wstate' = [w \in Workers |-> IF wstate[w] = "running" THEN "stopped" ELSE wstate[w]]
  /\ copies' = FALSE
  /\ phase' = "gone"
  /\ UNCHANGED <<verdict, tried, scored, exitcode>>

Next ==
  \/ \E w \in Workers, m \in Mutants, o \in Outcomes : Measure(w, m, o)
  \/ \E w \in Workers : Finish(w)
  \/ Report \/ Signal \/ Cleanup
  \/ (phase = "gone" /\ UNCHANGED vars)      \* terminal

Spec == Init /\ [][Next]_vars /\ WF_vars(Cleanup) /\ WF_vars(Report)
        /\ \A w \in Workers : WF_vars(Finish(w))
        /\ \A v \in Workers : WF_vars(\E m \in Mutants, o \in Outcomes : Measure(v, m, o))

\* A score is printed only when every mutant was measured (AC-2, review #3).
ScoreOnlyWhenComplete == scored => \A m \in Mutants : verdict[m] # "none"
\* A signal never yields a score.
SignalNeverScores == (phase \in {"cleanup", "gone"} /\ ~scored) => exitcode \in {2, 99} \/ phase = "gone"
\* Nothing is measured after the work phase.
NoVerdictAfterWork == phase # "work" => \A w \in Workers : wstate[w] # "running" \/ phase \in {"cleanup", "gone"}
\* Every run ends with the run dir gone (AC-4).
EndsClean == phase = "gone" => ~copies
EventuallyGone == <>(phase = "gone")
====

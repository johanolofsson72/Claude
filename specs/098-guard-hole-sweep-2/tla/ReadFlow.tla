---- MODULE ReadFlow ----
\* Spec 098 R7: settings_guard read_flows. Every abstract shape of a Bash line holding a read of a
\* guarded file is enumerated; Allowed must imply the read's output cannot reach a command that runs text.
\* Version "v1" is the pre-review R7 (commit 95b25ee), kept as the control that must fail.
EXTENDS Naturals
CONSTANT Version
VARIABLES mate, spill, unplain, runnerElsewhere, wrapperHidesRunner

Mates    == {"none", "filter", "pathFilter", "runner", "otherCmd"}
Spills   == {"none", "sink", "dupFd", "fileDigit", "fileName", "outOpt"}
Unplains == {"none", "group", "exec", "dollar", "backtick", "backslash", "quotedExec", "herestr", "highfd"}
vars == <<mate, spill, unplain, runnerElsewhere, wrapperHidesRunner>>

Init == /\ mate \in Mates /\ spill \in Spills /\ unplain \in Unplains
        /\ runnerElsewhere \in BOOLEAN /\ wrapperHidesRunner \in BOOLEAN
Next == UNCHANGED vars

\* Ground truth: what bash does with the line.
WritesFile == spill \in {"fileDigit", "fileName", "outOpt"}
Reaches == \/ mate \in {"runner", "otherCmd", "pathFilter"}
           \/ runnerElsewhere /\ (WritesFile \/ unplain # "none")

\* The guard, as coded.
Plain == IF Version = "v1" THEN unplain \in {"none", "dollar", "backtick", "backslash", "quotedExec"}
         ELSE unplain = "none"
SeenSpill == IF Version = "v1" THEN spill = "fileName" ELSE WritesFile
SeenMateBad == IF Version = "v1" THEN mate \in {"runner", "otherCmd"}
               ELSE mate \in {"runner", "otherCmd", "pathFilter"}
RunnerSeen == runnerElsewhere /\ (Version = "v2" \/ ~wrapperHidesRunner)
Deny == \/ SeenMateBad
        \/ ~Plain /\ RunnerSeen
        \/ Plain /\ SeenSpill /\ RunnerSeen
Allowed == ~Deny

NoReadReachesRunner == Allowed => ~Reaches
\* F155 must stay fixed: a plain line, filters only, no file written, runner elsewhere is allowed.
F155Allowed == (unplain = "none" /\ mate \in {"none", "filter"} /\ ~WritesFile) => Allowed
====

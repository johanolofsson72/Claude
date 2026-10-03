---- MODULE SettingsGit ----
\* 095 R1: the settings guard judges a whole Bash line once, at PreToolUse, and then the shell runs
\* its commands in order. A git tree verb is allowed when the revision it would write carries the
\* same guarded keys as the current file. A "mover" (update-ref, commit, hash-object + update-index …)
\* changes what a revision names. RULE = TRUE is the built rule: a mover BEFORE a tree verb on the
\* same line denies; a mover after it does not matter. RULE = FALSE is the first draft, which
\* compared contents only.
EXTENDS Integers, Sequences

CONSTANT RULE

Lines == { <<"verb">>, <<"mover", "verb">>, <<"verb", "mover">>, <<"mover">>, <<"verb", "verb">>,
           <<"mover", "verb", "mover">> }

VARIABLES file, ref, line, pc, verdict

vars == <<file, ref, line, pc, verdict>>

MoverBeforeVerb(l) == \E i, j \in 1..Len(l) : i < j /\ l[i] = "mover" /\ l[j] = "verb"
HasVerb(l) == \E i \in 1..Len(l) : l[i] = "verb"

Judge(l) ==
    IF ~HasVerb(l) THEN "allow"
    ELSE IF RULE /\ MoverBeforeVerb(l) THEN "deny"
    ELSE IF ref = file THEN "allow" ELSE "deny"

Init ==
    /\ file = "good"
    /\ ref \in {"good", "evil"}          \* the revision the verb names, as the guard reads it
    /\ line \in Lines
    /\ pc = 0
    /\ verdict = "none"

Check ==
    /\ pc = 0
    /\ verdict' = Judge(line)
    /\ pc' = IF Judge(line) = "allow" THEN 1 ELSE Len(line) + 1
    /\ UNCHANGED <<file, ref, line>>

Run ==
    /\ pc >= 1 /\ pc <= Len(line)
    /\ IF line[pc] = "mover"
          THEN /\ ref' = "evil" /\ UNCHANGED file
          ELSE /\ file' = ref /\ UNCHANGED ref
    /\ pc' = pc + 1
    /\ UNCHANGED <<line, verdict>>

Done == pc = Len(line) + 1 /\ UNCHANGED vars

Next == Check \/ Run \/ Done

Spec == Init /\ [][Next]_vars

\* Safety: a line the guard allowed never leaves the settings file with other guarded keys.
AllowedKeepsKeys == (verdict = "allow" /\ pc = Len(line) + 1) => file = "good"

TypeOK == /\ file \in {"good", "evil"} /\ ref \in {"good", "evil"} /\ verdict \in {"none", "allow", "deny"}
====

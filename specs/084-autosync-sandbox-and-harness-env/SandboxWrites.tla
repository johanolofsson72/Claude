---- MODULE SandboxWrites ----
\* 084 R2 R3: what a sync run may write outside the sandbox it declared.
\* A run picks a template clone (inside or outside the sandbox, by directory and by git common dir),
\* may refresh it, commits, and may push to origin, whose push URLs are each inside or outside.
\* SKIP_R2 / SKIP_R3 model the code with the requirement removed; the FALSE configs must fail.
EXTENDS Naturals, FiniteSets
CONSTANTS SKIP_R2, SKIP_R3, MaxUrls

Kinds == {"declared", "undeclared"}
VARIABLES kind, cloneDirIn, cloneGitIn, urlsIn, hasUpstream, phase, refreshed, pushed
vars == <<kind, cloneDirIn, cloneGitIn, urlsIn, hasUpstream, phase, refreshed, pushed>>

\* urlsIn: one Boolean per push URL ("inside the sandbox?"); zero URLs = no origin.
UrlVectors == UNION { [1..n -> BOOLEAN] : n \in 0..MaxUrls }

Init ==
  /\ kind \in Kinds /\ cloneDirIn \in BOOLEAN /\ cloneGitIn \in BOOLEAN
  /\ urlsIn \in UrlVectors /\ hasUpstream \in BOOLEAN
  /\ phase = "resolve" /\ refreshed = FALSE /\ pushed = FALSE

AllUrlsInside == DOMAIN urlsIn # {} /\ \A i \in DOMAIN urlsIn : urlsIn[i]
CloneInside == cloneDirIn /\ cloneGitIn

\* refresh_local_template: a declared run refreshes only a clone inside the sandbox (R3).
Resolve ==
  /\ phase = "resolve"
  /\ refreshed' = IF kind = "undeclared" \/ SKIP_R3 THEN TRUE ELSE CloneInside
  /\ phase' = "commit"
  /\ UNCHANGED <<kind, cloneDirIn, cloneGitIn, urlsIn, hasUpstream, pushed>>

\* The push block: needs an upstream; a declared run pushes only when every push URL is inside (R2).
Commit ==
  /\ phase = "commit"
  /\ pushed' = (hasUpstream /\ DOMAIN urlsIn # {} /\
                 (kind = "undeclared" \/ SKIP_R2 \/ AllUrlsInside))
  /\ phase' = "done"
  /\ UNCHANGED <<kind, cloneDirIn, cloneGitIn, urlsIn, hasUpstream, refreshed>>

Done == phase = "done" /\ UNCHANGED vars
Next == Resolve \/ Commit \/ Done
Spec == Init /\ [][Next]_vars /\ WF_vars(Next)

\* --- invariants -------------------------------------------------------------
NoSandboxedPushOutside == (kind = "declared" /\ pushed) => AllUrlsInside
NoSandboxedCloneMove   == (kind = "declared" /\ refreshed) => CloneInside
\* An undeclared run behaves as before: refresh always, push whenever there is an upstream.
UndeclaredUnchanged    == (kind = "undeclared" /\ phase = "done") =>
                            (refreshed /\ (pushed <=> (hasUpstream /\ DOMAIN urlsIn # {})))
\* A declared run with everything inside is not blocked (the sandbox is not an obstacle).
DeclaredInsideWorks    == (kind = "declared" /\ phase = "done" /\ hasUpstream /\ AllUrlsInside /\ CloneInside)
                            => (pushed /\ refreshed)
Terminates == <>(phase = "done")
====

---- MODULE MC_RunnerPool ----
EXTENDS RunnerPool
CONSTANTS w1, w2, m1, m2, m3
OwnerDef == (m1 :> w1) @@ (m2 :> w2) @@ (m3 :> w1)
====

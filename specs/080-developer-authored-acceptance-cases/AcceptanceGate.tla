---- MODULE AcceptanceGate ----
\* Spec 080: the acceptance-case gate as seen across a sequence of edits by one agent.
\* Digest versions model "the cases as they stand"; files model test files naming cases;
\* the cache stores a digest plus the files it saw, and a hit re-reads those files.
EXTENDS Naturals, FiniteSets
CONSTANTS Cases, Files, Versions
VARIABLES now, conf, names, cache, verdict
vars == <<now, conf, names, cache, verdict>>
None == 99

Init == /\ now = 0 /\ conf = None
        /\ names = [f \in Files |-> {}]
        /\ cache = [d |-> None, files |-> {}]
        /\ verdict = "idle"

Named(fs) == UNION {names[f] : f \in fs}
Confirmed == conf = now

EditCase == /\ \E v \in Versions \ {now} : now' = v
            /\ UNCHANGED <<conf, names, cache>> /\ verdict' = "idle"
Confirm  == /\ conf' = now /\ UNCHANGED <<now, names, cache>> /\ verdict' = "idle"
WriteTest == /\ Confirmed
             /\ \E f \in Files, s \in SUBSET Cases : names' = [names EXCEPT ![f] = s]
             /\ UNCHANGED <<now, conf, cache>> /\ verdict' = "idle"
\* A test file can be deleted or emptied at any time (the agent is unconstrained on it once confirmed,
\* and a deletion through Bash is not gated at all).
DropTest == /\ \E f \in Files : names' = [names EXCEPT ![f] = {}]
            /\ UNCHANGED <<now, conf, cache>> /\ verdict' = "idle"

CacheHit == cache.d = now /\ Cases \subseteq Named(cache.files)

ProdEdit ==
  /\ UNCHANGED <<now, conf, names>>
  /\ IF ~Confirmed THEN verdict' = "deny" /\ UNCHANGED cache
     ELSE IF CacheHit THEN verdict' = "allow" /\ UNCHANGED cache
     ELSE \/ /\ verdict' = "allow_timeout" /\ UNCHANGED cache          \* O6 fail-open
          \/ /\ IF Cases \subseteq Named(Files)
                THEN /\ verdict' = "allow"
                     /\ cache' = [d |-> now, files |-> {f \in Files : names[f] # {}}]
                ELSE /\ verdict' = "deny" /\ UNCHANGED cache

Next == EditCase \/ Confirm \/ WriteTest \/ DropTest \/ ProdEdit

\* Safety: an allowed production edit (not the documented timeout) means the cases are confirmed
\* as they stand AND every case is named by a test that exists right now.
GateSound == verdict = "allow" => (Confirmed /\ Cases \subseteq Named(Files))
TypeOK == verdict \in {"idle", "deny", "allow", "allow_timeout"} /\ now \in Versions

Spec == Init /\ [][Next]_vars
====

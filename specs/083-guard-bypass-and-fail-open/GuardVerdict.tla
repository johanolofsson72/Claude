---------------------------- MODULE GuardVerdict ----------------------------
(* Spec 083. The verdict a PreToolUse guard reaches for one tool call, over every
   combination of parser availability, payload shape and resolver outcome, and the
   way the CLI reads it (stdout counts only on exit 0, F029).

   Safety: no call the guard could not decide is allowed in silence (F044), and a
   fail-closed guard never allows a source edit it could not read (R2, O3).
   ExitOne models a guard that exits 1 after printing; MODEL_EXIT_ONE = TRUE
   reproduces F029 and must violate CliHonoursDeny. *)
EXTENDS TLC
CONSTANTS MODEL_EXIT_ONE

Guards   == {"failClosed", "failOpen"}
Parsers  == {"jq", "python3", "none"}
Payloads == {"wellformed", "malformed"}
Paths    == {"source", "other"}
Resolver == {"answer_allow", "answer_deny", "missing_python", "crash"}

VARIABLES guard, parser, payload, path, resolver, printed, exitcode, done

vars == <<guard, parser, payload, path, resolver, printed, exitcode, done>>

Init == /\ guard \in Guards /\ parser \in Parsers /\ payload \in Payloads
        /\ path \in Paths /\ resolver \in Resolver
        /\ printed = "nothing" /\ exitcode = 0 /\ done = FALSE

\* Can the guard read the payload at all? (guard_field: 3 = no parser, 4 = not JSON)
Readable == parser # "none" /\ payload = "wellformed"
\* The resolver needs python3 (pipeline-state / spec-interview).
EffResolver == IF parser = "jq" /\ resolver = "missing_python" THEN "missing_python"
               ELSE IF parser = "python3" /\ resolver = "missing_python" THEN "answer_deny"
               ELSE resolver

Decide ==
  /\ ~done
  /\ printed' =
       IF guard = "failClosed" THEN
         IF path = "other" THEN "nothing"                       \* precheck: not gated
         ELSE IF ~Readable THEN "deny"                           \* R2: cannot read -> deny
         ELSE CASE EffResolver = "answer_allow"   -> "nothing"
                [] EffResolver = "answer_deny"    -> "deny"
                [] EffResolver = "missing_python" -> "deny"      \* rc 127 -> deny
                [] EffResolver = "crash"          -> "deny"      \* unknown rc -> deny
       ELSE \* failOpen
         IF ~Readable THEN "announce"                           \* R3: allow, and say so
         ELSE IF path = "source" /\ EffResolver = "answer_deny" THEN "deny" ELSE "nothing"
  /\ exitcode' = IF MODEL_EXIT_ONE /\ printed' = "deny" THEN 1 ELSE 0
  /\ done' = TRUE
  /\ UNCHANGED <<guard, parser, payload, path, resolver>>

Next == Decide \/ (done /\ UNCHANGED vars)
Spec == Init /\ [][Next]_vars

\* What the CLI acts on.
CliVerdict == IF exitcode # 0 THEN "allow" ELSE IF printed = "deny" THEN "deny" ELSE "allow"

\* F044: an undecidable call is never a silent allow.
NoSilentAllow == done /\ ~Readable =>
                   (printed = "deny" \/ printed = "announce" \/ (guard = "failClosed" /\ path = "other"))
\* R2/O3: a fail-closed guard never lets an unreadable source edit through.
FailClosedHolds == done /\ guard = "failClosed" /\ path = "source" /\ ~Readable => CliVerdict = "deny"
\* R8/F029: whenever the guard printed a deny, the CLI applies it.
CliHonoursDeny == done /\ printed = "deny" => CliVerdict = "deny"
=============================================================================

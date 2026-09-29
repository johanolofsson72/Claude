# 042 — needs clause swallows a null dependency

Track: spec-only. No entity, no state machine, no new external surface. Not hardened: one function
in one CORE script (`scripts/lane_status.py`) and its test. Diagnosis in `specs/INDEX.pending.md`.

## The defect

`runnable()` keeps an unowned open row only when every entry in its `needs` list is a ticked id:

```python
and all(d in ticked for d in r["needs"])
```

`parse_rows()` puts whatever follows `needs` into that list. A register that says "depends on
nothing" in words (agentcrm's `needs inget`, or `needs nothing` / `needs none` in English) yields
`needs: ['inget']`. No row is ever ticked under that id, so the row is withheld from "unclaimed and
runnable" forever. On agentcrm's register at `3a7221ad` (2026-09-08, S16 ticked) the tool listed
three of nine runnable rows. The six it hid were S17, 027, 028, 029, 031 and 032. The last two are
the security rows H3 carved.

The failure only ever withholds. A short list of real rows looks exactly like a correct short list.

## Decision

The diagnosis proposed treating every entry that names no row as prose: free the row, report the
entry. agentcrm's own register (`specs/INDEX.md`, "Vem tar vad") and `scripts/next-rows.sh` state
the opposite policy on purpose: a `needs` entry naming no row **blocks**, so a typo can never make a
row look free. agentcrm gets there with a word list (`ingenting|inget|none|-`), which the diagnosis
rules out.

Both constraints hold if the entry's **shape** decides, not its vocabulary:

- **No digit in the entry** (`inget`, `nothing`, `none`, `ingenting`) → prose. Not a dependency,
  not reported. Every row id format the register uses (`004`, `004b`, `R1`, `S17`, `H3`) has a
  digit; no word meaning "nothing" in any language does.
- **Has a digit, names a ticked row** → satisfied.
- **Has a digit, names an open or held row** → blocks, as today.
- **Has a digit, names no row** (`04` for `004`, `R9`) → **blocks**, and is reported on one line:
  `needs names no row, held until fixed: 036 → 04; 038 → R9`. A typo can neither free a row nor
  hold it without saying why.

The report line sits under the runnable list, in the full report and the multi-lane brief. The
single-lane brief stays silent (the early return in `render()`, test case 5).

### Found during the fix: the list caps were silent too

With the fix, agentcrm's 2026-09-08 register has nine runnable rows. The full report shows eight
(`free[:8]`) and the brief six (`free[:6]`), and neither said so. The diagnosis's "eight would
have fitted" stopped being true once the fix landed. A capped list now says it is capped:
`… and 1 more: 029` in the full report, `(+3 more)` in the brief. Smaller than recording it.

## Acceptance

1. `needs inget`, `needs nothing`, `needs none, 007` (007 ticked) are offered as runnable.
2. Prose entries are never reported.
3. `needs 011` where 011 is an open row still withholds the row and prints no unresolved line.
4. `needs 007` where 007 is ticked offers the row and prints no unresolved line.
5. `needs 011, inget` with 011 open is withheld.
6. `needs 04` (no row 04) and `needs R9` withhold the row and are both named.
7. A ticked row's `needs` is never reported.
8. A single-lane brief stays silent.
9. A list longer than its cap names the overflow; exactly-at-cap prints no tail.
10. agentcrm at `3a7221ad`: 3 runnable before, 9 after, the six the diagnosis named.

## Non-goals

- Validating `needs` citations in `validate-register-ids.sh`.
- The `NEEDS` regex does not capture a bare `-` (`needs -` parses as no needs at all, which is
  already the right answer). Unchanged.
- Reading `INDEX.completed.md` to resolve ids of rows deleted from the register. A deleted row
  cited by `needs` blocks and is reported, which is the right thing to show.

## Clarifications

### Session 2026-09-29

- Q: Diagnosis (unresolved frees) or agentcrm's policy (unresolved blocks)? → A: Both, split by
  shape. Digit-less entries are prose and free the row; id-shaped entries that name no row block
  and are reported. Recorded in the run log as a deviation from the diagnosis.
- Q: Show the unresolved line in the brief or only the full report? → A: Both, where the runnable
  list shows. The brief is where agentcrm's developer read the short list.
- Q: Should a held row (`- [!]`) cited by `needs` count as known? → A: Yes. It is a row, not
  ticked, so it blocks.

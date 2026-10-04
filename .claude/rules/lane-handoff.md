# Lane handoff rule (two machines, one file — never a person as the transport)

**Inert on a single-lane project.** It applies only where two or more developers share one register (`— @name` owner tags, `SPEC_OWNER` per machine). Read `.claude/docs/lane-handoff-rationale.md` before acting on a multi-lane project.

## Where a cross-lane finding belongs (BLOCKING, multi-lane only)

Write it into the file that owns it, then commit and push. Never carry it between chats.

| The finding | The file |
|---|---|
| Belongs to an existing row | `specs/INDEX.pending.md` under that row |
| Work no row covers | a new owner-tagged row in `specs/INDEX.md` (carve budget applies) |
| Only an outsider can decide | the open-questions file, with a `**Blocks:** register row <id>` line |
| Deliberately deferred | the deferral log (e.g. `specs/PHASE-DEBT.md`) |
| Only the next session on the same spec needs it | `<spec-dir>/run-log.md` |

Tools: `scripts/lane-status.sh`, `scripts/lane-catchup.sh [--apply]`, `scripts/install-lane-merge-drivers.sh` (then `scripts/validate-register-ids.sh` after every merge).

**Forbidden:** a cross-lane finding only in chat; parking one in `run-log.md`; writing the register without pulling when upstream is ahead; moving someone else's owner tag.

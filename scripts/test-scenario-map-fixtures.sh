#!/bin/sh
# test-scenario-map-fixtures.sh — throwaway project fixtures for the 007bl harnesses.
#
# WHY: the three harnesses added by spec 007bl (layout, reminder, canary) all need the same
# thing: a small directory that looks enough like a project for a hook to run against, in each
# of the two map layouts. Building that inline in each harness would mean three slightly
# different notions of "a project", and the first time one drifted the harness would be testing
# its own fixture rather than the hook.
#
# The fixtures are deliberately minimal but not degenerate: each carries a language marker
# (package.json), a .git directory and a specs/INDEX.md, because every hook under test walks up
# to a project root, checks for a language marker, and reads the register. A fixture missing any
# of those makes the hooks exit silently, and a harness built on it would pass no matter what
# the hook did — the most expensive kind of green.
#
# SOURCE IT; it defines functions and runs nothing:
#   . "$(dirname "$0")/test-scenario-map-fixtures.sh"
#   root=$(make_single_file_fixture)
#   root=$(make_split_fixture)
#   fixture_cleanup            # removes everything made this run
#
# Each maker echoes the fixture root. Fixtures live under one temp dir per process so a single
# cleanup call takes them all, including after a failure.

FIXTURE_TMPDIR="${FIXTURE_TMPDIR:-}"

_fixture_tmpdir() {
    if [ -z "$FIXTURE_TMPDIR" ]; then
        FIXTURE_TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/scenmap-fixtures.XXXXXX")
        export FIXTURE_TMPDIR
    fi
    echo "$FIXTURE_TMPDIR"
}

fixture_cleanup() {
    [ -n "$FIXTURE_TMPDIR" ] && [ -d "$FIXTURE_TMPDIR" ] && rm -rf "$FIXTURE_TMPDIR"
    FIXTURE_TMPDIR=""
    return 0
}

# _fixture_skeleton <root> — the parts every fixture shares.
_fixture_skeleton() {
    _fs_root="$1"
    mkdir -p "$_fs_root/specs" "$_fs_root/.git" "$_fs_root/scripts"

    # The language marker. Without it every hook under test exits silently, per its own
    # template/scratch-repo guard, and the harness would prove nothing.
    printf '{ "name": "fixture", "private": true }\n' > "$_fs_root/package.json"

    cat > "$_fs_root/specs/INDEX.md" <<'FIXTURE_INDEX'
# Spec register

## Specs

- [x] 001 — alpha — full track — a finished feature
- [/] 002 — beta — full track — the in-progress row
- [ ] 003 — gamma — full track — the next row

## Register history

- 2026-08-26 — fixture register, not a real project
FIXTURE_INDEX
    unset _fs_root
}

# _fixture_index_head <root> — the part of the map that is identical in both layouts.
_fixture_index_head() {
    cat > "$1/specs/SCENARIOS.md" <<'FIXTURE_MAP_HEAD'
# Scenario map

Status:  ☐ mapped  ·  ◐ tested  ·  ✓ validated

## Use case overview (who can do what)

```mermaid
flowchart LR
  user([User]) --> uc1([Do the alpha thing])
  user --> uc2([Do the beta thing])
```

## Actor: User

FIXTURE_MAP_HEAD
}

_fixture_history() {
    cat >> "$1/specs/SCENARIOS.md" <<'FIXTURE_MAP_TAIL'

## Scenario history

- 2026-08-26 — fixture map, not a real project
FIXTURE_MAP_TAIL
}

# make_single_file_fixture — the pre-007bl shape: one map file, no specs/scenarios/ at all.
# This is the fixture that matters most. It is the one asserting that 41 projects which never
# split see byte-identical behaviour from every script 007bl touched.
make_single_file_fixture() {
    _sf_root="$(_fixture_tmpdir)/single-$$-${RANDOM:-0}"
    while [ -e "$_sf_root" ]; do _sf_root="${_sf_root}x"; done
    mkdir -p "$_sf_root"

    _fixture_skeleton "$_sf_root"
    _fixture_index_head "$_sf_root"

    cat >> "$_sf_root/specs/SCENARIOS.md" <<'FIXTURE_SINGLE'
### Feature: Alpha   (spec: 001-alpha)

The alpha feature, with a form the user can submit.

| ID     | Type  | Scenario              | Expected outcome            | Status |
|--------|-------|-----------------------|-----------------------------|--------|
| SC-001 | happy | Submit the alpha form | Saved and listed            | ✓      |
| SC-002 | error | Submit it empty       | Field error, input retained | ◐      |

#### The alpha detail   (spec: 001a-alpha-detail)

The nested sub-feature.

| ID     | Type  | Scenario                | Expected outcome     | Status |
|--------|-------|-------------------------|----------------------|--------|
| SC-003 | happy | Open the detail drawer  | The drawer opens     | ✓      |

### Feature: Beta   (spec: 002-beta)

The beta feature.

| ID     | Type  | Scenario           | Expected outcome | Status |
|--------|-------|--------------------|------------------|--------|
| SC-010 | happy | Click the beta tab | The tab opens    | ☐      |
FIXTURE_SINGLE

    _fixture_history "$_sf_root"
    echo "$_sf_root"
    unset _sf_root
}

# make_split_fixture — the post-007bl shape: index plus per-feature files.
#
# THE CASE THAT MATTERS is 001a-alpha-detail: a nested sub-feature whose slug appears ONLY
# inside specs/scenarios/001-alpha.md and NOWHERE in the index. It models msroute's real
# 007c-jwks-port-lifetime, a #### block living inside its parent's file whose slug the index
# never names. Pre-007bl the reminder hook greps the index alone, so it reports a scenario gap
# for a feature that is completely mapped.
#
# The other two slugs (001-alpha, 002-beta) DO appear in the index, because an index row names
# its feature's spec and links a file whose name embeds the slug. That makes them useless as a
# regression test for the multi-file search — they would pass with the old index-only grep. A
# fixture where every case passes both before and after the change tests nothing, so the
# nested slug carries the assertion and the other two guard against over-suppression.
make_split_fixture() {
    _sp_root="$(_fixture_tmpdir)/split-$$-${RANDOM:-0}"
    while [ -e "$_sp_root" ]; do _sp_root="${_sp_root}x"; done
    mkdir -p "$_sp_root/specs/scenarios"

    _fixture_skeleton "$_sp_root"
    _fixture_index_head "$_sp_root"

    cat >> "$_sp_root/specs/SCENARIOS.md" <<'FIXTURE_SPLIT_INDEX'
| Feature | Spec | Scenarios | Status |
|---------|------|-----------|--------|
| Alpha   | 001-alpha | [SC-001..003](scenarios/001-alpha.md) | 2 ✓, 1 ◐ |
| Beta    | 002-beta  | [SC-010](scenarios/002-beta.md)       | 1 ☐       |
FIXTURE_SPLIT_INDEX

    _fixture_history "$_sp_root"

    cat > "$_sp_root/specs/scenarios/001-alpha.md" <<'FIXTURE_ALPHA'
[← Scenario map](../SCENARIOS.md)

# Alpha   (spec: 001-alpha)

The alpha feature, with a form the user can submit.

| ID     | Type  | Scenario              | Expected outcome            | Status |
|--------|-------|-----------------------|-----------------------------|--------|
| SC-001 | happy | Submit the alpha form | Saved and listed            | ✓      |
| SC-002 | error | Submit it empty       | Field error, input retained | ◐      |

## The alpha detail   (spec: 001a-alpha-detail)

The nested sub-feature. Its slug is named here and in no index row — the shape that makes the
reminder hook's multi-file search load-bearing rather than decorative.

| ID     | Type  | Scenario                | Expected outcome     | Status |
|--------|-------|-------------------------|----------------------|--------|
| SC-003 | happy | Open the detail drawer  | The drawer opens     | ✓      |
FIXTURE_ALPHA

    cat > "$_sp_root/specs/scenarios/002-beta.md" <<'FIXTURE_BETA'
[← Scenario map](../SCENARIOS.md)

# Beta   (spec: 002-beta)

The beta feature.

| ID     | Type  | Scenario           | Expected outcome | Status |
|--------|-------|--------------------|------------------|--------|
| SC-010 | happy | Click the beta tab | The tab opens    | ☐      |
FIXTURE_BETA

    echo "$_sp_root"
    unset _sp_root
}

# make_empty_split_fixture — specs/scenarios/ exists but holds nothing.
# The interrupted-split case. Must read as single_file, or every consumer looks for rows in a
# directory that has none and the reminder hook reports a gap for every spec at once.
make_empty_split_fixture() {
    _es_root="$(_fixture_tmpdir)/empty-$$-${RANDOM:-0}"
    while [ -e "$_es_root" ]; do _es_root="${_es_root}x"; done
    mkdir -p "$_es_root/specs/scenarios"

    _fixture_skeleton "$_es_root"
    _fixture_index_head "$_es_root"
    _fixture_history "$_es_root"

    echo "$_es_root"
    unset _es_root
}

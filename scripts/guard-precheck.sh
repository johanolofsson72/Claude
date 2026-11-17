#!/bin/bash
# guard-precheck.sh — the one test the five Edit-path prechecks share (spec 090 R2(b), F083).
#
# Source it; do not execute it. It must stay builtin-only: it runs on every Edit/Write in every
# project, in front of the cheap exit that keeps those hooks from starting a process.
#
# WHY. Each guard exits early when the raw payload cannot name what it guards: no `.cs"` for the
# pipeline guards, no `scripts/` for core-machinery, no `INDEX.md` for core-owed-tick. The text is the
# name the agent spelled. A symlink that already exists in the tree has a name of its own:
# docs/notes.txt -> ../src/App.cs, or docs/tools -> ../scripts, and the precheck let both through
# before guard_canon, which follows links, ever saw them (083 adversarial #11, reproduced at 149eda0).
#
# guard_precheck_link <raw-json>: 0 when the parser must look, because the payload's file_path or
# notebook_path
#   * is a symlink, or runs through one,
#   * or holds a backslash, so the raw text is escaped and cannot be read as the name (a JSON \u
#     escape can spell any letter).
# Relative paths are taken against the payload's cwd, else $PWD, as guard_canon takes them.
#
# The ancestor test stops at CLAUDE_PROJECT_DIR when the path is spelled inside it. Above the project
# a link is ordinary (/tmp and /var on macOS, a symlinked ~/repos), and testing it would send every
# edit to the parser. Below the project a link moves the write, which is the case being caught. A path
# outside the project, or a run without CLAUDE_PROJECT_DIR, tests every component.
#
# guard_precheck_src <raw-json>: the three pipeline guards' whole precheck. 0 when the raw text holds a
# source path from the caller's SOURCE_EXTS, in any case (`.<ext>"`, and on NTFS `.<ext>."`,
# `.<ext> "` and `.<ext>::$DATA"`, the same file; R2(c)), or when guard_precheck_link says look.
guard_precheck_src() {
  local rc=1 was=0
  shopt -q nocasematch && was=1
  shopt -s nocasematch
  [[ $1 =~ \.($SOURCE_EXTS)([. ]|::\$DATA)*\" ]] && rc=0
  [ "$was" -eq 1 ] || shopt -u nocasematch
  [ "$rc" -eq 0 ] || guard_precheck_link "$1"
}

guard_precheck_link() {
  local raw="$1" p stop=""
  [[ $raw =~ \"(file_path|notebook_path)\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] || return 1
  p="${BASH_REMATCH[2]}"
  case "$p" in *\\*) return 0 ;; esac
  case "$p" in
    /*) ;;
    *)  if [[ $raw =~ \"cwd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then p="${BASH_REMATCH[1]}/$p"
        else p="$PWD/$p"; fi
        case "$p" in *\\*) return 0 ;; esac ;;
  esac
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    case "$p" in "${CLAUDE_PROJECT_DIR%/}"/*) stop="${CLAUDE_PROJECT_DIR%/}" ;; esac
  fi
  # Ends at the anchor's depth, or at "" (the parent of "/a") when there is none. By length, not by
  # string equality: the caller's `case` above may run under nocasematch, so `Claude/x` is "inside"
  # `claude`, and `[ "$p" != "$stop" ]` then never met its stop and spun at "" until the harness timed
  # the hook out, which ALLOWS the call (spec 105 R13, found 2026-11-17 on this repository: the harness
  # spells CLAUDE_PROJECT_DIR .../Claude, the disk .../claude).
  local prev
  while [ -n "$p" ] && [ "${#p}" -gt "${#stop}" ]; do
    [ -L "$p" ] && return 0
    prev=$p
    p="${p%/*}"
    [ "$p" = "$prev" ] && break       # no / left (a relative cwd "."): ${p%/*} cannot shrink it (threat model #24)
  done
  return 1
}

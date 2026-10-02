---- MODULE RootWalk ----
\* 090: the pipeline guards' walk (guard_walk) from an edited file up to its boundary, over every
\* layout the spec names. A path is file -> [worktree w] -> [anchor a] -> [outer o]: the file sits in
\* an optional linked worktree, below the session's anchor (CLAUDE_PROJECT_DIR), which may itself be
\* a subdirectory of an outer repository. Each level may hold a register, a marker and a .git of some
\* form. The agent chooses the layout (it can write .git files, git init, git worktree add); the
\* project's own register is at the top repository.
\*
\* RegisterNeverDropped: whenever the project above has a register, the walk ends with SOME register,
\* unless the developer started in a real nested repository (a commit at the anchor, O1) or the
\* worktree brought its own. Inherit = FALSE models 088 (no R7), AnchorCheck = FALSE models no R6.
EXTENDS TLC, Naturals
CONSTANTS Inherit, AnchorCheck

GitForms == {"none", "emptyfile", "emptydir", "init", "commit", "worktree", "fakefile"}

VARIABLES layout, result
vars == <<layout, result>>

\* A layout: does the worktree level exist, the .git form at the worktree and at the anchor, whether
\* the anchor has an outer repository above it, and where registers and markers sit.
Layouts == [ wt : BOOLEAN, wtGit : {"worktree"}, wtReg : BOOLEAN, wtMarker : BOOLEAN,
             anchorGit : GitForms, outer : BOOLEAN, topReg : BOOLEAN, topMarker : BOOLEAN ]

\* guard_git_boundary at the anchor (R6): with an outer repo above, only a linked worktree or a
\* directory-form repository with a commit is a boundary; with none above, any .git is.
AnchorIsBoundary(l) ==
  IF l.anchorGit = "none" THEN FALSE
  ELSE IF ~l.outer \/ ~AnchorCheck THEN TRUE
  ELSE l.anchorGit \in {"commit", "worktree"}

\* The walk. Levels in order: worktree (when present), anchor, outer (when present).
\* Returns [reg |-> register found, root |-> where it stopped].
Walk(l) ==
  LET wtOwn == l.wt /\ (l.wtReg)
      wtStops == l.wt /\ (~Inherit \/ (l.wtReg /\ l.wtMarker))
      \* registers collected below the anchor
      regBelow == l.wt /\ l.wtReg
      \* the anchor level holds the top register when there is no outer repo; otherwise the outer does
      anchorReg == ~l.outer /\ l.topReg
      outerReg == l.outer /\ l.topReg
  IN IF wtStops THEN [reg |-> regBelow, root |-> "worktree"]
     ELSE IF AnchorIsBoundary(l) THEN
            [reg |-> regBelow \/ anchorReg \/ (l.anchorGit = "worktree" /\ Inherit /\ outerReg),
             root |-> "anchor"]
     ELSE IF l.outer THEN [reg |-> regBelow \/ outerReg, root |-> "outer"]
     ELSE [reg |-> regBelow \/ anchorReg, root |-> "none"]

Init == /\ layout \in Layouts
        /\ layout.topReg
        /\ result = Walk(layout)

Next == UNCHANGED vars
Spec == Init /\ [][Next]_vars

RealNestedRepo == layout.outer /\ layout.anchorGit = "commit"

RegisterNeverDropped ==
  (result.reg) \/ RealNestedRepo \/ (~layout.outer /\ layout.anchorGit = "none")
====

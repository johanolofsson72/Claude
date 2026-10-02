# template-identity.sh — is this repository the template? Sourced, never run (spec 091 R1, F097).
#
# Four callers used to answer this by matching origin's URL against *johanolofsson72/Claude*:
# core-machinery-guard and core-owed-tick-guard (the template is exempt from both), and
# template-autosync.sh and its hook (the template is never a sync target). Origin is one command away
# for the agent (`git remote set-url`), and the unanchored pattern also matched evil-johanolofsson72/Claude.
# File markers are no better: the sync copies them into every project.
#
# So the template is its history. The URL must match one of three anchored spellings AND HEAD's root
# commits must be exactly the template's first commit. No synced project shares it (46 measured on
# 2026-10-02); making one share it means rebuilding the project's whole history on the template's.
# The root is read with replace refs off and grafts read from /dev/null: both can
# fake a parentless commit, and --no-replace-objects alone still honours .git/info/grafts (measured).
#
#   template_identity DIR   -> prints template | impostor | project, always exit 0
#   template_url_matches URL -> exit 0 when URL is one of the anchored spellings
#
# impostor = the URL says template and the history does not (a shallow clone of the template lands
# here too). Callers that exempt do so only for `template`; a missing library means `project`.
# bash 3.2-safe; one `git remote get-url`, plus one rev-list only when the URL matches (22 ms).

TEMPLATE_ROOT_COMMIT=d3cf8238372ce7a37d5d66b115cbcbf9d57bb2b9

template_url_matches() {
  # GitHub folds case in owner and repository names, so a clone of .../johanolofsson72/claude (lower
  # case) is the template too (threat model A1); bash 3.2 has no ${1,,}. One trailing / and then one
  # .git are optional.
  _tu=$(printf '%s' "$1" | tr 'A-Z' 'a-z'); _tu=${_tu%/}; _tu=${_tu%.git}
  case "$_tu" in
    https://github.com/johanolofsson72/claude|git@github.com:johanolofsson72/claude|ssh://git@github.com/johanolofsson72/claude) return 0 ;;
  esac
  return 1
}

template_identity() {
  # The raw value, not `remote get-url`, which applies url.*.insteadOf (threat model A1): the URL that is
  # compared is the one written in this repository's own config.
  _ti_url=$(git -C "$1" config --local --get remote.origin.url 2>/dev/null </dev/null)
  if ! template_url_matches "$_ti_url"; then echo project; return 0; fi
  _ti_roots=$(GIT_GRAFT_FILE=/dev/null \
              git --no-replace-objects -c core.commitGraph=false -C "$1" rev-list --max-parents=0 HEAD 2>/dev/null </dev/null)
  if [ "$_ti_roots" = "$TEMPLATE_ROOT_COMMIT" ]; then echo template; else echo impostor; fi
}

#!/usr/bin/env bash
# Shared lane-branch set builder for the two integration gates
# (block-unreviewed-merge.sh, block-merge-if-verification-unclosed.sh).
#
# Why this exists: ~40 lines of set-building lived VERBATIM in both gates. Duplicated
# gate-signal code drifts — a fix to one copy (a new lane source, a liveness rule)
# silently misses the other, and one gate's lane becomes the other gate's blind spot.
# Single authority, same policy as lib/merge-targets.sh / lib/lane-match.sh /
# lib/board-liveness.sh (ADR 0005 guard 1).
#
# The lane set is the union of two sources (ADR 0004):
#   (a) task branches of an ACTIVE board (docs/bootstrap/sprint/board.json) — liveness, not
#       existence, judged by lib/board-liveness.sh (a leftover all-done board must not
#       arm the gates: 2026-06-07 incident).
#   (b) branches checked out in LINKED worktrees — the physical trace of parallel
#       mutation that exists regardless of HOW the lanes were created (board-less
#       Workflow / manual worktrees; 2026-06-11 incident). The first porcelain block is
#       the main worktree itself and is excluded (its branch is the merge DESTINATION,
#       not a lane).
# Pure bash + grep/sed, jq-free.

# Single authority on board liveness (resolved relative to this lib).
# shellcheck source=board-liveness.sh
# Include guard — dispatcher が 1 プロセスに複数 gate を source するときの再読込抑止。
[ -n "${_BOOTSTRAP_LIB_LANE_SET:-}" ] && return 0
_BOOTSTRAP_LIB_LANE_SET=1

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/board-liveness.sh"
# Single authority on where the sprint directory lives (new docs/bootstrap/ vs legacy docs/).
# shellcheck source=resolve-docs.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/resolve-docs.sh"

# lane_branches <top> — print the lane-branch union, one per line (may include empty
# lines; lane_set_contains ignores them). Absent board / no linked worktrees simply
# contribute nothing — the CALLER decides the fail-mode for an empty set (both gates
# treat it as no-grounds -> fail-open).
lane_branches() {
  local top="$1" board branches="" wt=""
  board="$(resolve_docs_dir "$top" sprint)/board.json"
  if board_has_active_tasks "$board"; then
    branches=$(grep -oE '"branch"[[:space:]]*:[[:space:]]*"[^"]*"' "$board" | sed 's/.*"branch"[[:space:]]*:[[:space:]]*"//; s/"$//')
  fi
  # Linked-worktree branches: skip the first porcelain block (= the main worktree).
  wt=$(git -C "$top" worktree list --porcelain 2>/dev/null | sed -n '/^$/,$p' | sed -n 's|^branch refs/heads/||p')
  if [ -n "$branches" ] && [ -n "$wt" ]; then
    printf '%s\n%s\n' "$branches" "$wt"
  elif [ -n "$branches" ]; then
    printf '%s\n' "$branches"
  elif [ -n "$wt" ]; then
    printf '%s\n' "$wt"
  fi
  return 0
}

# lane_set_contains <tok> <set> — return 0 if <tok> equals a non-empty line of <set>.
lane_set_contains() {
  local tok="$1" b
  while IFS= read -r b; do
    [ -n "$b" ] && [ "$tok" = "$b" ] && return 0
  done <<< "$2"
  return 1
}

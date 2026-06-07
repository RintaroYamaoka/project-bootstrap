#!/usr/bin/env bash
# Shared judge for "is a sprint ACTIVE" — the liveness (not existence) of board.json.
#
# Born from docs/incidents/2026-06-07-stale-board-gate-bypass: the sprint gate used to
# treat a NON-EMPTY board.json as "sprint in progress", but a board is per-sprint
# ephemeral state with a terminal phase (all tasks done, not yet archived) where
# existence and liveness diverge — a leftover done-board silently disarmed the gate
# for two weeks. The rule is therefore: a sprint is active iff the board has at least
# one task whose status is not "done". block-unplanned-feature-build.sh and
# block-unreviewed-merge.sh both gate on this; a single authority prevents the two
# copies from drifting (drift in a gate signal IS the silent-bypass class).
#
# Contract:
#   board_has_active_tasks <board-path>
#   return 0 = board exists, non-empty, and has at least one "status" != "done"
#   return 1 = anything else (absent / empty / no tasks / no status keys / all done)
#   no stdout. Pure bash + grep, jq-free.

# board_has_active_tasks — see header.
board_has_active_tasks() {
  local board="$1"
  [ -s "$board" ] || return 1
  grep -oE '"status"[[:space:]]*:[[:space:]]*"[^"]*"' "$board" | grep -qv '"done"'
}

#!/usr/bin/env bash
# Unit tests for hooks/lib/board-liveness.sh — the shared "is a sprint ACTIVE" judge.
#
# Why a lib: the liveness rule (= board.json has a task with status != done) was inlined
# in block-unplanned-feature-build.sh after the stale-board incident
# (docs/incidents/2026-06-07-stale-board-gate-bypass). block-unreviewed-merge.sh needs the
# exact same judgment; two inline copies would drift, and drift in a gate signal is the
# silent-bypass class all over again. Single authority, two consumers.
#
# Contract:
#   board_has_active_tasks <board-path>
#   return 0  = board exists, non-empty, and has at least one "status" != "done"
#   return 1  = anything else (absent / empty / all done / no tasks / no status keys)
#   no stdout. Pure bash + grep, jq-free.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"
source "$(cd "$DIR/../../hooks" && pwd)/lib/board-liveness.sh"

TMP="$(mktemp -d)"

check() { # check <expected-rc> <label> <board-content or ABSENT>
  local expected="$1" label="$2" content="$3" rc
  local board="$TMP/board.json"
  rm -f "$board"
  [ "$content" != "ABSENT" ] && printf '%s' "$content" > "$board"
  if board_has_active_tasks "$board"; then rc=0; else rc=1; fi
  test_case "$label"
  assert_eq "$expected" "$rc"
}

check 1 "absent board is not active" ABSENT
check 1 "empty board is not active" ""
check 1 "taskless board is not active" '{"sprint":"s1","wip_limit":2}'
check 1 "all-done board is not active" '{"tasks":[{"id":"T0","status":"done"},{"id":"T1","status":"done"}]}'
check 0 "todo task makes board active" '{"tasks":[{"id":"T0","status":"done"},{"id":"T1","status":"todo"}]}'
check 0 "in-progress task makes board active" '{"tasks":[{"id":"T1","status":"in-progress"}]}'
check 0 "in-review task makes board active" '{"tasks":[{"id":"T1","status":"in-review"}]}'
check 1 "status-less tasks carry no liveness evidence" '{"tasks":[{"id":"T1"}]}'

finish

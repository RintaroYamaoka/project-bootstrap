#!/usr/bin/env bash
# Unit tests for hooks/lib/gate-entry.sh — the judge for whether a single .gate entry
# is LIVE EVIDENCE of a sprint-gate decision.
#
# Why a lib: a .gate entry is a per-feature ephemeral judgment, but the gate used to
# honor entries forever (no expiry) and at any breadth (any glob). One `src/**` line
# recorded on 2026-06-02 in a consumer repo silently disarmed the sprint gate for the
# entire source tree, permanently — 10+ new source files were created without a single
# gate decision (docs/incidents/2026-06-11-gate-broad-glob-permanent-fail-open, the 4th
# member of the gate-silence class). The fix bounds an entry in TIME (date column + TTL)
# and in SPACE (feature-scoped glob), so no single line can outlive or outgrow the
# feature it judged.
#
# Contract:
#   gate_date_fresh <YYYY-MM-DD> [today]
#     return 0 = strict YYYY-MM-DD and 0 <= (today - date) <= GATE_TTL_DAYS (3)
#     return 1 = malformed / absent / future / older than TTL
#   gate_scope_ok <glob>
#     return 0 = exact path (no wildcard), or the literal directory prefix before the
#                first wildcard segment has >= 2 segments (feature-scoped)
#     return 1 = tree-wide (src/**, scripts/**, **, *, *.ts, src/*/x, ...)
#   no stdout. Pure bash, jq-free, no GNU date arithmetic.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"
source "$(cd "$DIR/../../hooks" && pwd)/lib/gate-entry.sh"

check_fresh() { # check_fresh <expected-rc> <label> <date> <today>
  local expected="$1" label="$2" dt="$3" today="$4" rc
  if gate_date_fresh "$dt" "$today"; then rc=0; else rc=1; fi
  test_case "$label"
  assert_eq "$expected" "$rc"
}

check_scope() { # check_scope <expected-rc> <label> <glob>
  local expected="$1" label="$2" pat="$3" rc
  if gate_scope_ok "$pat"; then rc=0; else rc=1; fi
  test_case "$label"
  assert_eq "$expected" "$rc"
}

# --- freshness: TTL boundary (GATE_TTL_DAYS = 3) ---
check_fresh 0 "same-day entry is fresh"            2026-06-11 2026-06-11
check_fresh 0 "age 3 (= TTL) is still fresh"       2026-06-08 2026-06-11
check_fresh 1 "age 4 (> TTL) is stale"             2026-06-07 2026-06-11
check_fresh 1 "weeks-old entry is stale"           2026-01-01 2026-06-11
check_fresh 1 "future-dated entry is not evidence" 2026-06-12 2026-06-11
check_fresh 0 "month boundary arithmetic"          2026-02-28 2026-03-02
check_fresh 1 "year boundary stale"                2025-12-31 2026-06-11

# --- freshness: malformed dates carry no evidence (旧形式の行を含む) ---
check_fresh 1 "old-format rationale word is not a date" "sequential:" 2026-06-11
check_fresh 1 "empty date is not evidence"              ""            2026-06-11
check_fresh 1 "slash-separated date rejected"           2026/06/11    2026-06-11
check_fresh 1 "non-zero-padded date rejected"           2026-6-8      2026-06-11

# --- freshness: today defaults to the real clock ---
test_case "today defaults to date +%F"
if gate_date_fresh "$(date +%F)"; then rc=0; else rc=1; fi
assert_eq 0 "$rc"

# --- scope: exact paths are the narrowest possible — always ok ---
check_scope 0 "exact nested file"      src/lib/staff.ts
check_scope 0 "exact root file"        main.py
check_scope 0 "exact script"           scripts/import_terminal_tabs.py

# --- scope: globs need a >= 2-segment literal prefix (feature 面に絞る) ---
check_scope 0 "two-segment dir glob"   'src/components/**'
check_scope 0 "deep dir glob"          'src/app/cd/settings/**'
check_scope 0 "extension glob in dir"  'src/lib/*.ts'
check_scope 1 "tree-wide src glob"     'src/**'
check_scope 1 "tree-wide scripts glob" 'scripts/**'
check_scope 1 "bare doublestar"        '**'
check_scope 1 "bare star"              '*'
check_scope 1 "bare extension glob"    '*.ts'
check_scope 1 "wildcard at 2nd segment" 'src/*/util.ts'

finish

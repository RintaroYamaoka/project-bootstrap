#!/usr/bin/env bash
# Unit tests for hooks/lib/verification-plan.sh — the single authority on the
# verification-plan format. Pins: status parsing, the fail-closed OPEN bias
# (unknown status -> open), DROP-needs-a-reason, comment/blank handling, counts.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"
# shellcheck source=../../hooks/lib/verification-plan.sh
. "$DIR/../../hooks/lib/verification-plan.sh"

# --- vplan_row_status ---
test_case "status of a normal row is uppercased"
assert_eq "PASS" "$(vplan_row_status 'pass | unit | x | y | ai | ok')"
test_case "status tolerates leading/trailing space"
assert_eq "TODO" "$(vplan_row_status '   todo | contract | x | y | ai | ')"
test_case "comment line has no status"
assert_eq "" "$(vplan_row_status '# verification plan — foo')"
test_case "blank line has no status"
assert_eq "" "$(vplan_row_status '   ')"

# --- vplan_is_open: only PASS and DROP close; everything else is open ---
test_case "TODO is open"; vplan_is_open 'TODO | a | b | c | ai |'; assert_eq 0 "$?"
test_case "FAIL is open"; vplan_is_open 'FAIL | a | b | c | ai |'; assert_eq 0 "$?"
test_case "HUMAN is open"; vplan_is_open 'HUMAN | a | b | c | human |'; assert_eq 0 "$?"
test_case "PASS is closed"; vplan_is_open 'PASS | a | b | c | ai | ok'; assert_eq 1 "$?"
test_case "DROP is closed"; vplan_is_open 'DROP | a | b | c | ai | low risk'; assert_eq 1 "$?"
test_case "unknown/typo status is OPEN (fail-closed)"; vplan_is_open 'PSAS | a | b | c | ai |'; assert_eq 0 "$?"
test_case "comment is not open"; vplan_is_open '# note'; assert_eq 1 "$?"

# --- vplan_field ---
test_case "field 6 (evidence) is extracted and trimmed"
assert_eq "site real output" "$(vplan_field 'PASS | contract | keys | oracle | ai | site real output' 6)"

# --- file-level: a mixed plan ---
PLAN="$(mktemp)"
cat > "$PLAN" <<'EOF'
# verification plan — demo booking
# STATUS | kind | behaviour | oracle | by | evidence
PASS  | contract | form keys ⊆ schema required | site real output | ai | PR#303
HUMAN | e2e      | book a demo end-to-end       | submission row appears | human |
TODO  | monitor  | CV>0 & bookings=0 alarm      | daily rollup | ai |
DROP  | unit     | css pixel exactness          | n/a | ai | low risk, not worth it
EOF

test_case "row count ignores comments/blanks"
assert_eq 4 "$(vplan_row_count "$PLAN")"

test_case "open rows = HUMAN + TODO (2 lines)"
assert_eq 2 "$(vplan_open_rows "$PLAN" | grep -c .)"
test_case "open rows include the HUMAN e2e row"
case "$(vplan_open_rows "$PLAN")" in *"book a demo end-to-end"*) assert_eq ok ok ;; *) assert_eq ok FAIL ;; esac
test_case "open rows do NOT include the PASS row"
case "$(vplan_open_rows "$PLAN")" in *"form keys"*) assert_eq ok FAIL ;; *) assert_eq ok ok ;; esac

test_case "justified DROP is not flagged"
assert_eq 0 "$(vplan_bad_drops "$PLAN" | grep -c .)"

# --- DROP without a reason is flagged ---
PLAN2="$(mktemp)"
cat > "$PLAN2" <<'EOF'
PASS | unit | x | y | ai | ok
DROP | unit | skipped thing | n/a | ai |
EOF
test_case "DROP with empty reason is flagged"
assert_eq 1 "$(vplan_bad_drops "$PLAN2" | grep -c .)"
test_case "a fully-closed plan with a reasoned DROP has no open rows"
assert_eq 0 "$(vplan_open_rows "$PLAN2" | grep -c .)"

# --- empty / missing files ---
test_case "missing file: row count 0"
assert_eq 0 "$(vplan_row_count "/no/such/file")"
test_case "missing file: no open rows"
assert_eq 0 "$(vplan_open_rows "/no/such/file" | grep -c .)"

rm -f "$PLAN" "$PLAN2"
finish

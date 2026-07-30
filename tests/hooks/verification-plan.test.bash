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

# --- vplan_path_for_branch: single authority for branch -> plan path (shared by the
#     merge gate AND the SessionStart doctor so the two surfaces can't drift). ---
# The directory half is resolved through resolve-docs.sh (ADR 0020): a repo with
# neither layout on disk gets the new canonical docs/bootstrap/verification, so an
# un-adopted path reads the same place the gate would create.
test_case "plan path maps a slashed branch to an underscored filename"
assert_eq "/tmp/r/docs/bootstrap/verification/feat_x.md" "$(vplan_path_for_branch /tmp/r feat/x)"
test_case "plan path for a flat branch name"
assert_eq "/tmp/r/docs/bootstrap/verification/main.md" "$(vplan_path_for_branch /tmp/r main)"
test_case "plan path collapses every slash (nested branch)"
assert_eq "/tmp/r/docs/bootstrap/verification/feat_foo_bar.md" "$(vplan_path_for_branch /tmp/r feat/foo/bar)"

# A repo still on the legacy flat layout must keep resolving to ITS plans — otherwise
# the merge gate would look at an empty directory and fail open on upgrade.
VP_LEGACY="$(mktemp -d)"; mkdir -p "$VP_LEGACY/docs/verification"
test_case "plan path follows the legacy layout when that is what the repo has"
assert_eq "$VP_LEGACY/docs/verification/feat_x.md" "$(vplan_path_for_branch "$VP_LEGACY" feat/x)"
VP_NEW="$(mktemp -d)"; mkdir -p "$VP_NEW/docs/bootstrap/verification"
test_case "plan path follows the new layout once migrated"
assert_eq "$VP_NEW/docs/bootstrap/verification/feat_x.md" "$(vplan_path_for_branch "$VP_NEW" feat/x)"
test_case "empty branch yields empty path (caller detects)"
assert_eq "" "$(vplan_path_for_branch /tmp/r '')"

# --- vplan_has_kind: exact field-2 (kind) match, case-folded, NOT a substring scan ---
# (D4 / ADR 0007 amendment) The async/monitor doctor keys on the kind field the AI
# deliberately set — never on prose — so a DROP row whose behaviour text contains the
# word 'drop' or 'monitor' must NOT register as that kind.
KPLAN="$(mktemp)"
cat > "$KPLAN" <<'EOF'
# verification plan — async work
TODO  | async   | cron sends the reminder           | n/a | ai |
PASS  | unit     | parse the row                     | known | ai | ok
DROP  | unit     | drop the monitor pixel exactness  | n/a | ai | low risk, not worth monitoring
EOF
test_case "vplan_has_kind finds an exact async kind row"
vplan_has_kind "$KPLAN" async; assert_eq 0 "$?"
test_case "vplan_has_kind is case-insensitive on the kind field"
vplan_has_kind "$KPLAN" ASYNC; assert_eq 0 "$?"
test_case "vplan_has_kind does NOT match a word inside the behaviour prose (no substring scan)"
vplan_has_kind "$KPLAN" monitor; assert_eq 1 "$?"
test_case "vplan_has_kind absent kind returns non-zero"
vplan_has_kind "$KPLAN" e2e; assert_eq 1 "$?"
test_case "vplan_has_kind on a missing file returns non-zero"
vplan_has_kind "/no/such/file" async; assert_eq 1 "$?"
rm -f "$KPLAN"

rm -f "$PLAN" "$PLAN2"
finish

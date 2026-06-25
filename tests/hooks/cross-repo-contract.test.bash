#!/usr/bin/env bash
# Unit tests for hooks/lib/cross-repo-contract.sh — the single authority on the
# cross-repo contract declaration (docs/verification/contracts) shared by the merge
# gate and the doctor (ADR 0011).
#
# Two halves are exercised:
#   (1) declaration parse — comment/blank handling, field extraction, glob match.
#   (2) branch_changed_sources over a REAL temp git repo with a lane branch: the lane's
#       OWN delta computed OFFLINE (merge-base lane..main, diff base..lane, filtered to
#       source faces). This is the move the critique flagged: reusing the doctor's
#       cwd/HEAD delta yields the empty set during a PreToolUse merge hook (HEAD = main),
#       so the gate never fires. We assert the lane delta is non-empty when it must be.
#
# Pure bash, jq-free, no network. Mirrors verification-drift.test.bash fixture style.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"
source "$(cd "$DIR/../../hooks" && pwd)/lib/cross-repo-contract.sh"

git config --global user.email >/dev/null 2>&1 || git config --global user.email "test@example.com"
git config --global user.name  >/dev/null 2>&1 || git config --global user.name  "test"

# ── (1) declaration parse ───────────────────────────────────────────────────────
CF="$(mktemp)"
cat > "$CF" <<'EOF'
# a comment
   # indented comment

demo-survey-schema | src/schemas/demoSiteSurvey.* | demo-site | apps/web/SurveyForm.tsx | consumer-driven
booking-payload    | src/api/booking/*.ts          | demo-site | apps/web/postBooking.ts  |
EOF

test_case "comments and blanks are ignored; two contracts parsed"
assert_eq 2 "$(crc_each_contract "$CF" | grep -c .)"

test_case "field 1 (id) is extracted and trimmed"
assert_eq "demo-survey-schema" "$(crc_field 'demo-survey-schema | src/schemas/demoSiteSurvey.* | demo-site | x | y' 1)"
test_case "field 2 (local_face_glob) is extracted and trimmed"
assert_eq "src/schemas/demoSiteSurvey.*" "$(crc_field 'demo-survey-schema | src/schemas/demoSiteSurvey.* | demo-site | x | y' 2)"
test_case "field 3 (peer_repo) is extracted and trimmed"
assert_eq "demo-site" "$(crc_field 'demo-survey-schema | src/schemas/demoSiteSurvey.* | demo-site | x | y' 3)"

test_case "crc_contracts_file maps dir to docs/verification/contracts"
assert_eq "/tmp/r/docs/verification/contracts" "$(crc_contracts_file /tmp/r)"

# crc_glob_matches <path> <glob> — repo-relative path vs declared glob.
test_case "glob match: extension wildcard hits a concrete file"
crc_glob_matches "src/schemas/demoSiteSurvey.ts" "src/schemas/demoSiteSurvey.*"; assert_eq 0 "$?"
test_case "glob match: directory wildcard hits a nested file"
crc_glob_matches "src/api/booking/create.ts" "src/api/booking/*.ts"; assert_eq 0 "$?"
test_case "glob non-match: different directory"
crc_glob_matches "src/api/other/create.ts" "src/api/booking/*.ts"; assert_eq 1 "$?"
test_case "glob non-match: different extension"
crc_glob_matches "src/schemas/demoSiteSurvey.md" "src/schemas/demoSiteSurvey.ts"; assert_eq 1 "$?"

# ── (2) branch_changed_sources over a real temp git repo ────────────────────────
# Build: main with a base commit; a lane branch that adds/edits a source face AND a doc;
# then move main forward so HEAD (during the merge hook) is NOT the lane tip. The lane's
# OWN delta must still be computed correctly OFFLINE against the merge-base.
mklane_repo() {
  local r; r="$(mktemp -d)"
  git -C "$r" init -q -b main
  mkdir -p "$r/src/schemas" "$r/docs/verification"
  printf 'export const base = 1\n' > "$r/src/schemas/base.ts"
  git -C "$r" add -A
  git -C "$r" -c user.email=t@e.x -c user.name=t commit -q -m base
  # lane branch off main
  git -C "$r" checkout -q -b feat/lane
  printf 'export const survey = {a:1}\n' > "$r/src/schemas/demoSiteSurvey.ts"
  printf '# lane notes\n' > "$r/docs/lane-notes.md"
  git -C "$r" add -A
  git -C "$r" -c user.email=t@e.x -c user.name=t commit -q -m "lane: add survey schema + doc"
  # main moves forward (so HEAD during a merge differs from the lane tip)
  git -C "$r" checkout -q main
  printf 'export const base = 2\n' > "$r/src/schemas/base.ts"
  git -C "$r" add -A
  git -C "$r" -c user.email=t@e.x -c user.name=t commit -q -m "main: advance base"
  printf '%s' "$r"
}

R="$(mklane_repo)"
# Run with HEAD on main (the merge-hook condition): the lane delta must still surface the
# lane's OWN source change, NOT main's, and must exclude the lane's doc-only change.
CHANGED="$(branch_changed_sources "$R" feat/lane)"
test_case "branch_changed_sources surfaces the lane's own source face (HEAD on main)"
case "$CHANGED" in *"src/schemas/demoSiteSurvey.ts"*) assert_eq ok ok ;; *) assert_eq ok FAIL ;; esac
test_case "branch_changed_sources excludes the lane's doc-only change"
case "$CHANGED" in *"docs/lane-notes.md"*) assert_eq ok FAIL ;; *) assert_eq ok ok ;; esac
test_case "branch_changed_sources excludes main's own advance (only the lane delta)"
case "$CHANGED" in *"src/schemas/base.ts"*) assert_eq ok FAIL ;; *) assert_eq ok ok ;; esac

# crc_touched_contract_ids <dir> <lane> — intersect the lane delta with declared globs.
printf 'demo-survey-schema | src/schemas/demoSiteSurvey.* | demo-site | x | y\n' > "$R/docs/verification/contracts"
printf 'unrelated | src/api/*.ts | demo-site | x | y\n' >> "$R/docs/verification/contracts"
TOUCHED="$(crc_touched_contract_ids "$R" feat/lane)"
test_case "touched contract id is the one whose glob matches the lane delta"
assert_eq "demo-survey-schema" "$TOUCHED"

# Lane that touches NO declared face => no touched ids (no-grounds, gate fail-open).
mklane_repo_nodecl() {
  local r; r="$(mktemp -d)"
  git -C "$r" init -q -b main
  mkdir -p "$r/src/util" "$r/docs/verification"
  git -C "$r" -c user.email=t@e.x -c user.name=t commit -q --allow-empty -m base
  git -C "$r" checkout -q -b feat/lane2
  printf 'export const u = 1\n' > "$r/src/util/helper.ts"
  git -C "$r" add -A
  git -C "$r" -c user.email=t@e.x -c user.name=t commit -q -m "lane2: util"
  printf 'demo-survey-schema | src/schemas/*.ts | demo-site | x | y\n' > "$r/docs/verification/contracts"
  printf '%s' "$r"
}
R2="$(mklane_repo_nodecl)"
test_case "lane touching no declared face yields no touched ids"
assert_eq "" "$(crc_touched_contract_ids "$R2" feat/lane2)"

# Missing contracts file => no contracts, no touched ids (fail-open at the gate).
R3="$(mktemp -d)"; git -C "$R3" init -q -b main
git -C "$R3" -c user.email=t@e.x -c user.name=t commit -q --allow-empty -m base
test_case "missing contracts file: zero contracts"
assert_eq 0 "$(crc_each_contract "$R3/docs/verification/contracts" | grep -c .)"

# ── (3) crc_closed_row_references_id — a CLOSED plan row that names the contract id ─────
# The gate needs: a touched contract id requires a CLOSED (PASS / reasoned DROP) plan row
# that references the id. An OPEN row that names the id does NOT close it (it blocks via the
# plan's existing OPEN-row check); a row naming a DIFFERENT id does not count.
source "$(cd "$DIR/../../hooks" && pwd)/lib/verification-plan.sh"
PLAN="$(mktemp)"
cat > "$PLAN" <<'EOF'
PASS  | contract | form keys ⊆ schema [contract:demo-survey-schema] | site real output | ai | suite green
TODO  | contract | booking payload shape [contract:booking-payload] | site real output | ai |
DROP  | contract | legacy [contract:legacy-thing] | n/a | ai | retired, no longer shared
EOF
test_case "PASS row referencing the id closes it"
crc_closed_row_references_id "$PLAN" "demo-survey-schema"; assert_eq 0 "$?"
test_case "reasoned DROP row referencing the id closes it (deliberate, logged ack)"
crc_closed_row_references_id "$PLAN" "legacy-thing"; assert_eq 0 "$?"
test_case "an OPEN (TODO) row referencing the id does NOT close it"
crc_closed_row_references_id "$PLAN" "booking-payload"; assert_eq 1 "$?"
test_case "an id with no referencing row at all is not closed"
crc_closed_row_references_id "$PLAN" "absent-id"; assert_eq 1 "$?"
rm -f "$PLAN"

rm -f "$CF"
finish

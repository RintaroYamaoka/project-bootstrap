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

# ── (3b) ANCHORED-TAG match — the [contract:<id>] convention, no string-proxy holes ─────
# The adversarial review found that a RAW substring scan of the whole row text closes a
# touched contract on two false-positive holes inside this fail-CLOSED gate:
#   (1) id-substring collision — a touched id 'booking' is "closed" by a row that only
#       references the SUPERSTRING id 'booking-payload' (the gate returned 0 where it MUST
#       block). (2) common-word collision — 'survey' is "closed" by any PASS/DROP row whose
#       prose merely mentions the word 'survey', with no contract tag at all.
# The repo already conventions the anchored token '[contract:<id>]'; the matcher must key on
# that LITERAL bracketed tag (id treated as a literal — never a substring, never prose).
PLAN2="$(mktemp)"
cat > "$PLAN2" <<'EOF'
PASS  | contract | booking payload shape [contract:booking-payload] | site real output | ai | suite green
PASS  | manual   | the demo survey looked fine to me                | human eyeballed  | ai | no tag here
EOF
test_case "id-substring hole: 'booking' is NOT closed by a row tagging only 'booking-payload'"
crc_closed_row_references_id "$PLAN2" "booking"; assert_eq 1 "$?"
test_case "common-word hole: 'survey' is NOT closed by a PASS row whose prose only says 'survey'"
crc_closed_row_references_id "$PLAN2" "survey"; assert_eq 1 "$?"

PLAN3="$(mktemp)"
cat > "$PLAN3" <<'EOF'
PASS  | contract | booking payload shape [contract:booking] | site real output | ai | suite green
PASS  | contract | survey form keys ⊆ schema [contract:survey] | site real output | ai | suite green
EOF
test_case "anchored tag for 'booking' DOES close id 'booking'"
crc_closed_row_references_id "$PLAN3" "booking"; assert_eq 0 "$?"
test_case "exact-id anchored row for 'survey' closes 'survey'"
crc_closed_row_references_id "$PLAN3" "survey"; assert_eq 0 "$?"
test_case "superstring id 'booking-payload' is NOT closed by the 'booking' tag (boundary safety)"
crc_closed_row_references_id "$PLAN3" "booking-payload"; assert_eq 1 "$?"
test_case "an OPEN (TODO) row carrying the anchored tag still does NOT close (status wins)"
printf 'TODO | contract | x [contract:booking] | o | ai |\n' > "$PLAN3"
crc_closed_row_references_id "$PLAN3" "booking"; assert_eq 1 "$?"
rm -f "$PLAN2" "$PLAN3"

# ── (4) END-TO-END through the gate (block-merge-if-verification-unclosed.sh) ───────────
# The unit cases above prove crc_closed_row_references_id; here we prove the FIX holds all
# the way through the fail-CLOSED gate. We build a real repo whose lane branch touches a
# declared contract face, attach a plan that is "closed" on the OPEN-row axis (all rows
# PASS) but only acknowledges the WRONG (superstring / prose) id — the gate must still
# BLOCK (exit 2). With the substring bug it returned exit 0 (false-CLOSE). A control case
# with the correctly anchored tag (and no test runner detected) must PASS the contract axis.
#
# gate_repo <touched-id> <plan-tag-line> — builds a repo where:
#   - docs/verification/ exists (opt-in)
#   - contract id <touched-id> declares glob src/api/<touched-id>/*.ts
#   - a LINKED WORKTREE holds feat/<touched-id>-lane (so is_lane_branch is true) whose OWN
#     delta adds src/api/<touched-id>/create.ts (touches the declared face)
#   - docs/verification/feat_<touched-id>-lane.md = the plan, all rows PASS, carrying the
#     caller-supplied <plan-tag-line> as its only contract row.
# Echoes the repo top path. No package.json => detect_test_command returns 1 (the contract
# SUITE step is skipped), isolating the ack-row decision we are testing.
gate_repo() {
  local id="$1" tagline="$2" r wt
  r="$(mktemp -d)"; wt="$(mktemp -d)"; rmdir "$wt"
  git -C "$r" init -q -b main
  mkdir -p "$r/docs/verification" "$r/src/api/$id"
  printf 'export const base = 1\n' > "$r/src/base.ts"
  git -C "$r" add -A
  git -C "$r" -c user.email=t@e.x -c user.name=t commit -q -m base
  # lane branch in a LINKED WORKTREE — touches the declared contract face on its own delta.
  git -C "$r" worktree add -q -b "feat/$id-lane" "$wt" main >/dev/null 2>&1
  mkdir -p "$wt/src/api/$id"
  printf 'export const x = 1\n' > "$wt/src/api/$id/create.ts"
  git -C "$wt" add -A
  git -C "$wt" -c user.email=t@e.x -c user.name=t commit -q -m "lane: touch $id face" >/dev/null 2>&1
  # declaration + plan, committed on main (so they are present in the gate's TOP working tree)
  printf '%s | src/api/%s/*.ts | demo-site | x | y\n' "$id" "$id" > "$r/docs/verification/contracts"
  {
    printf '# verification plan\n'
    printf 'PASS | e2e | unrelated flow works | site | ai | green\n'
    printf '%s\n' "$tagline"
  } > "$r/docs/verification/feat_$id-lane.md"
  git -C "$r" add -A
  git -C "$r" -c user.email=t@e.x -c user.name=t commit -q -m "declare contract + plan"
  printf '%s' "$r"
}

# (4a) FALSE-CLOSE HOLE #1 (id-substring): touched id 'booking' acknowledged ONLY by a row
# tagging the superstring 'booking-payload' → the gate MUST BLOCK (with the bug it passed).
GR="$(gate_repo booking 'PASS | contract | payload shape [contract:booking-payload] | site | ai | green')"
RUN_DIR="$GR" run_hook block-merge-if-verification-unclosed.sh '{"tool_input":{"command":"git merge feat/booking-lane"}}'
test_case "e2e: touched id 'booking' is NOT closed by a 'booking-payload' row — gate BLOCKS"
assert_exit 2
test_case "e2e: the block names the touched contract id"
assert_stderr_contains 'booking'
rm -rf "$GR"

# (4b) FALSE-CLOSE HOLE #2 (common-word): touched id 'survey' acknowledged ONLY by a PASS
# row whose prose mentions the word survey (no tag) → the gate MUST BLOCK.
GR="$(gate_repo survey 'PASS | manual | the survey looked fine to me | human | ai | eyeballed')"
RUN_DIR="$GR" run_hook block-merge-if-verification-unclosed.sh '{"tool_input":{"command":"git merge feat/survey-lane"}}'
test_case "e2e: touched id 'survey' is NOT closed by prose mentioning 'survey' — gate BLOCKS"
assert_exit 2
rm -rf "$GR"

# (4c) CONTROL: the correctly anchored tag '[contract:booking]' DOES close the touched id;
# with no detectable test runner the contract axis passes → the gate exits 0 (clean merge).
GR="$(gate_repo booking 'PASS | contract | payload shape [contract:booking] | site | ai | green')"
RUN_DIR="$GR" run_hook block-merge-if-verification-unclosed.sh '{"tool_input":{"command":"git merge feat/booking-lane"}}'
test_case "e2e: anchored '[contract:booking]' row closes the touched id — gate PASSES"
assert_exit 0
rm -rf "$GR"

# (5) NEEDS_CONTRACT_SUITE red->block branch — previously untested edge. Same shape as (4c)
# (touched id acknowledged via an ANCHORED row) but the repo carries a package.json whose
# "test" script EXITS NON-ZERO. detect_test_command finds it (npm on PATH), the gate RUNS
# the suite to back the contract PASS, the suite is RED → the gate must BLOCK (exit 2).
# If npm is absent the runner can't be detected; we skip the e2e and say so (the decision
# branch is also exercised at unit level by the green-vs-red suite reasoning in the gate).
if command -v npm >/dev/null 2>&1; then
  GR="$(gate_repo booking 'PASS | contract | payload shape [contract:booking] | site | ai | green')"
  # add a failing test script (exit 1) — keep it on main so the gate's TOP tree sees it.
  cat > "$GR/package.json" <<'EOF'
{ "name": "fixture", "version": "0.0.0", "scripts": { "test": "exit 1" } }
EOF
  git -C "$GR" add -A
  git -C "$GR" -c user.email=t@e.x -c user.name=t commit -q -m "add failing test script"
  RUN_DIR="$GR" run_hook block-merge-if-verification-unclosed.sh '{"tool_input":{"command":"git merge feat/booking-lane"}}'
  test_case "e2e: acknowledged contract + RED consumer suite — gate RUNS the suite and BLOCKS"
  assert_exit 2
  test_case "e2e: the block cites the failing test suite (D3 cross-repo contract)"
  assert_stderr_contains 'test suite fails'
  rm -rf "$GR"
else
  test_case "e2e: NEEDS_CONTRACT_SUITE red->block — SKIPPED (npm not on PATH in this env)"
  assert_eq skip skip
fi

rm -f "$CF"
finish

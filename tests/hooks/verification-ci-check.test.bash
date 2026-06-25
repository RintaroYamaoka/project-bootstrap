#!/usr/bin/env bash
# Tests for hooks/lib/verification-ci-check.sh — the server-side (CI) twin of the merge
# gate (ADR 0012). Same judgement as the local hook (verification-plan.sh authority) but
# resolves the branch from arg/$GITHUB_HEAD_REF/git instead of a PreToolUse JSON.
#
# Pins: opt-in (no docs/verification => neutral pass), no-plan => neutral pass (lane-ness
# isn't observable server-side), empty plan => block, OPEN row => block, unjustified DROP
# => block, all-closed => pass, branch resolution order (arg > GITHUB_HEAD_REF).

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"
SCRIPT="$DIR/../../hooks/lib/verification-ci-check.sh"

setup_repo() {
  local tmp; tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  REPO="$(git -C "$tmp" rev-parse --show-toplevel)"
  git -C "$REPO" config user.email t@t.test
  git -C "$REPO" config user.name tester
  git -C "$REPO" commit -q --allow-empty -m base
}
adopt_verify() { mkdir -p "$REPO/docs/verification"; }
write_plan() { # write_plan <branch> <line...>
  local b="$1"; shift
  mkdir -p "$REPO/docs/verification"
  printf '%s\n' "$@" > "$REPO/docs/verification/$(printf '%s' "$b" | tr '/' '_').md"
}
# run_ci <branch-arg> [GITHUB_HEAD_REF] — execute the script from inside the fixture repo.
run_ci() {
  local arg="$1" headref="${2:-}"
  local errf outf; errf="$(mktemp)"; outf="$(mktemp)"
  ( cd "$REPO" && GITHUB_HEAD_REF="$headref" bash "$SCRIPT" "$arg" ) >"$outf" 2>"$errf"
  HOOK_EXIT=$?
  HOOK_STDERR="$(cat "$errf")"; HOOK_STDOUT="$(cat "$outf")"
  rm -f "$errf" "$outf"
}

# 1. Not adopted => neutral pass.
setup_repo
test_case "no docs/verification adoption: neutral pass"
run_ci feat_x
assert_exit 0
assert_stderr_contains 'not adopted'

# 2. Adopted but no plan for the branch => neutral pass (lane-ness not observable in CI).
setup_repo; adopt_verify
test_case "adopted, no plan for branch: neutral pass"
run_ci feat_x
assert_exit 0
assert_stderr_contains 'no verification plan'

# 3. Plan with all rows closed (PASS + reasoned DROP) => pass.
setup_repo; adopt_verify
write_plan feat_x \
  '# STATUS | kind | behaviour | oracle | by | note' \
  'PASS | contract | keys ⊆ schema | site output | ai | PR#1' \
  'DROP | unit | css pixels | n/a | ai | low risk'
test_case "closed plan passes"
run_ci feat_x
assert_exit 0
assert_stderr_contains 'OK'

# 4. Plan with an OPEN row (TODO) => block.
setup_repo; adopt_verify
write_plan feat_x \
  '# h' \
  'TODO | contract | keys ⊆ schema | site output | ai |'
test_case "OPEN row blocks"
run_ci feat_x
assert_exit 1
assert_stderr_contains 'not closed'

# 5. Plan with a HUMAN row => block (HUMAN is OPEN — the irreducible oracle).
setup_repo; adopt_verify
write_plan feat_x \
  '# h' \
  'HUMAN | e2e | finish a real booking | row appears | human |'
test_case "HUMAN row blocks"
run_ci feat_x
assert_exit 1

# 6. Empty plan (no data rows) => block.
setup_repo; adopt_verify
write_plan feat_x '# only a comment'
test_case "empty plan blocks"
run_ci feat_x
assert_exit 1
assert_stderr_contains 'no test-case rows'

# 7. Unjustified DROP => block.
setup_repo; adopt_verify
write_plan feat_x \
  '# h' \
  'DROP | unit | css pixels | n/a | ai |'
test_case "DROP without a reason blocks"
run_ci feat_x
assert_exit 1

# 8. Branch resolution: empty arg falls back to GITHUB_HEAD_REF.
setup_repo; adopt_verify
write_plan feat_fromenv \
  '# h' \
  'TODO | contract | x | y | ai |'
test_case "branch resolves from GITHUB_HEAD_REF when arg empty"
run_ci '' feat_fromenv
assert_exit 1
assert_stderr_contains 'feat_fromenv'

finish

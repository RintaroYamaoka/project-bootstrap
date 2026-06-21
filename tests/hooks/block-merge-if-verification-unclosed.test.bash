#!/usr/bin/env bash
# Tests for hooks/block-merge-if-verification-unclosed.sh — verification plan as a
# fail-closed precondition of integration (git merge of a lane branch).
#
# Mirrors the lane-branch signal of block-unreviewed-merge: the gate fires for task
# branches on an active board and for branches checked out in linked worktrees, only
# when docs/verification/ is adopted. A merge is blocked unless the lane's plan exists,
# has >=1 row, has no OPEN row (TODO/FAIL/HUMAN), and no unjustified DROP.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"

HOOK=block-merge-if-verification-unclosed.sh

setup_repo() {
  local tmp; tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  REPO="$(git -C "$tmp" rev-parse --show-toplevel)"
  git -C "$REPO" config user.email t@t.test
  git -C "$REPO" config user.name tester
}
adopt_verify() { mkdir -p "$REPO/docs/verification"; }
active_board() {
  mkdir -p "$REPO/docs/sprint"
  printf '%s' '{"sprint":"s1","wip_limit":2,"tasks":[{"id":"T1","title":"x","branch":"feat/T1-auth","status":"in-review"},{"id":"T2","title":"y","branch":"feat/T2-api","status":"todo"}]}' > "$REPO/docs/sprint/board.json"
}
write_plan() { # write_plan <branch> <line...>
  local b="$1"; shift
  mkdir -p "$REPO/docs/verification"
  printf '%s\n' "$@" > "$REPO/docs/verification/$(printf '%s' "$b" | tr '/' '_').md"
}
add_worktree_branch() {
  git -C "$REPO" commit -q --allow-empty -m base 2>/dev/null
  git -C "$REPO" worktree add -q -b "$1" "$REPO/.claude/worktrees/$(printf '%s' "$1" | tr '/' '_')" >/dev/null 2>&1
}
merge_input() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' "$1" "$REPO"; }

# 1. docs/verification not adopted => fail-open even with an active board.
setup_repo
active_board
RUN_DIR="$REPO"
test_case "no verification adoption: merge passes (opt-in)"
run_hook "$HOOK" "$(merge_input 'git merge feat/T1-auth')"
assert_exit 0

# 2. Adopted, lane branch, NO plan file => blocked.
setup_repo
active_board
adopt_verify
RUN_DIR="$REPO"
test_case "lane merge without a plan is blocked"
run_hook "$HOOK" "$(merge_input 'git merge feat/T1-auth')"
assert_exit 2
assert_stderr_contains 'no verification plan'

# 3. Plan exists but all rows closed (PASS + reasoned DROP) => passes.
setup_repo
active_board
write_plan feat/T1-auth \
  'PASS | contract | keys subset | site output | ai | PR#1' \
  'DROP | unit | pixel exactness | n/a | ai | low risk'
RUN_DIR="$REPO"
test_case "closed plan lets the merge pass"
run_hook "$HOOK" "$(merge_input 'git merge feat/T1-auth')"
assert_exit 0

# 4. Plan has an open TODO row => blocked.
setup_repo
active_board
write_plan feat/T1-auth \
  'PASS | contract | keys subset | site output | ai | PR#1' \
  'TODO | e2e | book end-to-end | submission row | ai |'
RUN_DIR="$REPO"
test_case "open TODO row blocks the merge"
run_hook "$HOOK" "$(merge_input 'git merge feat/T1-auth')"
assert_exit 2
assert_stderr_contains 'not closed'

# 5. Plan has an unresolved HUMAN row => blocked (the irreducible oracle hasn't run).
setup_repo
active_board
write_plan feat/T1-auth \
  'HUMAN | e2e | book a demo end-to-end | submission appears | human |'
RUN_DIR="$REPO"
test_case "unresolved HUMAN row blocks the merge"
run_hook "$HOOK" "$(merge_input 'git merge feat/T1-auth')"
assert_exit 2

# 6. Plan exists but has zero data rows (only comments) => blocked.
setup_repo
active_board
write_plan feat/T1-auth '# verification plan — nothing here yet' '# STATUS | kind | ...'
RUN_DIR="$REPO"
test_case "empty (comment-only) plan is blocked"
run_hook "$HOOK" "$(merge_input 'git merge feat/T1-auth')"
assert_exit 2
assert_stderr_contains 'no test cases'

# 7. DROP without a reason => blocked (no silent caps).
setup_repo
active_board
write_plan feat/T1-auth \
  'PASS | unit | x | y | ai | ok' \
  'DROP | unit | skipped thing | n/a | ai |'
RUN_DIR="$REPO"
test_case "unjustified DROP blocks the merge"
run_hook "$HOOK" "$(merge_input 'git merge feat/T1-auth')"
assert_exit 2
assert_stderr_contains 'DROP'

# 8. Merging a branch NOT on the board => fail-open (no basis).
setup_repo
active_board
adopt_verify
RUN_DIR="$REPO"
test_case "non-lane branch merge passes"
run_hook "$HOOK" "$(merge_input 'git merge hotfix/typo')"
assert_exit 0

# 9. Non-merge command => fail-open.
setup_repo
active_board
adopt_verify
RUN_DIR="$REPO"
test_case "non-merge command passes"
run_hook "$HOOK" "$(merge_input 'git status')"
assert_exit 0

# 10. Flag-with-arg before the branch (-m <msg>) must not hide the branch.
setup_repo
active_board
adopt_verify
RUN_DIR="$REPO"
test_case "merge -m message feat/T1-auth still detected and blocked (no plan)"
run_hook "$HOOK" "$(merge_input 'git merge -m integration_msg feat/T1-auth')"
assert_exit 2

# 11. Unparseable command JSON => fail-closed.
setup_repo
active_board
adopt_verify
RUN_DIR="$REPO"
test_case "unparseable hook input is fail-closed"
run_hook "$HOOK" '{"tool_name":"Bash","tool_input":{"command":"git merge feat/T1-auth'
assert_exit 2

# 12. Non-git dir => fail-open.
NOGIT="$(mktemp -d)"; mkdir -p "$NOGIT/docs/verification"
RUN_DIR="$NOGIT"
test_case "non-git dir is fail-open"
run_hook "$HOOK" "$(printf '{"tool_name":"Bash","tool_input":{"command":"git merge feat/T1-auth"},"cwd":"%s"}' "$NOGIT")"
assert_exit 0

# 13. Worktree lane branch (no board) with a closed plan => passes.
setup_repo
adopt_verify
add_worktree_branch "lane/slack-notify"
write_plan "lane/slack-notify" 'PASS | contract | x | y | ai | ok'
RUN_DIR="$REPO"
test_case "worktree lane with closed plan passes (no board needed)"
run_hook "$HOOK" "$(merge_input 'git merge lane/slack-notify')"
assert_exit 0

# 14. Worktree lane branch (no board) with an open plan => blocked.
setup_repo
adopt_verify
add_worktree_branch "lane/slack-notify"
write_plan "lane/slack-notify" 'FAIL | contract | x | y | ai | regressed'
RUN_DIR="$REPO"
test_case "worktree lane with FAIL row is blocked"
run_hook "$HOOK" "$(merge_input 'git merge lane/slack-notify')"
assert_exit 2

# 15. Worktree lane but docs/verification NOT adopted => fail-open (opt-in).
setup_repo
add_worktree_branch "lane/slack-notify"
RUN_DIR="$REPO"
test_case "worktree lane without verification adoption passes (opt-in)"
run_hook "$HOOK" "$(merge_input 'git merge lane/slack-notify')"
assert_exit 0

# --- regression: compound + path-prefixed merges (the greedy-sed / bare-token bypass) ---
# Same bug as block-unreviewed-merge: only the LAST merge of a compound command was
# inspected and only a bare `git merge` token was detected. lib/merge-targets.sh fixes both.

# 16. Compound merge must not hide a lane with no/open plan behind a closed-plan lane.
setup_repo
active_board
adopt_verify
write_plan feat/T2-api 'PASS | contract | x | y | ai | ok'
RUN_DIR="$REPO"
test_case "compound merge does not hide an unverified lane behind a closed one"
run_hook "$HOOK" "$(merge_input 'git merge feat/T1-auth && git merge feat/T2-api')"
assert_exit 2
assert_stderr_contains 'no verification plan'

# 17. Path-prefixed git (/usr/bin/git) must be detected.
setup_repo
active_board
adopt_verify
RUN_DIR="$REPO"
test_case "path-prefixed git merge of an unverified lane is blocked"
run_hook "$HOOK" "$(merge_input '/usr/bin/git merge feat/T1-auth')"
assert_exit 2

# 18. Compound merge of two closed-plan lanes still passes (no over-block).
setup_repo
active_board
write_plan feat/T1-auth 'PASS | contract | x | y | ai | ok'
write_plan feat/T2-api 'PASS | contract | x | y | ai | ok'
RUN_DIR="$REPO"
test_case "compound merge of two closed-plan lanes passes"
run_hook "$HOOK" "$(merge_input 'git merge feat/T1-auth && git merge feat/T2-api')"
assert_exit 0

finish

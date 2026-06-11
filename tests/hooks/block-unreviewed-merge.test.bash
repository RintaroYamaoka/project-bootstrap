#!/usr/bin/env bash
# Tests for hooks/block-unreviewed-merge.sh — AI レビューを統合の precondition にする gate.
#
# Why this hook exists: the throughput ceiling of the parallel flow is the human reviewing
# every diff serially (sprint-plan/SKILL.md states it outright). Stage 2 of the trust ladder
# moves first-pass review to adversarial read-only AI agents and lets the human read verdicts
# + samples. But "the review happened" must not be advisory — this hook makes it a fail-closed
# precondition of the integration act itself (git merge of a task branch), exactly as the TDD
# hook enforces test existence and the sprint gate enforces that the decomposition judgment ran.
#
# Signal design (memory feedback_gate_signal_and_failmode):
#   - signal = the merge act itself, not vocabulary
#   - unparseable command  => fail-CLOSED (parse-command contract)
#   - no active sprint / branch not on the board / non-merge command => fail-OPEN (no basis)
#   - review record with verdict: reject => block HARDER (a rejected branch must not merge)

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"

HOOK=block-unreviewed-merge.sh

setup_repo() {
  local tmp; tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  REPO="$(git -C "$tmp" rev-parse --show-toplevel)"
  git -C "$REPO" config user.email t@t.test
  git -C "$REPO" config user.name tester
}
active_board() {
  mkdir -p "$REPO/docs/sprint"
  printf '%s' '{"sprint":"s1","wip_limit":2,"tasks":[{"id":"T1","title":"x","branch":"feat/T1-auth","status":"in-review"},{"id":"T2","title":"y","branch":"feat/T2-api","status":"todo"}]}' > "$REPO/docs/sprint/board.json"
}
done_board() {
  mkdir -p "$REPO/docs/sprint"
  printf '%s' '{"sprint":"s1","wip_limit":2,"tasks":[{"id":"T1","branch":"feat/T1-auth","status":"done"}]}' > "$REPO/docs/sprint/board.json"
}
write_review() { # write_review <branch> <verdict-line...>
  local b="$1"; shift
  mkdir -p "$REPO/docs/sprint/reviews"
  printf '%s\n' "$@" > "$REPO/docs/sprint/reviews/$(printf '%s' "$b" | tr '/' '_').md"
}
merge_input() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' "$1" "$REPO"; }

# 1. No docs/sprint at all => merge passes (fail-open, gate not adopted).
setup_repo
RUN_DIR="$REPO"
test_case "no sprint adoption: merge passes"
run_hook "$HOOK" "$(merge_input 'git merge feat/T1-auth')"
assert_exit 0

# 2. Active sprint, merging a task branch, NO review record => blocked.
setup_repo
active_board
RUN_DIR="$REPO"
test_case "task-branch merge without review record is blocked"
run_hook "$HOOK" "$(merge_input 'git merge feat/T1-auth')"
assert_exit 2
assert_stderr_contains 'reviews/'

# 3. Review record with verdict: approve => passes.
setup_repo
active_board
write_review feat/T1-auth 'verdict: approve' '- finding: none'
RUN_DIR="$REPO"
test_case "approved review record lets the merge pass"
run_hook "$HOOK" "$(merge_input 'git merge feat/T1-auth')"
assert_exit 0

# 4. Review record with verdict: reject => blocked (must not override a rejection).
setup_repo
active_board
write_review feat/T1-auth 'verdict: reject' '- finding: broken auth check'
RUN_DIR="$REPO"
test_case "rejected review record blocks the merge"
run_hook "$HOOK" "$(merge_input 'git merge feat/T1-auth')"
assert_exit 2
assert_stderr_contains 'reject'

# 5. Record exists but carries no verdict line => not a completed review => blocked.
setup_repo
active_board
write_review feat/T1-auth '# notes only, reviewer never concluded'
RUN_DIR="$REPO"
test_case "record without verdict line is blocked"
run_hook "$HOOK" "$(merge_input 'git merge feat/T1-auth')"
assert_exit 2

# 6. Merging a branch that is NOT on the board => fail-open (no basis to demand review).
setup_repo
active_board
RUN_DIR="$REPO"
test_case "non-task branch merge passes during active sprint"
run_hook "$HOOK" "$(merge_input 'git merge hotfix/typo')"
assert_exit 0

# 7. All-done board (sprint over) => fail-open (liveness, not existence).
setup_repo
done_board
RUN_DIR="$REPO"
test_case "done board: merge passes (sprint not active)"
run_hook "$HOOK" "$(merge_input 'git merge feat/T1-auth')"
assert_exit 0

# 8. Non-merge git command => fail-open.
setup_repo
active_board
RUN_DIR="$REPO"
test_case "non-merge command passes"
run_hook "$HOOK" "$(merge_input 'git status')"
assert_exit 0

# 9. Flag with argument before the branch (-m <msg>) must not hide the branch.
setup_repo
active_board
RUN_DIR="$REPO"
test_case "merge -m message feat/T1-auth is still detected"
run_hook "$HOOK" "$(merge_input 'git merge -m integration_msg feat/T1-auth')"
assert_exit 2

# 10. --no-ff style flags are skipped, branch still detected; approval passes it.
setup_repo
active_board
write_review feat/T2-api 'verdict: approve'
RUN_DIR="$REPO"
test_case "merge --no-ff of approved branch passes"
run_hook "$HOOK" "$(merge_input 'git merge --no-ff feat/T2-api')"
assert_exit 0

# 11. Unparseable command JSON => fail-closed (parse-command contract).
setup_repo
active_board
RUN_DIR="$REPO"
test_case "unparseable hook input is fail-closed"
run_hook "$HOOK" '{"tool_name":"Bash","tool_input":{"command":"git merge feat/T1-auth'
assert_exit 2

# 12. Non-git dir => fail-open.
NOGIT="$(mktemp -d)"; mkdir -p "$NOGIT/docs/sprint"
RUN_DIR="$NOGIT"
test_case "non-git dir is fail-open"
run_hook "$HOOK" "$(printf '{"tool_name":"Bash","tool_input":{"command":"git merge feat/T1-auth"},"cwd":"%s"}' "$NOGIT")"
assert_exit 0

# --- worktree lane branches (board-independent) ---
# 実際の並列開発は board を作らない形でも起きる: Workflow サブエージェントの隔離 worktree、
# 手動の worktree 並走 (ADR 0004 / docs/incidents/2026-06-11-parallel-mode-gate-coverage)。
# 統合の関所は「どの方式で作ったか」に依存してはいけない — linked worktree に checkout
# された branch の merge は、活性 board が無くてもレビュー記録を要求する。
# opt-in は docs/sprint/ の存在 (= sprint flow 採用宣言、他 gate と同じ)。

add_worktree_branch() { # add_worktree_branch <branch> — linked worktree に checkout した branch を作る
  git -C "$REPO" commit -q --allow-empty -m base 2>/dev/null
  git -C "$REPO" worktree add -q -b "$1" "$REPO/.claude/worktrees/$(printf '%s' "$1" | tr '/' '_')" >/dev/null 2>&1
}

# 13. No board at all, branch lives in a linked worktree, no review record => blocked.
setup_repo
mkdir -p "$REPO/docs/sprint"
add_worktree_branch "lane/slack-notify"
RUN_DIR="$REPO"
test_case "worktree lane merge without review is blocked (no board needed)"
run_hook "$HOOK" "$(merge_input 'git merge lane/slack-notify')"
assert_exit 2
assert_stderr_contains 'reviews/'

# 14. Same lane with verdict: approve => passes.
setup_repo
mkdir -p "$REPO/docs/sprint"
add_worktree_branch "lane/slack-notify"
write_review "lane/slack-notify" "verdict: approve" "- 指摘なし"
RUN_DIR="$REPO"
test_case "worktree lane merge with approve passes"
run_hook "$HOOK" "$(merge_input 'git merge lane/slack-notify')"
assert_exit 0

# 15. Same lane with verdict: reject => blocked harder.
setup_repo
mkdir -p "$REPO/docs/sprint"
add_worktree_branch "lane/slack-notify"
write_review "lane/slack-notify" "verdict: reject" "- 境界条件の test 不足"
RUN_DIR="$REPO"
test_case "worktree lane merge with reject is blocked"
run_hook "$HOOK" "$(merge_input 'git merge lane/slack-notify')"
assert_exit 2
assert_stderr_contains 'REJECT'

# 16. Plain branch (no worktree, no board): merge passes — 通常の merge を一切妨げない。
setup_repo
mkdir -p "$REPO/docs/sprint"
git -C "$REPO" commit -q --allow-empty -m base
git -C "$REPO" branch hotfix/typo
RUN_DIR="$REPO"
test_case "plain branch merge passes (no worktree, no board)"
run_hook "$HOOK" "$(merge_input 'git merge hotfix/typo')"
assert_exit 0

# 17. Worktree lane but docs/sprint NOT adopted => fail-open (opt-in respected).
setup_repo
add_worktree_branch "lane/slack-notify"
RUN_DIR="$REPO"
test_case "worktree lane without sprint adoption passes (opt-in)"
run_hook "$HOOK" "$(merge_input 'git merge lane/slack-notify')"
assert_exit 0

finish

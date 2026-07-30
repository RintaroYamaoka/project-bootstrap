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

# --- ADR 0005 guard 1: an agent's verdict: approve does NOT substitute for the real suite ---
# After approve, the gate runs the detected test suite itself and blocks on failure. The only
# runner deterministically installed + controllable here is package.json's npm test (same basis
# as block-commit-if-tests-fail.test.bash). No runner => fail-open (cases 3/10/14 above still pass).

# 18. approve + a passing project suite => merge passes (the gate ran it green).
setup_repo
active_board
write_review feat/T1-auth 'verdict: approve'
printf '{"scripts":{"test":"exit 0"}}' > "$REPO/package.json"
RUN_DIR="$REPO"
test_case "approve with a passing suite merges (guard 1 ran it)"
run_hook "$HOOK" "$(merge_input 'git merge feat/T1-auth')"
assert_exit 0

# 19. approve + a FAILING project suite => blocked (agent approve cannot override real failure).
setup_repo
active_board
write_review feat/T1-auth 'verdict: approve'
printf '{"scripts":{"test":"exit 1"}}' > "$REPO/package.json"
RUN_DIR="$REPO"
test_case "approve with a failing suite is blocked (guard 1)"
run_hook "$HOOK" "$(merge_input 'git merge feat/T1-auth')"
assert_exit 2
assert_stderr_contains 'guard 1'

# --- regression: compound + path-prefixed merges (the greedy-sed / bare-token bypass) ---
# This gate used to extract the target with a greedy `sed 's/^.*git merge//'` (which sees
# only the LAST merge of a compound command) and detect only a bare `git merge` token. So
# `git merge <unreviewed> && git merge <approved>` slipped the unreviewed lane past with
# zero enforcement, and `/usr/bin/git merge <lane>` was invisible. lib/merge-targets.sh now
# walks EVERY segment and accepts path-prefixed git. (The "string proxy for an action"
# weakness the doctrine condemns for sprint vocabulary — fixed here for the merge signal.)

# 20. Compound merge must not hide an unreviewed lane behind an approved one.
setup_repo
active_board
write_review feat/T2-api 'verdict: approve'
RUN_DIR="$REPO"
test_case "compound merge does not hide an unreviewed lane behind an approved one"
run_hook "$HOOK" "$(merge_input 'git merge feat/T1-auth && git merge feat/T2-api')"
assert_exit 2
assert_stderr_contains 'reviews/'

# 21. Path-prefixed git (/usr/bin/git) must be detected, not only a bare `git` token.
setup_repo
active_board
RUN_DIR="$REPO"
test_case "path-prefixed git merge of an unreviewed lane is blocked"
run_hook "$HOOK" "$(merge_input '/usr/bin/git merge feat/T1-auth')"
assert_exit 2

# 22. Compound merge of two approved lanes still passes (no over-block).
setup_repo
active_board
write_review feat/T1-auth 'verdict: approve'
write_review feat/T2-api 'verdict: approve'
RUN_DIR="$REPO"
test_case "compound merge of two approved lanes passes"
run_hook "$HOOK" "$(merge_input 'git merge feat/T1-auth && git merge feat/T2-api')"
assert_exit 0


# ---------------------------------------------------------------------------
# New layout: docs/bootstrap/<name> (ADR 0020).
# Every fixture above builds the LEGACY docs/<name> layout, so on its own it only
# proves backward compatibility. These cases prove the gate actually arms under the
# new parent-folder layout — without them a mis-wired resolver would leave the gate
# silently fail-open (this plugin's worst fail-mode) with the whole suite still green.
# ---------------------------------------------------------------------------

active_board_new() {
  mkdir -p "$REPO/docs/bootstrap/sprint"
  printf '%s' '{"sprint":"s1","wip_limit":2,"tasks":[{"id":"T1","title":"x","branch":"feat/T1-auth","status":"in-review"}]}' > "$REPO/docs/bootstrap/sprint/board.json"
}
write_review_new() {
  local b="$1"; shift
  mkdir -p "$REPO/docs/bootstrap/sprint/reviews"
  printf '%s\n' "$@" > "$REPO/docs/bootstrap/sprint/reviews/$(printf '%s' "$b" | tr '/' '_').md"
}

setup_repo
active_board_new
RUN_DIR="$REPO"
test_case "new layout: task-branch merge without a review record is blocked"
run_hook "$HOOK" "$(merge_input 'git merge feat/T1-auth')"
assert_exit 2
assert_stderr_contains 'reviews/'

setup_repo
active_board_new
write_review_new feat/T1-auth 'verdict: approve' '- finding: none'
RUN_DIR="$REPO"
test_case "new layout: an approved review record lets the merge pass"
run_hook "$HOOK" "$(merge_input 'git merge feat/T1-auth')"
assert_exit 0

setup_repo
active_board_new
write_review_new feat/T1-auth 'verdict: reject' '- finding: broken auth check'
RUN_DIR="$REPO"
test_case "new layout: a rejection still blocks"
run_hook "$HOOK" "$(merge_input 'git merge feat/T1-auth')"
assert_exit 2
assert_stderr_contains 'reject'

# Half-migrated: board in the new layout, review record left behind in the legacy one.
# The new layout wins, so the stale legacy approval must NOT clear the gate.
setup_repo
active_board_new
write_review feat/T1-auth 'verdict: approve' '- finding: none'
RUN_DIR="$REPO"
test_case "half-migrated: a legacy-path approval does not clear the new-layout gate"
run_hook "$HOOK" "$(merge_input 'git merge feat/T1-auth')"
assert_exit 2

finish

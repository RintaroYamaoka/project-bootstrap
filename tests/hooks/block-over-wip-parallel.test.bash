#!/usr/bin/env bash
# Tests for hooks/block-over-wip-parallel.sh — the WIP-limit fail-closed gate (ADR 0005 guard 3).
#
# Before this hook .bootstrap-wip was display-only (resolve-wip-limit.sh always fell open);
# nothing blocked when parallel breadth exceeded it. The hook signals on the ACT of opening a
# new parallel lane — `git worktree add` — and blocks (exit 2) when the existing linked-worktree
# count already meets the declared wip_limit. It is the observable lane-creation path; per ADR
# 0005 a hook cannot see a Workflow's internal isolation worktrees, so the integration choke
# (block-unreviewed-merge.sh: every lane needs review + a real suite run) remains the net there.
#
# Signal/fail-mode (memory feedback_gate_signal_and_failmode):
#   - unparseable command  => fail-CLOSED (parse-command contract)
#   - non-worktree-add / non-git / docs/sprint not adopted / .bootstrap-wip undeclared or
#     unparseable => fail-OPEN (no basis; opt-in preserved — only a declared limit blocks)

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"

HOOK=block-over-wip-parallel.sh

setup_repo() {
  local tmp; tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  REPO="$(git -C "$tmp" rev-parse --show-toplevel)"
  git -C "$REPO" config user.email t@t.test
  git -C "$REPO" config user.name tester
  git -C "$REPO" commit -q --allow-empty -m base
}
adopt_sprint() { mkdir -p "$REPO/docs/sprint"; }
set_wip() { printf '%s\n' "$1" > "$REPO/.bootstrap-wip"; }
add_lane() { # add_lane <branch> — create one linked worktree
  git -C "$REPO" worktree add -q -b "$1" "$REPO/.claude/worktrees/$(printf '%s' "$1" | tr '/' '_')" >/dev/null 2>&1
}
wt_input() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' "$1" "$REPO"; }

# 1. docs/sprint not adopted => fail-open even with a declared limit and lanes at cap.
setup_repo
set_wip 1
add_lane lane/a
RUN_DIR="$REPO"
test_case "no sprint adoption: worktree add passes (opt-in)"
run_hook "$HOOK" "$(wt_input 'git worktree add -b feat/x ../wt-x')"
assert_exit 0

# 2. Adopted, limit 2, zero linked worktrees => under cap => passes.
setup_repo
adopt_sprint
set_wip 2
RUN_DIR="$REPO"
test_case "under wip_limit: worktree add passes"
run_hook "$HOOK" "$(wt_input 'git worktree add -b feat/x ../wt-x')"
assert_exit 0

# 3. Adopted, limit 2, already 2 linked worktrees => at cap => blocked.
setup_repo
adopt_sprint
set_wip 2
add_lane lane/a
add_lane lane/b
RUN_DIR="$REPO"
test_case "at wip_limit: a further worktree add is blocked"
run_hook "$HOOK" "$(wt_input 'git worktree add -b feat/c ../wt-c')"
assert_exit 2
assert_stderr_contains "WIP"

# 4. Adopted, limit 3, only 2 linked => still under cap => passes.
setup_repo
adopt_sprint
set_wip 3
add_lane lane/a
add_lane lane/b
RUN_DIR="$REPO"
test_case "below a higher wip_limit: passes"
run_hook "$HOOK" "$(wt_input 'git worktree add -b feat/c ../wt-c')"
assert_exit 0

# 5. Adopted but .bootstrap-wip undeclared => fail-open (opt-in: only a declared limit blocks).
setup_repo
adopt_sprint
add_lane lane/a
add_lane lane/b
RUN_DIR="$REPO"
test_case "no .bootstrap-wip declared: passes (opt-in)"
run_hook "$HOOK" "$(wt_input 'git worktree add -b feat/c ../wt-c')"
assert_exit 0

# 6. Adopted, .bootstrap-wip garbage => fail-open (unparseable limit does not block).
setup_repo
adopt_sprint
set_wip 'abc'
add_lane lane/a
add_lane lane/b
RUN_DIR="$REPO"
test_case "unparseable .bootstrap-wip: passes (fail-open)"
run_hook "$HOOK" "$(wt_input 'git worktree add -b feat/c ../wt-c')"
assert_exit 0

# 7. Non-worktree-add command => fail-open even at cap.
setup_repo
adopt_sprint
set_wip 1
add_lane lane/a
RUN_DIR="$REPO"
test_case "non-worktree-add command passes"
run_hook "$HOOK" "$(wt_input 'git worktree list')"
assert_exit 0

# 8. `git worktree remove` is not an add => passes.
setup_repo
adopt_sprint
set_wip 1
add_lane lane/a
RUN_DIR="$REPO"
test_case "git worktree remove passes (not a lane creation)"
run_hook "$HOOK" "$(wt_input 'git worktree remove ../wt-a')"
assert_exit 0

# 9. Unparseable command JSON => fail-closed.
setup_repo
adopt_sprint
set_wip 1
RUN_DIR="$REPO"
test_case "unparseable hook input is fail-closed"
run_hook "$HOOK" '{"tool_name":"Bash","tool_input":{"command":"git worktree add ../wt'
assert_exit 2

# 10. Non-git dir => fail-open.
NOGIT="$(mktemp -d)"; mkdir -p "$NOGIT/docs/sprint"; printf '1\n' > "$NOGIT/.bootstrap-wip"
RUN_DIR="$NOGIT"
test_case "non-git dir is fail-open"
run_hook "$HOOK" "$(printf '{"tool_name":"Bash","tool_input":{"command":"git worktree add ../wt"},"cwd":"%s"}' "$NOGIT")"
assert_exit 0

finish

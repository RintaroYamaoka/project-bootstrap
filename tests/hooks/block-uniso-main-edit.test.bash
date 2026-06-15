#!/usr/bin/env bash
# Tests for hooks/block-uniso-main-edit.sh — mutation lane の worktree 隔離強制 (ADR 0005 guard 2).
#
# Gap this closes: block-out-of-lane-edit.sh only acts inside a worktree that HAS a .bootstrap-lane
# (a lane). Editing a SOURCE file in the shared MAIN worktree while parallel lanes are active fell
# open — exactly the un-isolated parallel mutation worktree isolation exists to prevent (a Workflow
# subagent writing in the shared tree). This gate blocks that, but only with a PRECISE signal so it
# never cries wolf on the legitimate lead: it fires ONLY when (a) docs/sprint adopted, (b) we are in
# the MAIN worktree, (c) active linked-worktree lanes exist, (d) NOT mid-integration (no MERGE_HEAD /
# rebase / cherry-pick / revert — the lead resolving conflicts must pass), (e) the target is a source
# face (docs/config/test/sprint-state all fail open). 誤検知 > false negative (ADR 0004), so every
# ambiguous case fails OPEN.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"

HOOK=block-uniso-main-edit.sh

setup_repo() {
  local tmp; tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  REPO="$(git -C "$tmp" rev-parse --show-toplevel)"
  git -C "$REPO" config user.email t@t.test
  git -C "$REPO" config user.name tester
  git -C "$REPO" commit -q --allow-empty -m base
}
adopt_sprint() { mkdir -p "$REPO/docs/sprint"; }
add_lane() { # add_lane <branch> — one linked worktree; echoes its path
  local wt="$REPO/.claude/worktrees/$(printf '%s' "$1" | tr '/' '_')"
  git -C "$REPO" worktree add -q -b "$1" "$wt" >/dev/null 2>&1
  printf '%s' "$wt"
}
edit_input() { printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"},"cwd":"%s"}' "$1" "${RUN_DIR}"; }

# 1. docs/sprint not adopted => fail-open even with lanes + a source edit in main.
setup_repo
add_lane lane/a >/dev/null
RUN_DIR="$REPO"
test_case "no sprint adoption: main-tree source edit passes (opt-in)"
run_hook "$HOOK" "$(edit_input "$REPO/src/x.ts")"
assert_exit 0

# 2. Adopted but no linked lanes => fail-open (no parallel mutation to collide with).
setup_repo
adopt_sprint
RUN_DIR="$REPO"
test_case "no active lanes: main-tree source edit passes"
run_hook "$HOOK" "$(edit_input "$REPO/src/x.ts")"
assert_exit 0

# 3. Adopted + active lane + source edit in MAIN tree + not mid-merge => BLOCKED.
setup_repo
adopt_sprint
add_lane lane/a >/dev/null
RUN_DIR="$REPO"
test_case "main-tree source edit during active lanes is blocked"
run_hook "$HOOK" "$(edit_input "$REPO/src/x.ts")"
assert_exit 2
assert_stderr_contains "isolation"

# 4. Same, but mid-merge (lead resolving conflicts) => fail-open.
setup_repo
adopt_sprint
add_lane lane/a >/dev/null
git -C "$REPO" rev-parse HEAD > "$REPO/.git/MERGE_HEAD"
RUN_DIR="$REPO"
test_case "mid-merge conflict resolution passes (lead integrating)"
run_hook "$HOOK" "$(edit_input "$REPO/src/x.ts")"
assert_exit 0

# 5. Same active-lane state, but editing a DOC (not a source face) => fail-open.
setup_repo
adopt_sprint
add_lane lane/a >/dev/null
RUN_DIR="$REPO"
test_case "main-tree doc edit passes (not a source face)"
run_hook "$HOOK" "$(edit_input "$REPO/README.md")"
assert_exit 0

# 6. Editing sprint runtime state (board.json) in main is never blocked.
setup_repo
adopt_sprint
add_lane lane/a >/dev/null
RUN_DIR="$REPO"
test_case "main-tree docs/sprint state edit passes"
run_hook "$HOOK" "$(edit_input "$REPO/docs/sprint/board.json")"
assert_exit 0

# 7. Editing inside a LANE worktree (has .bootstrap-lane) => fail-open here (block-out-of-lane owns it).
setup_repo
adopt_sprint
WT="$(add_lane lane/a)"
printf '%s\n' 'src/**' > "$WT/.bootstrap-lane"
RUN_DIR="$WT"
test_case "edit inside a lane worktree is not this gate's job"
run_hook "$HOOK" "$(edit_input "$WT/src/x.ts")"
assert_exit 0

# 8. No file_path in payload => fail-open.
setup_repo
adopt_sprint
add_lane lane/a >/dev/null
RUN_DIR="$REPO"
test_case "missing file_path is fail-open"
run_hook "$HOOK" '{"tool_name":"Edit","tool_input":{}}'
assert_exit 0

# 9. Non-git dir => fail-open.
NOGIT="$(mktemp -d)"; mkdir -p "$NOGIT/docs/sprint"
RUN_DIR="$NOGIT"
test_case "non-git dir is fail-open"
run_hook "$HOOK" "$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/src/x.ts"},"cwd":"%s"}' "$NOGIT" "$NOGIT")"
assert_exit 0

# 10. Existing-file source edit (not just new) is also caught (guard 2 covers edits, not only creation).
setup_repo
adopt_sprint
add_lane lane/a >/dev/null
mkdir -p "$REPO/src"; printf 'x\n' > "$REPO/src/existing.ts"
RUN_DIR="$REPO"
test_case "existing source-file edit in main during lanes is blocked"
run_hook "$HOOK" "$(edit_input "$REPO/src/existing.ts")"
assert_exit 2

finish

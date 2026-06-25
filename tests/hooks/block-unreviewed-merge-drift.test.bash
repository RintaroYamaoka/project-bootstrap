#!/usr/bin/env bash
# Tests for the two integration-drift additions to hooks/block-unreviewed-merge.sh
# (LANE MG): D6 (stale-base block, fail-CLOSED) and D5 (leftover-worktree advisory).
#
# Why these exist (incident 2026-06-25): a lane branch that is STALE relative to what it
# is being merged INTO can silently REVERT already-merged fixes. The merge destination at
# the PreToolUse moment is the current HEAD (the branch being merged into). git diff/status
# is computed vs HEAD, not vs main, so a 17-commit-behind lane whose staged edits revert
# merged fixes looks clean and slips past the review+suite path. D6 makes "the lane contains
# the destination tip" a fail-closed precondition (merge-base --is-ancestor HEAD <lane>);
# rebase is mechanical, not a judgment, so demanding it is safe. D5 is a NON-blocking nudge
# at the same teardown moment to remove merged-but-leftover worktrees (a leftover tree may
# hold uncommitted work, so coercing removal is the cry-wolf failure mode 2026-05-29 records).
#
# Signal / fail-mode coverage required by the lane:
#   (a) merging a lane BEHIND the destination is blocked (exit 2) with a rebase instruction
#   (b) a lane that already contains the destination tip passes the D6 check
#   (c) a non-lane / unresolvable case fails OPEN (no false block)
#   (d) the D5 advisory prints when a merged leftover worktree exists but does NOT block
#
# Testing this hook needs real git state, so we build minimal temp-git fixtures (init main +
# a lane branch, advance main so the lane is behind, etc.), following the helper.bash idiom
# used by block-unreviewed-merge.test.bash / repo-drift.test.bash. We exercise the new D6
# ancestor check and D5 notice both end-to-end (through the hook) and via the small sourceable
# functions the hook factors them into (d6_lane_contains_dest / d6_divergence_count).

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"

HOOK=block-unreviewed-merge.sh

git config --global user.email >/dev/null 2>&1 || git config --global user.email "test@example.com"
git config --global user.name  >/dev/null 2>&1 || git config --global user.name  "test"

# Source ONLY the hook's functions (the sentinel suppresses the cat/main body so sourcing
# does not block on stdin). This lets us unit-test the factored D6 helpers against a real repo.
BUM_SOURCE_ONLY=1 source "$(cd "$DIR/../../hooks" && pwd)/$HOOK"

# --- fixture helpers -----------------------------------------------------------------

setup_repo() {
  local tmp; tmp="$(mktemp -d)"
  git -C "$tmp" init -q -b main
  REPO="$(git -C "$tmp" rev-parse --show-toplevel)"
  git -C "$REPO" config user.email t@t.test
  git -C "$REPO" config user.name tester
  git -C "$REPO" commit -q --allow-empty -m base
  mkdir -p "$REPO/docs/sprint"            # opt-in: sprint flow adopted
}
# approve_review — write an approving review record so the D6 precondition is the only gate
# left between the lane and the merge (an approved+tested lane that is stale must still block).
approve_review() {
  local b="$1"
  mkdir -p "$REPO/docs/sprint/reviews"
  printf 'verdict: approve\n- 指摘なし\n' > "$REPO/docs/sprint/reviews/$(printf '%s' "$b" | tr '/' '_').md"
}
# lane_branch — make <branch> a linked-worktree lane (board-independent path) at the given ref.
lane_branch() {
  local b="$1" ref="${2:-HEAD}"
  git -C "$REPO" worktree add -q -b "$b" "$REPO/.wt/$(printf '%s' "$b" | tr '/' '_')" "$ref" >/dev/null 2>&1
}
# advance_main — add N empty commits on main (moves the destination tip past older lanes).
advance_main() {
  local n="$1" i
  for ((i = 0; i < n; i++)); do
    git -C "$REPO" commit -q --allow-empty -m "main$i"
  done
}
merge_input() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' "$1" "$REPO"; }

# =====================================================================================
# D6 — unit tests of the factored ancestor / divergence helpers (real temp git)
# =====================================================================================

# A lane branched off base, then main advanced 2 commits → lane is BEHIND HEAD.
setup_repo
BASE="$(git -C "$REPO" rev-parse HEAD)"
lane_branch "lane/stale" "$BASE"
advance_main 2                            # HEAD (main) now 2 ahead of lane/stale

test_case "d6_lane_contains_dest: stale lane does NOT contain destination → 1"
if d6_lane_contains_dest "$REPO" HEAD "lane/stale"; then assert_eq stale-pass should-fail; else assert_eq blocked blocked; fi

test_case "d6_divergence_count: destination has 2 commits the stale lane lacks"
# format: "<dest-only>\t<lane-only>" from rev-list --left-right --count HEAD...<lane>
assert_eq "2	0" "$(d6_divergence_count "$REPO" HEAD "lane/stale")"

# A lane that already contains the destination tip (branched off current HEAD) → fresh.
lane_branch "lane/fresh" "HEAD"
test_case "d6_lane_contains_dest: fresh lane (contains destination) → 0"
if d6_lane_contains_dest "$REPO" HEAD "lane/fresh"; then assert_eq ancestor ancestor; else assert_eq fresh-blocked should-pass; fi

test_case "d6_lane_contains_dest: unresolvable lane ref → fail-OPEN (treated as contains)"
# An unknown ref must NOT be reported as stale (cannot compute ⇒ never false-block).
if d6_lane_contains_dest "$REPO" HEAD "lane/does-not-exist"; then assert_eq open open; else assert_eq unresolved-blocked should-pass; fi

# =====================================================================================
# D6 — end-to-end through the hook (approved + suiteless so D6 is the deciding gate)
# =====================================================================================

# (a) merging a lane BEHIND the destination is blocked (exit 2) with a rebase instruction.
setup_repo
BASE="$(git -C "$REPO" rev-parse HEAD)"
lane_branch "lane/stale" "$BASE"
approve_review "lane/stale"
advance_main 3                            # destination now 3 ahead of the lane
RUN_DIR="$REPO"
test_case "(a) approved-but-stale lane merge is blocked (D6 fail-closed)"
run_hook "$HOOK" "$(merge_input 'git merge lane/stale')"
assert_exit 2
assert_stderr_contains "rebase"
assert_stderr_contains "lane/stale"

# (b) a lane that already contains the destination tip passes the D6 check.
setup_repo
lane_branch "lane/fresh" "HEAD"          # branched off the current destination tip
approve_review "lane/fresh"
RUN_DIR="$REPO"
test_case "(b) fresh lane (contains destination) passes D6"
run_hook "$HOOK" "$(merge_input 'git merge lane/fresh')"
assert_exit 0

# (c1) a NON-lane branch is unaffected by D6 → fail-open even if behind.
setup_repo
BASE="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" branch hotfix/typo "$BASE"  # plain branch, NOT a lane (no worktree, no board)
advance_main 2
RUN_DIR="$REPO"
test_case "(c1) non-lane behind branch is NOT blocked by D6 (fail-open)"
run_hook "$HOOK" "$(merge_input 'git merge hotfix/typo')"
assert_exit 0

# (c2) lane target that cannot be resolved (deleted ref) → D6 cannot compute → fail-open.
# Build a board lane so HAS_LANE fires, but merge a token that resolves to no commit.
setup_repo
printf '%s' '{"sprint":"s","wip_limit":2,"tasks":[{"id":"T","branch":"feat/ghost","status":"in-review"}]}' > "$REPO/docs/sprint/board.json"
approve_review "feat/ghost"              # review present so only D6 could speak
RUN_DIR="$REPO"
test_case "(c2) lane whose ref does not resolve fails OPEN in D6 (no false block)"
run_hook "$HOOK" "$(merge_input 'git merge feat/ghost')"
# feat/ghost has no branch/commit → ancestor relation cannot be computed → D6 must not block.
# (The suite step is fail-open with no runner, so a non-2 exit proves D6 did not false-block.)
assert_exit 0

# =====================================================================================
# D5 — leftover-worktree advisory: prints but NEVER changes the exit code
# =====================================================================================

# (d) a merged-but-leftover worktree exists at the integration moment. Merging a *fresh*
# approved lane must still PASS (exit 0) while the D5 advisory is printed to stderr.
setup_repo
git -C "$REPO" update-ref refs/remotes/origin/main "$(git -C "$REPO" rev-parse HEAD)"  # local main ref for drift_main_ref
# a leftover lane already merged into origin/main (tip == origin/main), still checked out
git -C "$REPO" branch lane/leftover "$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" worktree add -q "$REPO/.wt/leftover" lane/leftover >/dev/null 2>&1
# the lane we are actually merging now — fresh, approved
lane_branch "lane/fresh" "HEAD"
approve_review "lane/fresh"
RUN_DIR="$REPO"
test_case "(d) D5 advisory prints for a leftover worktree but does NOT block"
run_hook "$HOOK" "$(merge_input 'git merge lane/fresh')"
assert_exit 0
assert_stderr_contains "worktree remove"
assert_stderr_contains "lane/leftover"

# D5 silence: no MERGED-but-leftover worktrees → no advisory bloat. The only checked-out
# lane here (lane/fresh) carries its own commit ahead of origin/main, so it is ACTIVE
# (not yet merged) and must not be flagged as a leftover.
setup_repo
git -C "$REPO" update-ref refs/remotes/origin/main "$(git -C "$REPO" rev-parse HEAD)"
lane_branch "lane/fresh" "HEAD"
git -C "$REPO/.wt/lane_fresh" -c user.email=t@t.test -c user.name=tester commit -q --allow-empty -m work
approve_review "lane/fresh"
RUN_DIR="$REPO"
test_case "D5 is silent when there are no leftover worktrees"
run_hook "$HOOK" "$(merge_input 'git merge lane/fresh')"
assert_exit 0
case "$HOOK_STDERR" in
  *"worktree remove"*) assert_eq "no-d5-advisory" "advisory-leaked" ;;
  *) assert_eq quiet quiet ;;
esac

finish

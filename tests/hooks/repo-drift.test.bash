#!/usr/bin/env bash
# Unit tests for hooks/lib/repo-drift.sh — the SessionStart doctor's "repo drift" judge.
#
# Two silent states the doctor surfaces (visibility, not enforcement): HEAD behind the
# main remote-tracking ref (stale-checkout class) and merged-but-leftover worktrees
# (lane teardown skipped). We build throwaway repos with a LOCAL refs/remotes/origin/main
# (no network — the lib never fetches) and assert behind counts, ref resolution, the
# merged-worktree listing, and the composed report's silence/speech.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"
source "$(cd "$DIR/../../hooks" && pwd)/lib/repo-drift.sh"

git config --global user.email >/dev/null 2>&1 || git config --global user.email "test@example.com"
git config --global user.name  >/dev/null 2>&1 || git config --global user.name  "test"

# mkrepo — a fresh repo with one commit on main, echoes its path.
mkrepo() {
  local r; r="$(mktemp -d)"
  git -C "$r" init -q -b main
  git -C "$r" -c user.email=t@e.x -c user.name=t commit -q --allow-empty -m c0
  printf '%s' "$r"
}
# advance — add N empty commits on the current branch of <repo>, echo the new HEAD sha.
advance() {
  local r="$1" n="$2" i
  for ((i = 0; i < n; i++)); do
    git -C "$r" -c user.email=t@e.x -c user.name=t commit -q --allow-empty -m "x$i"
  done
  git -C "$r" rev-parse HEAD
}

# --- drift_main_ref resolution -------------------------------------------------------
R="$(mkrepo)"
test_case "no remote-tracking ref → drift_main_ref returns 1"
if drift_main_ref "$R" >/dev/null; then assert_eq ret1 ret0; else assert_eq ret1 ret1; fi

git -C "$R" update-ref refs/remotes/origin/main "$(git -C "$R" rev-parse HEAD)"
test_case "origin/main present → resolved"
assert_eq "origin/main" "$(drift_main_ref "$R")"

# --- behind_count --------------------------------------------------------------------
# Pin origin/main ahead of HEAD by 2 commits: branch, advance the ref, reset HEAD back.
R="$(mkrepo)"
BASE="$(git -C "$R" rev-parse HEAD)"
AHEAD="$(advance "$R" 2)"
git -C "$R" update-ref refs/remotes/origin/main "$AHEAD"
git -C "$R" reset -q --hard "$BASE"
test_case "HEAD two commits behind origin/main"
assert_eq "2" "$(behind_count "$R" origin/main)"

test_case "HEAD level with ref → behind 0"
git -C "$R" reset -q --hard "$AHEAD"
assert_eq "0" "$(behind_count "$R" origin/main)"

# --- merged_worktree_lines -----------------------------------------------------------
R="$(mkrepo)"
HEAD0="$(git -C "$R" rev-parse HEAD)"
git -C "$R" update-ref refs/remotes/origin/main "$HEAD0"
# a lane whose tip is already in origin/main (== HEAD0) → merged → should be listed
git -C "$R" branch feat-done "$HEAD0"
WT_DONE="$(mktemp -d)/done"; git -C "$R" worktree add -q "$WT_DONE" feat-done
# a lane with a commit NOT in origin/main → active → should NOT be listed
git -C "$R" branch feat-active "$HEAD0"
WT_ACTIVE="$(mktemp -d)/active"; git -C "$R" worktree add -q "$WT_ACTIVE" feat-active
git -C "$WT_ACTIVE" -c user.email=t@e.x -c user.name=t commit -q --allow-empty -m ahead

LINES="$(merged_worktree_lines "$R" origin/main)"
test_case "merged lane is listed"
case "$LINES" in *feat-done*) assert_eq found found ;; *) assert_eq "feat-done listed" "missing" ;; esac
test_case "active (unmerged) lane is not listed"
case "$LINES" in *feat-active*) assert_eq "feat-active absent" "present" ;; *) assert_eq absent absent ;; esac
test_case "main branch worktree is never flagged"
case "$LINES" in *"branch main "*) assert_eq "main absent" "present" ;; *) assert_eq absent absent ;; esac

# --- drift_report composition --------------------------------------------------------
R="$(mkrepo)"
git -C "$R" update-ref refs/remotes/origin/main "$(git -C "$R" rev-parse HEAD)"
test_case "no drift → report is silent"
assert_eq "" "$(drift_report "$R")"

# behind only
R="$(mkrepo)"; BASE="$(git -C "$R" rev-parse HEAD)"; AHEAD="$(advance "$R" 1)"
git -C "$R" update-ref refs/remotes/origin/main "$AHEAD"; git -C "$R" reset -q --hard "$BASE"
REP="$(drift_report "$R")"
test_case "behind → report mentions 遅れ"
case "$REP" in *"遅れ"*) assert_eq spoke spoke ;; *) assert_eq "遅れ present" missing ;; esac

# leftover worktree only
R="$(mkrepo)"; H="$(git -C "$R" rev-parse HEAD)"; git -C "$R" update-ref refs/remotes/origin/main "$H"
git -C "$R" branch feat-old "$H"; WT="$(mktemp -d)/old"; git -C "$R" worktree add -q "$WT" feat-old
REP="$(drift_report "$R")"
test_case "leftover worktree → report mentions worktree teardown"
case "$REP" in *"worktree remove"*) assert_eq spoke spoke ;; *) assert_eq "teardown present" missing ;; esac

test_case "non-git dir → report silent"
assert_eq "" "$(drift_report "$(mktemp -d)")"

finish

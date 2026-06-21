#!/usr/bin/env bash
# Unit tests for hooks/lib/merge-targets.sh — the shared merge-target enumerator for the
# two integration gates (block-unreviewed-merge, block-merge-if-verification-unclosed).
#
# The bug this replaces: both gates used `sed 's/^.*git merge//'` (greedy → only the LAST
# merge of a compound command) and a bare-`git merge` token detector. So
#   git merge A && git merge B   inspected only B
#   /usr/bin/git merge A         was invisible
# letting an un-reviewed / un-verified lane integrate past the gate. This lib walks every
# segment and accepts path-prefixed git.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"
source "$(cd "$DIR/../../hooks" && pwd)/lib/merge-targets.sh"

# targets <command> — join enumerated targets with commas for a stable assertion.
targets() { merge_target_branches "$1" | paste -sd, -; }
has_merge() { if cmd_has_git_merge "$1"; then echo yes; else echo no; fi; }

# --- cmd_has_git_merge -------------------------------------------------------------
test_case "bare git merge is detected"
assert_eq yes "$(has_merge 'git merge feat/x')"

test_case "path-prefixed /usr/bin/git merge is detected (the bypass)"
assert_eq yes "$(has_merge '/usr/bin/git merge feat/x')"

test_case "./git merge is detected"
assert_eq yes "$(has_merge './git merge feat/x')"

test_case "git merge inside a compound command is detected"
assert_eq yes "$(has_merge 'echo hi && git merge feat/x')"

test_case "mygit merge is NOT a git merge (no false trigger)"
assert_eq no "$(has_merge 'mygit merge feat/x')"

test_case "git status is not a merge"
assert_eq no "$(has_merge 'git status')"

# --- merge_target_branches: the core bug -------------------------------------------
test_case "single merge yields its branch"
assert_eq 'feat/x' "$(targets 'git merge feat/x')"

test_case "compound '&&' merge yields BOTH branches (greedy-sed regression)"
assert_eq 'feat/a,feat/b' "$(targets 'git merge feat/a && git merge feat/b')"

test_case "compound ';' merge without surrounding spaces yields both"
assert_eq 'feat/a,feat/b' "$(targets 'git merge feat/a;git merge feat/b')"

test_case "path-prefixed git merge yields its branch (token regression)"
assert_eq 'feat/x' "$(targets '/usr/bin/git merge feat/x')"

# --- merge_target_branches: flags & values must not be read as branches ------------
test_case "-m <message> is skipped, the branch is still found"
assert_eq 'feat/x' "$(targets 'git merge -m integration_msg feat/x')"

test_case "--no-ff style flags are skipped"
assert_eq 'feat/x' "$(targets 'git merge --no-ff feat/x')"

test_case "octopus merge yields every positional branch"
assert_eq 'feat/a,feat/b' "$(targets 'git merge feat/a feat/b')"

# --- merge_target_branches: no false positives from a following non-merge command --
test_case "a branch echoed after '&&' is NOT read as a merge target"
assert_eq 'feat/a' "$(targets 'git merge feat/a && echo feat/b')"

test_case "a non-merge command yields no targets"
assert_eq '' "$(targets 'git status')"

finish

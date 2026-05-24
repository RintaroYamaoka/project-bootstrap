#!/usr/bin/env bash
# Characterization tests for hooks/block-dangerous-git-ops.sh
#
# The hook is a PreToolUse-on-Bash guard. It parses the Bash tool_input.command
# string (pure string matching — no git repo needed) and blocks (exit 2)
# destructive git ops that can erase a parallel session's work, while letting
# safe variants through (exit 0). The critical boundary is force push:
# `--force` / `-f` block, but `--force-with-lease` (conflict-detecting) passes.
#
# These tests pin the hook's ACTUAL behavior, not its aspiration. Where the
# source under-blocks relative to its own header comment, the test encodes the
# real (passing) result and flags the gap in a comment — see CLEAN GAP below.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"

# input_json <command> — minimal PreToolUse Bash payload. The hook reads only
# tool_input.command, so no transcript/cwd/git repo is required.
input_json() {
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1"
}

# expect_block <command> — assert the hook blocks (exit 2) and emits its banner.
expect_block() {
  test_case "BLOCK: $1"
  run_hook block-dangerous-git-ops.sh "$(input_json "$1")"
  assert_exit 2
  assert_stderr_contains "blocking destructive git op"
}

# expect_pass <command> — assert the hook passes through (exit 0).
expect_pass() {
  test_case "PASS: $1"
  run_hook block-dangerous-git-ops.sh "$(input_json "$1")"
  assert_exit 0
}

# ---------------------------------------------------------------------------
# BLOCK side — destructive ops that can erase others' work.
# ---------------------------------------------------------------------------

# reset --hard wipes all uncommitted work (incl. a parallel session's WIP).
expect_block 'git reset --hard'
expect_block 'git reset --hard HEAD~1'

# force push rewrites remote history, dropping others' pushed commits.
expect_block 'git push -f'
expect_block 'git push --force'
expect_block 'git push --force origin main'

# checkout -- discards unstaged changes (whole tree or a single pathspec).
expect_block 'git checkout -- .'
expect_block 'git checkout -- path'   # source blocks any `-- <path>`, not just `.`

# restore reverts tracked files; `.` / `--staged .` hit the whole cwd.
expect_block 'git restore .'
expect_block 'git restore --staged .'

# clean -f deletes untracked files (a parallel session's new files).
# NOTE: only the bare `-f` token blocks here; clustered forms see CLEAN GAP below.
expect_block 'git clean -f'

# branch -D force-deletes a branch even if unmerged.
expect_block 'git branch -D feature'

# ---------------------------------------------------------------------------
# PASS side — safe variants and the critical force-with-lease boundary.
# ---------------------------------------------------------------------------

# THE critical boundary: --force-with-lease is conflict-detecting → allowed,
# even though the substring "--force" appears. The hook explicitly exempts it.
expect_pass 'git push --force-with-lease'
expect_pass 'git push --force-with-lease origin feat/x'

# reset without --hard keeps the working tree → safe.
expect_pass 'git reset --soft HEAD~1'
expect_pass 'git reset HEAD~1'          # default (mixed) reset, no tree wipe

# Plain branch switch (no `-- `) is not a discard.
expect_pass 'git checkout feature-branch'

# Lowercase -d only deletes a *merged* branch (git refuses unmerged) → safe.
expect_pass 'git branch -d merged'

# Read-only / unrelated commands.
expect_pass 'git status'
expect_pass 'ls -la'                    # non-git command short-circuits at exit 0

# ---------------------------------------------------------------------------
# clean: any flag cluster CONTAINING f/F is destructive and must block,
# regardless of where f sits in the cluster. `-fd` (untracked dirs) and `-fx`
# (ignored + untracked) are the canonical destructive forms and are advertised
# as blocked in the hook header. Earlier the regex anchored f at the cluster
# END and let `-fd` / `-fx` slip through — that under-block bug is fixed.
# ---------------------------------------------------------------------------
expect_block 'git clean -fd'   # deletes untracked dirs
expect_block 'git clean -fx'   # deletes ignored + untracked
expect_block 'git clean -df'   # f not last in cluster
expect_block 'git clean --force'
# `-d` alone (no -f) does not delete anything in git clean, so it stays unblocked.
expect_pass 'git clean -d'

finish

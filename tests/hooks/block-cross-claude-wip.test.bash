#!/usr/bin/env bash
# Tests for hooks/block-cross-claude-wip.sh
#
# Regression origin: a real parallel-dev incident. Two Claude terminals shared one
# working tree (= one .git/index). Terminal B's `git commit --amend` swept Terminal A's
# 14 staged files (docs + tests) into commit 67c2bad with the wrong message, which was
# then pushed to origin/main. The hook DID block plain `git commit` of foreign staged
# files, but block-cross-claude-wip.sh exempted `--amend` entirely — that exemption was
# the hole. These tests pin the fix and guard against over-blocking message-only amend.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"

# setup_repo — fresh temp git repo with one seed commit. Sets REPO to git's own
# toplevel view so that paths in the fake transcript share git's path prefix
# (avoids msys /tmp vs C:/.../Temp mismatch on Windows).
setup_repo() {
  local tmp; tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  REPO="$(git -C "$tmp" rev-parse --show-toplevel)"
  git -C "$REPO" config user.email t@t.test
  git -C "$REPO" config user.name tester
  echo seed > "$REPO/seed.txt"
  git -C "$REPO" add seed.txt
  git -C "$REPO" commit -qm seed
}

# make_transcript <self-edited-path>... — a JSONL transcript whose Edit tool_use
# entries declare exactly the given files as edited by "this session".
make_transcript() {
  TRANSCRIPT="$(mktemp)"
  : > "$TRANSCRIPT"
  local p
  for p in "$@"; do
    printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"%s"}}]}}\n' "$p" >> "$TRANSCRIPT"
  done
}

# input_json <command> <transcript-path> <cwd>
input_json() {
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"transcript_path":"%s","cwd":"%s"}' "$1" "$2" "$3"
}

# 1. The incident itself: --amend with a foreign file in the shared index must block.
setup_repo
echo foreign > "$REPO/foreign.txt"
git -C "$REPO" add foreign.txt          # staged by "another session", NOT self-edited
make_transcript "$REPO/mine.txt"         # this session only touched mine.txt
RUN_DIR="$REPO"
test_case "amend with foreign staged file is blocked"
run_hook block-cross-claude-wip.sh "$(input_json 'git commit --amend -m x' "$TRANSCRIPT" "$REPO")"
assert_exit 2

# 2. Do not over-block: message-only amend (clean index) must pass.
setup_repo
make_transcript "$REPO/mine.txt"
RUN_DIR="$REPO"
test_case "amend with clean index (message-only) passes"
run_hook block-cross-claude-wip.sh "$(input_json 'git commit --amend -m newmsg' "$TRANSCRIPT" "$REPO")"
assert_exit 0

# 3. Regression guard: plain commit of a foreign staged file still blocks.
setup_repo
echo foreign > "$REPO/foreign.txt"
git -C "$REPO" add foreign.txt
make_transcript "$REPO/mine.txt"
RUN_DIR="$REPO"
test_case "plain commit with foreign staged file is blocked"
run_hook block-cross-claude-wip.sh "$(input_json 'git commit -m x' "$TRANSCRIPT" "$REPO")"
assert_exit 2

# 4. Commit of only self-edited files passes.
setup_repo
echo mine > "$REPO/mine.txt"
git -C "$REPO" add mine.txt
make_transcript "$REPO/mine.txt"
RUN_DIR="$REPO"
test_case "commit of only self-edited file passes"
run_hook block-cross-claude-wip.sh "$(input_json 'git commit -m x' "$TRANSCRIPT" "$REPO")"
assert_exit 0

finish

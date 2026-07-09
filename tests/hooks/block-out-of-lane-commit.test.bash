#!/usr/bin/env bash
# Tests for hooks/block-out-of-lane-commit.sh
#
# The edit-time lane gate only sees Edit|Write|MultiEdit. Bash-mediated writes
# (`biome format --write`, `sed -i`, codemods, `>` redirects) never reach it, so a lane
# worker can silently mutate files outside its lane (marketing-app 2026-07-09 incident M5).
# This gate sits at the one action every write method must pass through: `git commit`.
# Staged files must all fall inside the worktree's declared lane globs.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"

HOOK=block-out-of-lane-commit.sh

setup_repo() {
  local tmp; tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  REPO="$(git -C "$tmp" rev-parse --show-toplevel)"
  git -C "$REPO" config user.email t@t.test
  git -C "$REPO" config user.name tester
  RUN_DIR="$REPO"
}
write_lane() { printf '%s\n' "$@" > "$REPO/.bootstrap-lane"; }
# stage <relpath> — create and `git add` a file at that repo-relative path.
stage() {
  mkdir -p "$REPO/$(dirname "$1")"
  echo x > "$REPO/$1"
  git -C "$REPO" add -f "$1"
}
input_json() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' "$1" "$REPO"; }

# 1. Non-commit command passes through (staged out-of-lane file proves the gate never ran).
setup_repo
write_lane 'src/auth/**'
stage 'src/billing/pay.ts'
test_case "non-commit command (git status) passes through"
run_hook "$HOOK" "$(input_json 'git status')"
assert_exit 0

# 2. No lane file => fail-open (non-sprint work is untouched).
setup_repo
stage 'src/billing/pay.ts'
test_case "no lane file: commit passes (fail-open)"
run_hook "$HOOK" "$(input_json 'git commit -m x')"
assert_exit 0

# 3. All staged files inside the lane => commit allowed.
setup_repo
write_lane 'src/auth/**' 'tests/auth/**'
stage 'src/auth/login.ts'
stage 'tests/auth/login.test.ts'
test_case "staged files all within lane: commit allowed"
run_hook "$HOOK" "$(input_json 'git commit -m x')"
assert_exit 0

# 4. THE REGRESSION: a Bash-written out-of-lane file is staged => commit blocked.
#    This is exactly M5 — `biome format --write` touched a file no lane owns, and no
#    Edit-time hook ever saw it.
setup_repo
write_lane 'src/auth/**'
stage 'src/auth/login.ts'
stage 'scripts/_apply-migration.mjs'
test_case "out-of-lane staged file blocks commit"
run_hook "$HOOK" "$(input_json 'git commit -m x')"
assert_exit 2
assert_stderr_contains "scripts/_apply-migration.mjs"

# 5. The lane file itself must be declared like anything else (no implicit self-exemption),
#    but a lane that declares it can commit it.
setup_repo
write_lane 'src/auth/**' '.bootstrap-lane'
stage 'src/auth/login.ts'
git -C "$REPO" add -f .bootstrap-lane
test_case "lane file staged and declared: commit allowed"
run_hook "$HOOK" "$(input_json 'git commit -m x')"
assert_exit 0

# 6. `git commit -a` also sweeps in unstaged tracked modifications => they must be checked.
setup_repo
write_lane 'src/auth/**'
stage 'src/auth/login.ts'
stage 'scripts/tool.mjs'
git -C "$REPO" commit -qm init
echo mutated > "$REPO/scripts/tool.mjs"   # tracked, modified, NOT staged
test_case "git commit -a catches unstaged tracked out-of-lane modification"
run_hook "$HOOK" "$(input_json 'git commit -am x')"
assert_exit 2
assert_stderr_contains "scripts/tool.mjs"

# 7. Same state, plain `git commit` (no -a): nothing is staged => fail-open, git itself refuses.
test_case "plain git commit with empty index: fail-open"
run_hook "$HOOK" "$(input_json 'git commit -m x')"
assert_exit 0

# 8. Mid-merge commits cross lanes by definition => the lead's conflict resolution passes.
setup_repo
write_lane 'src/auth/**'
stage 'src/auth/login.ts'
git -C "$REPO" commit -qm init
stage 'scripts/tool.mjs'
printf '%s' "$(git -C "$REPO" rev-parse HEAD)" > "$(git -C "$REPO" rev-parse --absolute-git-dir)/MERGE_HEAD"
test_case "merge in progress: out-of-lane staged file passes"
run_hook "$HOOK" "$(input_json 'git commit -m merge')"
assert_exit 0

# 9. Unparseable hook input => fail-closed (matches the other commit gates).
setup_repo
write_lane 'src/auth/**'
test_case "unparseable input: fail-closed"
run_hook "$HOOK" 'not json at all'
assert_exit 2

finish

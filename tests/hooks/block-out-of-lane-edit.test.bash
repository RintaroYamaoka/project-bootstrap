#!/usr/bin/env bash
# Tests for hooks/block-out-of-lane-edit.sh
#
# Sprint substrate: each parallel worker runs in its own git worktree whose root holds
# a `.bootstrap-lane` file (one owned glob per line). The hook blocks editing any file
# outside that worktree's declared lane, making "1 task = 1 owner = 1 worktree" a
# deterministic boundary. No lane file => fail-open (normal non-sprint work is untouched).

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"

setup_repo() {
  local tmp; tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  REPO="$(git -C "$tmp" rev-parse --show-toplevel)"
  git -C "$REPO" config user.email t@t.test
  git -C "$REPO" config user.name tester
}
write_lane() { printf '%s\n' "$@" > "$REPO/.bootstrap-lane"; }
edit_input() { printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"},"cwd":"%s"}' "$1" "$REPO"; }

# 1. No lane file => fail-open (any edit passes).
setup_repo
RUN_DIR="$REPO"
test_case "no lane file: edit passes (fail-open)"
run_hook block-out-of-lane-edit.sh "$(edit_input "$REPO/src/anything.ts")"
assert_exit 0

# 2. Edit within an owned glob passes.
setup_repo
write_lane 'src/auth/**' 'tests/auth/**'
RUN_DIR="$REPO"
test_case "edit within owned glob passes"
run_hook block-out-of-lane-edit.sh "$(edit_input "$REPO/src/auth/login.ts")"
assert_exit 0

# 3. Edit outside the owned lane is blocked.
setup_repo
write_lane 'src/auth/**' 'tests/auth/**'
RUN_DIR="$REPO"
test_case "edit outside owned lane is blocked"
run_hook block-out-of-lane-edit.sh "$(edit_input "$REPO/src/billing/pay.ts")"
assert_exit 2

# 4. Exact-path lane entry matches.
setup_repo
write_lane 'lib/util.ts'
RUN_DIR="$REPO"
test_case "exact-path lane entry matches"
run_hook block-out-of-lane-edit.sh "$(edit_input "$REPO/lib/util.ts")"
assert_exit 0

# 5. Comment and blank lines in the lane file are ignored.
setup_repo
printf '# my lane\n\nsrc/auth/**\n' > "$REPO/.bootstrap-lane"
RUN_DIR="$REPO"
test_case "comment/blank lines ignored, glob still matches"
run_hook block-out-of-lane-edit.sh "$(edit_input "$REPO/src/auth/x.ts")"
assert_exit 0

# 6. Single-star glob still matches nested paths (bash [[ ]] '*' spans '/').
setup_repo
write_lane 'src/auth/*'
RUN_DIR="$REPO"
test_case "single-star glob matches nested path"
run_hook block-out-of-lane-edit.sh "$(edit_input "$REPO/src/auth/deep/nested.ts")"
assert_exit 0

finish

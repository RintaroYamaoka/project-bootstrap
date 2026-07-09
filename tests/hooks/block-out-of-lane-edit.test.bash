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

# --- Absolute paths outside this worktree -------------------------------------
# A lane worker writing an absolute path into ANOTHER worktree of the same repo (typically
# the main repo) used to fail-open as "undecidable". It is decidable: a path under another
# worktree root is by definition outside this lane (marketing-app 2026-07-09 incident M5).
# Paths under no worktree at all (/tmp scratchpad, ~/.claude) stay fail-open — there the
# hook genuinely has no grounds to judge.
setup_worktree() {
  setup_repo
  echo x > "$REPO/seed"; git -C "$REPO" add seed; git -C "$REPO" commit -qm init
  git -C "$REPO" worktree add -q -b lane1 "$REPO-wt" >/dev/null 2>&1
  WT="$(git -C "$REPO-wt" rev-parse --show-toplevel)"
  printf '%s\n' 'src/auth/**' > "$WT/.bootstrap-lane"
  RUN_DIR="$WT"
}
wt_input() { printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"},"cwd":"%s"}' "$1" "$WT"; }

# 7. THE REGRESSION: editing the main repo's file from inside a lane worktree is blocked.
setup_worktree
test_case "absolute path into another worktree (main repo) is blocked"
run_hook block-out-of-lane-edit.sh "$(wt_input "$REPO/scripts/_apply-migration.mjs")"
assert_exit 2
assert_stderr_contains "別 worktree"

# 8. Even a path that WOULD match the lane glob is blocked when it lives in another worktree
#    (the lane owns `src/auth/**` in ITS OWN tree, not in someone else's).
setup_worktree
test_case "another worktree's path is blocked even if it matches a lane glob"
run_hook block-out-of-lane-edit.sh "$(wt_input "$REPO/src/auth/login.ts")"
assert_exit 2

# 9. The lane's own tree still resolves normally through the same absolute path.
setup_worktree
test_case "own worktree absolute path within lane still passes"
run_hook block-out-of-lane-edit.sh "$(wt_input "$WT/src/auth/login.ts")"
assert_exit 0

# 10. A path under no worktree at all => fail-open (no grounds to judge).
setup_worktree
test_case "absolute path outside every worktree stays fail-open"
run_hook block-out-of-lane-edit.sh "$(wt_input "/tmp/scratch/notes.md")"
assert_exit 0

finish

#!/usr/bin/env bash
# Tests for hooks/block-unplanned-feature-build.sh
#
# Why this hook exists: sprint auto-decomposition used to be enforced only by an advisory
# reminder (sprint-trigger-reminder.sh) that injects a checklist — but the judgment and the
# action were left to the model, which is the exact "advisory is forgotten" failure mode the
# plugin rejects everywhere else. A real incident (scrum never fired during app development)
# proved it. This hook makes the gate fail-closed and TDD-shaped: creating a NEW source file
# (= the act of building feature surface, the judgment target itself — NOT the prompt vocabulary)
# is blocked until a sprint-gate decision is recorded in docs/sprint/.gate (or a sprint is
# already active via board.json). It does not (and cannot) launch a sprint — it only enforces
# that the decision was consciously made, just as require-test-companion enforces a test exists.
#
# Opt-in: only active when docs/sprint/ exists (project adopted the sprint flow), mirroring
# .bootstrap-arch / .bootstrap-protected / .bootstrap-lane. Fail-open otherwise.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"

HOOK=block-unplanned-feature-build.sh

setup_repo() {
  local tmp; tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  REPO="$(git -C "$tmp" rev-parse --show-toplevel)"
  git -C "$REPO" config user.email t@t.test
  git -C "$REPO" config user.name tester
}
enable_sprint() { mkdir -p "$REPO/docs/sprint"; }
write_gate() { printf '%s\n' "$@" > "$REPO/docs/sprint/.gate"; }
write_board() { printf '%s' '{"sprint":"s1","wip_limit":2}' > "$REPO/docs/sprint/board.json"; }
touch_file() { mkdir -p "$(dirname "$REPO/$1")"; : > "$REPO/$1"; }

write_input() { printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"x"},"cwd":"%s"}' "$1" "$REPO"; }
edit_input() { printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"},"cwd":"%s"}' "$1" "$REPO"; }

# 1. Opt-in absent (no docs/sprint/) => fail-open even for a new source file.
setup_repo
RUN_DIR="$REPO"
test_case "no docs/sprint dir: new source file passes (fail-open opt-in)"
run_hook "$HOOK" "$(write_input "$REPO/src/foo.ts")"
assert_exit 0

# 2. Opt-in present, new source file, no .gate/board => blocked.
setup_repo
enable_sprint
RUN_DIR="$REPO"
test_case "new source surface without recorded gate is blocked"
run_hook "$HOOK" "$(write_input "$REPO/src/foo.ts")"
assert_exit 2
assert_stderr_contains ".gate"

# 3. .gate records a covering scope glob => passes.
setup_repo
enable_sprint
write_gate 'src/**  sequential: single module, no disjoint >=2 leaves'
RUN_DIR="$REPO"
test_case "new source within recorded .gate scope passes"
run_hook "$HOOK" "$(write_input "$REPO/src/foo.ts")"
assert_exit 0

# 4. Active sprint (board.json present) => passes (lane hook owns scope).
setup_repo
enable_sprint
write_board
RUN_DIR="$REPO"
test_case "active sprint (board.json) passes"
run_hook "$HOOK" "$(write_input "$REPO/src/new.ts")"
assert_exit 0

# 5. Editing an EXISTING source file is not new surface => fail-open.
setup_repo
enable_sprint
touch_file "src/foo.ts"
RUN_DIR="$REPO"
test_case "edit of existing source file passes (not new surface)"
run_hook "$HOOK" "$(edit_input "$REPO/src/foo.ts")"
assert_exit 0

# 6. A new test file is not feature surface => fail-open.
setup_repo
enable_sprint
RUN_DIR="$REPO"
test_case "new test file passes (not source surface)"
run_hook "$HOOK" "$(write_input "$REPO/src/foo.test.ts")"
assert_exit 0

# 7. A new doc/config file is not source => fail-open.
setup_repo
enable_sprint
RUN_DIR="$REPO"
test_case "new markdown file passes"
run_hook "$HOOK" "$(write_input "$REPO/docs/notes.md")"
assert_exit 0

# 8. New source OUTSIDE the recorded .gate scope re-fires (mid-session new feature surface).
setup_repo
enable_sprint
write_gate 'src/auth/**  sequential: auth only'
RUN_DIR="$REPO"
test_case "new source outside recorded scope is blocked (re-fire)"
run_hook "$HOOK" "$(write_input "$REPO/src/billing/pay.ts")"
assert_exit 2

# 9. Writing the gate artifact itself must never be blocked.
setup_repo
enable_sprint
RUN_DIR="$REPO"
test_case "writing docs/sprint/.gate itself passes"
run_hook "$HOOK" "$(write_input "$REPO/docs/sprint/.gate")"
assert_exit 0

# 10. Missing file_path => fail-open (no basis).
setup_repo
enable_sprint
RUN_DIR="$REPO"
test_case "missing file_path is fail-open"
run_hook "$HOOK" "$(printf '{"tool_name":"Write","tool_input":{"content":"x"},"cwd":"%s"}' "$REPO")"
assert_exit 0

# 11. Not a git repo => fail-open.
NOGIT="$(mktemp -d)"; mkdir -p "$NOGIT/docs/sprint"
RUN_DIR="$NOGIT"
test_case "non-git dir is fail-open"
run_hook "$HOOK" "$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/src/x.ts","content":"y"},"cwd":"%s"}' "$NOGIT" "$NOGIT")"
assert_exit 0

# 12. Block message shows the project-declared wip_limit (.bootstrap-wip), not a hardcoded default.
setup_repo
enable_sprint
printf '4\n' > "$REPO/.bootstrap-wip"
RUN_DIR="$REPO"
test_case "block message surfaces declared .bootstrap-wip value"
run_hook "$HOOK" "$(write_input "$REPO/src/foo.ts")"
assert_exit 2
assert_stderr_contains '4 (.bootstrap-wip)'

# 13. Without a declaration the block message falls back to the default wording.
setup_repo
enable_sprint
RUN_DIR="$REPO"
test_case "block message falls back to 既定 2-3 without declaration"
run_hook "$HOOK" "$(write_input "$REPO/src/foo.ts")"
assert_exit 2
assert_stderr_contains '既定 2-3'

# 14. Comment/blank lines in .gate are ignored; a later glob still matches.
setup_repo
enable_sprint
printf '# decisions\n\nsrc/**  sequential: x\n' > "$REPO/docs/sprint/.gate"
RUN_DIR="$REPO"
test_case "comment/blank lines in .gate ignored, glob still matches"
run_hook "$HOOK" "$(write_input "$REPO/src/deep/nested.ts")"
assert_exit 0

finish

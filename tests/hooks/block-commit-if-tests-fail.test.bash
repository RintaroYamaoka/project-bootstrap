#!/usr/bin/env bash
# Characterization tests for hooks/block-commit-if-tests-fail.sh
#
# The hook is PreToolUse on Bash for `git commit`. From cwd it detects a project
# marker (package.json with a "test" script / pyproject / go.mod / Cargo.toml /
# Gemfile), runs that marker's test command, and blocks the commit with exit 2 if
# the tests fail. No marker (or a marker whose runner is not installed) -> warn on
# stderr and pass (exit 0). Non-commit commands pass straight through.
#
# These tests pin the REAL behavior in this environment. The only marker whose runner
# is deterministically installed AND controllable here is package.json: `npm test
# --silent` runs the package's "test" script, so `exit 0`/`exit 1` scripts give a
# fully deterministic PASS/FAIL. See the note near the bottom for the markers that
# cannot be exercised (go/cargo/bundle absent; pytest absent and no .venv for uv).

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"

HOOK=block-commit-if-tests-fail.sh

# fresh_dir — empty temp dir to use as RUN_DIR (cwd the hook inspects for markers).
fresh_dir() { RUN_DIR="$(mktemp -d)"; }

# input_json <command> — the PreToolUse payload the harness pipes on stdin.
input_json() {
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' "$1" "${RUN_DIR:-$PWD}"
}

# 1. Non-commit command passes through without inspecting markers or running tests.
#    (cwd has a package.json whose test would FAIL — proving it is never run here.)
fresh_dir
printf '{"scripts":{"test":"exit 1"}}' > "$RUN_DIR/package.json"
test_case "non-commit command (git status) passes through"
run_hook "$HOOK" "$(input_json 'git status')"
assert_exit 0

# 2. git commit with NO project marker -> warn and pass (exit 0).
fresh_dir
test_case "git commit with no project marker warns and passes"
run_hook "$HOOK" "$(input_json 'git commit -m x')"
assert_exit 0
assert_stderr_contains "no test framework detected"

# 3. package.json marker, passing test script -> commit allowed (exit 0).
fresh_dir
printf '{"scripts":{"test":"exit 0"}}' > "$RUN_DIR/package.json"
test_case "package.json with passing test allows commit"
run_hook "$HOOK" "$(input_json 'git commit -m x')"
assert_exit 0
assert_stderr_contains "running npm test --silent"

# 4. package.json marker, failing test script -> commit blocked (exit 2).
fresh_dir
printf '{"scripts":{"test":"exit 1"}}' > "$RUN_DIR/package.json"
test_case "package.json with failing test blocks commit"
run_hook "$HOOK" "$(input_json 'git commit -m x')"
assert_exit 2
assert_stderr_contains "tests failed"

# 5. package.json WITHOUT a "test" key -> not detected as a runner -> warn and pass.
#    (The hook greps for the literal '"test"'; absent it falls through to the no-marker
#    branch even though package.json exists.)
fresh_dir
printf '{"scripts":{"build":"exit 0"}}' > "$RUN_DIR/package.json"
test_case "package.json without a test script warns and passes"
run_hook "$HOOK" "$(input_json 'git commit -m x')"
assert_exit 0
assert_stderr_contains "no test framework detected"

# 6. pyproject.toml present but no .venv and pytest not installed -> TEST_CMD stays
#    empty -> warn and pass. This is the deterministic, runner-absent path.
#    (If pytest/uv+.venv were present this would instead run pytest; not the case here.)
fresh_dir
printf '[project]\nname = "x"\n' > "$RUN_DIR/pyproject.toml"
test_case "pyproject with no resolvable runner warns and passes"
run_hook "$HOOK" "$(input_json 'git commit -m x')"
assert_exit 0
assert_stderr_contains "no test framework detected"

# 7. Commit detected even when chained after another command (e.g. `&& git commit`).
#    package.json test FAILS, so a passed-through commit would wrongly exit 0; exit 2
#    proves the chained `git commit` was recognized and the test was run.
fresh_dir
printf '{"scripts":{"test":"exit 1"}}' > "$RUN_DIR/package.json"
test_case "chained git commit is detected and gated"
run_hook "$HOOK" "$(input_json 'git add -A && git commit -m x')"
assert_exit 2

# 8. go.mod / Cargo.toml / Gemfile whose runner is NOT installed -> warn and pass,
#    never a false block. Earlier these branches set TEST_CMD without a `command -v`
#    guard (unlike the pyproject branch), so a missing toolchain executed a
#    non-existent command -> non-zero exit -> the commit was wrongly blocked. Each
#    assertion runs only when its runner is genuinely absent, keeping the test
#    deterministic and portable.
if ! command -v go >/dev/null 2>&1; then
  fresh_dir
  printf 'module x\n\ngo 1.21\n' > "$RUN_DIR/go.mod"
  test_case "go.mod with go absent warns and passes (no false block)"
  run_hook "$HOOK" "$(input_json 'git commit -m x')"
  assert_exit 0
  assert_stderr_contains "no test framework detected"
fi
if ! command -v cargo >/dev/null 2>&1; then
  fresh_dir
  printf '[package]\nname = "x"\n' > "$RUN_DIR/Cargo.toml"
  test_case "Cargo.toml with cargo absent warns and passes (no false block)"
  run_hook "$HOOK" "$(input_json 'git commit -m x')"
  assert_exit 0
  assert_stderr_contains "no test framework detected"
fi

finish

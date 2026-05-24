#!/usr/bin/env bash
# Tests for hooks/block-commit-if-lint-fails.sh
#
# Analogous to the test gate: on `git commit`, detect the project's lint command and
# block the commit if it fails. This enforces the DETERMINISTIC slice of "clean code"
# (the project's own linter rules), not taste. No resolvable linter => warn-and-pass.
# Every runner branch is `command -v`-guarded so a missing toolchain never false-blocks
# (the regression lesson from the block-commit-if-tests-fail go/cargo bug).

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"

HOOK=block-commit-if-lint-fails.sh
fresh_dir() { RUN_DIR="$(mktemp -d)"; }
input_json() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' "$1" "${RUN_DIR:-$PWD}"; }

# 1. Non-commit command passes through (cwd has a failing lint script, proving it never runs).
fresh_dir
printf '{"scripts":{"lint":"exit 1"}}' > "$RUN_DIR/package.json"
test_case "non-commit command (git status) passes through"
run_hook "$HOOK" "$(input_json 'git status')"
assert_exit 0

# 2. No project marker -> warn and pass.
fresh_dir
test_case "git commit with no marker warns and passes"
run_hook "$HOOK" "$(input_json 'git commit -m x')"
assert_exit 0
assert_stderr_contains "no linter"

# 3. package.json with a passing lint script -> commit allowed.
fresh_dir
printf '{"scripts":{"lint":"exit 0"}}' > "$RUN_DIR/package.json"
test_case "package.json with passing lint allows commit"
run_hook "$HOOK" "$(input_json 'git commit -m x')"
assert_exit 0

# 4. package.json with a failing lint script -> commit blocked.
fresh_dir
printf '{"scripts":{"lint":"exit 1"}}' > "$RUN_DIR/package.json"
test_case "package.json with failing lint blocks commit"
run_hook "$HOOK" "$(input_json 'git commit -m x')"
assert_exit 2
assert_stderr_contains "lint failed"

# 5. package.json WITHOUT a "lint" script -> warn and pass.
fresh_dir
printf '{"scripts":{"build":"exit 0"}}' > "$RUN_DIR/package.json"
test_case "package.json without a lint script warns and passes"
run_hook "$HOOK" "$(input_json 'git commit -m x')"
assert_exit 0
assert_stderr_contains "no linter"

# 6. Cargo.toml whose linter (cargo) is absent -> warn and pass (runner-absent guard).
if ! command -v cargo >/dev/null 2>&1; then
  fresh_dir
  printf '[package]\nname = "x"\n' > "$RUN_DIR/Cargo.toml"
  test_case "Cargo.toml with cargo absent warns and passes (no false block)"
  run_hook "$HOOK" "$(input_json 'git commit -m x')"
  assert_exit 0
  assert_stderr_contains "no linter"
fi

finish

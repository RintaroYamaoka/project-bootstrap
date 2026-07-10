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
# opt-in: the gate only fires when the project declares `.bootstrap-lint`. fresh_dir
# creates the marker so the behaviour tests exercise detection; the opt-out test below
# removes it to confirm a missing marker disables the gate entirely.
fresh_dir() { RUN_DIR="$(mktemp -d)"; : > "$RUN_DIR/.bootstrap-lint"; }
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

# 7. opt-out: NO .bootstrap-lint marker -> gate disabled, commit allowed even with a
#    failing lint script. This is what keeps repos with an unconfigured/interactive
#    linter (e.g. `next lint` with no ESLint config) from being blocked by default.
fresh_dir
rm "$RUN_DIR/.bootstrap-lint"
printf '{"scripts":{"lint":"exit 1"}}' > "$RUN_DIR/package.json"
test_case "no .bootstrap-lint marker: gate disabled, commit allowed"
run_hook "$HOOK" "$(input_json 'git commit -m x')"
assert_exit 0

# 8. Detector bypasses (2026-07-10 audit): the failing lint script proves detection —
#    exit 2 == the gate saw the commit despite the path prefix / global option.
fresh_dir
printf '{"scripts":{"lint":"exit 1"}}' > "$RUN_DIR/package.json"
test_case "/usr/bin/git commit is detected and gated (path-prefix bypass)"
run_hook "$HOOK" "$(input_json '/usr/bin/git commit -m x')"
assert_exit 2

test_case "git -c k=v commit is detected and gated (global-option bypass)"
run_hook "$HOOK" "$(input_json 'git -c user.name=x commit -m x')"
assert_exit 2

finish

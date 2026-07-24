#!/usr/bin/env bash
# Characterization tests for hooks/require-test-companion.sh
#
# Intent: pin the current behavior of the "Red phase enforcement" PreToolUse hook
# (Edit|Write|MultiEdit). It blocks (exit 2) editing an implementation source file
# when no companion test exists, and passes (exit 0) for test files, docs/config,
# ephemeral `scripts/_*` scripts, and impl files that already have a companion test.
#
# Companion resolution is cwd-relative for the bare `tests/...` candidates and the
# recursive `find tests test` fallback, so each fixture is built in its own temp
# dir and exercised via RUN_DIR (the helper does `cd "$RUN_DIR"` before running).
# The impl file_path is absolute inside that dir; the hook normalizes `\` -> `/`.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"

# fixture_dir — fresh temp dir, echoed as git's forward-slash view so paths match
# the hook's normalized form on Windows Git Bash.
fixture_dir() {
  local tmp; tmp="$(mktemp -d)"
  ( cd "$tmp" && pwd )
}

# input_json <abs-file-path> <cwd>
input_json() {
  printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"},"cwd":"%s"}' "$1" "$2"
}

# --- 1. impl file with NO companion test -> block (exit 2) + explains itself ---
D="$(fixture_dir)"
: > "$D/foo.ts"
RUN_DIR="$D"
test_case "impl .ts with no companion test is blocked"
run_hook require-test-companion.sh "$(input_json "$D/foo.ts" "$D")"
assert_exit 2
assert_stderr_contains "no companion test file found"

# --- 2a. impl file WITH a beside companion (foo.test.ts next to foo.ts) -> pass ---
D="$(fixture_dir)"
: > "$D/foo.ts"
: > "$D/foo.test.ts"
RUN_DIR="$D"
test_case "impl .ts with beside companion foo.test.ts passes"
run_hook require-test-companion.sh "$(input_json "$D/foo.ts" "$D")"
assert_exit 0

# --- 2b. impl file WITH a companion under tests/ (flat) -> pass ---
D="$(fixture_dir)"
: > "$D/foo.ts"
mkdir -p "$D/tests"
: > "$D/tests/foo.test.ts"
RUN_DIR="$D"
test_case "impl .ts with tests/foo.test.ts companion passes"
run_hook require-test-companion.sh "$(input_json "$D/foo.ts" "$D")"
assert_exit 0

# --- 3. a test file itself is always skipped -> pass ---
D="$(fixture_dir)"
: > "$D/foo.test.ts"
RUN_DIR="$D"
test_case "test file foo.test.ts is skipped"
run_hook require-test-companion.sh "$(input_json "$D/foo.test.ts" "$D")"
assert_exit 0

# --- 4. markdown / config files are skipped -> pass ---
D="$(fixture_dir)"
: > "$D/README.md"
: > "$D/config.json"
RUN_DIR="$D"
test_case "markdown file is skipped"
run_hook require-test-companion.sh "$(input_json "$D/README.md" "$D")"
assert_exit 0
test_case "json config file is skipped"
run_hook require-test-companion.sh "$(input_json "$D/config.json" "$D")"
assert_exit 0

# --- 5. scripts/_* ephemeral underscore script is skipped -> pass ---
D="$(fixture_dir)"
mkdir -p "$D/scripts"
: > "$D/scripts/_foo.mjs"
RUN_DIR="$D"
test_case "scripts/_foo.mjs ephemeral script is skipped"
run_hook require-test-companion.sh "$(input_json "$D/scripts/_foo.mjs" "$D")"
assert_exit 0

# --- 6. nested tests/unit/<layer>/foo.test.ts companion (recursive fallback) -> pass ---
D="$(fixture_dir)"
: > "$D/foo.ts"
mkdir -p "$D/tests/unit/infrastructure"
: > "$D/tests/unit/infrastructure/foo.test.ts"
RUN_DIR="$D"
test_case "deep tests/unit/<layer>/foo.test.ts companion found via recursive fallback"
run_hook require-test-companion.sh "$(input_json "$D/foo.ts" "$D")"
assert_exit 0

# --- 7. Python bar.py with tests/test_bar.py companion -> pass ---
D="$(fixture_dir)"
: > "$D/bar.py"
mkdir -p "$D/tests"
: > "$D/tests/test_bar.py"
RUN_DIR="$D"
test_case "python bar.py with tests/test_bar.py companion passes"
run_hook require-test-companion.sh "$(input_json "$D/bar.py" "$D")"
assert_exit 0

# --- 8. file_path containing a comma is parsed whole (2026-07-10 audit) ---
# The old `grep -oE '"file_path"[^,}]*'` extractor truncated the value at the first
# ',': "src/foo,bar/baz.ts" became "src/foo" (no extension) and the gate silently
# fail-OPENed on an untested implementation file.
D="$(fixture_dir)"
mkdir -p "$D/src/foo,bar"
: > "$D/src/foo,bar/baz.ts"
RUN_DIR="$D"
test_case "impl file in a comma-named dir with no companion test is blocked (no truncation)"
run_hook require-test-companion.sh "$(input_json "$D/src/foo,bar/baz.ts" "$D")"
assert_exit 2

# --- worktree: 編集対象 file が cwd と別の project root にある場合 (実測 2026-07-24) ---
# companion 解決の相対 candidates (tests/...) と find fallback が cwd 基準のため、
# worktree のファイル編集を session cwd から審査すると companion 実在でも誤 block していた。
P="$(fixture_dir)"
mkdir -p "$P/src" "$P/tests"
printf '{}' > "$P/package.json"
: > "$P/src/foo.ts"
: > "$P/tests/foo.test.ts"
RUN_DIR="$(fixture_dir)"   # 全く別の空 dir = session cwd を模す
test_case "worktree: companion under the file's own project root passes (cwd mismatch)"
run_hook require-test-companion.sh "$(input_json "$P/src/foo.ts" "$RUN_DIR")"
assert_exit 0

# 逆向き: cwd 側に同名 companion があっても、file の root に無ければ block する
# (cwd の他人の test で緑を偽装しない)
P2="$(fixture_dir)"
mkdir -p "$P2/src"
printf '{}' > "$P2/package.json"
: > "$P2/src/bar.ts"
RUN_DIR="$(fixture_dir)"
mkdir -p "$RUN_DIR/tests"
: > "$RUN_DIR/tests/bar.test.ts"
test_case "worktree: companion only in cwd (not the file's root) still blocks"
run_hook require-test-companion.sh "$(input_json "$P2/src/bar.ts" "$RUN_DIR")"
assert_exit 2

finish

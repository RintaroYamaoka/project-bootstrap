# Test helper for hook scripts.
# Zero external deps — no bats, no jq (jq is absent on the maintainer's Git Bash and
# on many users' machines, so the test harness must match the hooks' pure-bash policy).
#
# A test file sources this, calls test_case / run_hook / assert_*, then finish.
# Each *.test.bash runs as its own process (see run.sh) for fixture isolation.

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../hooks" && pwd)"

TESTS_RUN=0
TESTS_FAILED=0
CURRENT_TEST=""

HOOK_EXIT=0
HOOK_STDERR=""
HOOK_STDOUT=""

# test_case <name> — label the assertions that follow.
test_case() { CURRENT_TEST="$1"; }

# run_hook <script-name> <stdin-json>
# Runs hooks/<script-name> with the JSON piped on stdin. If RUN_DIR is set, runs
# with that as cwd (hooks resolve git context from cwd). Captures exit code, stderr,
# and stdout (stdout matters for context-injecting hooks like UserPromptSubmit).
run_hook() {
  local script="$1" input="$2"
  local errf outf; errf="$(mktemp)"; outf="$(mktemp)"
  ( cd "${RUN_DIR:-$PWD}" && printf '%s' "$input" | bash "$HOOKS_DIR/$script" ) >"$outf" 2>"$errf"
  HOOK_EXIT=$?
  HOOK_STDERR="$(cat "$errf")"
  HOOK_STDOUT="$(cat "$outf")"
  rm -f "$errf" "$outf"
}

assert_exit() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$HOOK_EXIT" = "$1" ]; then
    echo "  ok   [$CURRENT_TEST] exit $1"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL [$CURRENT_TEST] expected exit $1, got $HOOK_EXIT"
    [ -n "$HOOK_STDERR" ] && printf '    stderr: %s\n' "$(printf '%s' "$HOOK_STDERR" | head -2)"
  fi
}

assert_stderr_contains() {
  TESTS_RUN=$((TESTS_RUN + 1))
  case "$HOOK_STDERR" in
    *"$1"*) echo "  ok   [$CURRENT_TEST] stderr contains '$1'" ;;
    *)
      TESTS_FAILED=$((TESTS_FAILED + 1))
      echo "  FAIL [$CURRENT_TEST] stderr missing '$1'"
      ;;
  esac
}

assert_stdout_contains() {
  TESTS_RUN=$((TESTS_RUN + 1))
  case "$HOOK_STDOUT" in
    *"$1"*) echo "  ok   [$CURRENT_TEST] stdout contains '$1'" ;;
    *)
      TESTS_FAILED=$((TESTS_FAILED + 1))
      echo "  FAIL [$CURRENT_TEST] stdout missing '$1'"
      ;;
  esac
}

assert_stdout_empty() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -z "$HOOK_STDOUT" ]; then
    echo "  ok   [$CURRENT_TEST] stdout empty"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL [$CURRENT_TEST] expected empty stdout, got: $(printf '%s' "$HOOK_STDOUT" | head -1)"
  fi
}

# assert_eq <expected> <actual> — direct value comparison (for engine unit tests).
assert_eq() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$1" = "$2" ]; then
    echo "  ok   [$CURRENT_TEST] '$2'"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL [$CURRENT_TEST] expected '$1', got '$2'"
  fi
}

# finish — print per-file summary and exit non-zero if anything failed.
finish() {
  echo "  ($TESTS_RUN assertions, $TESTS_FAILED failed)"
  [ "$TESTS_FAILED" = 0 ]
  exit $?
}

#!/usr/bin/env bash
# Shared detector for the project's test suite — the single authority on "what are
# the tests". Born from ADR 0005 guard 1: the merge gate (block-unreviewed-merge.sh)
# must run the REAL suite at integration so a Workflow's agent-judged "verdict:
# approve" cannot substitute for verification. The commit gate
# (block-commit-if-tests-fail.sh) already detects the same runners; duplicating that
# logic inline would let the two drift (drift in a gate signal IS the silent-bypass
# class), so both source this.
#
# detect_test_command:
#   inspects the CURRENT directory for a known project marker AND that the marker's
#   runner is on PATH; prints the test command to stdout + returns 0 when found,
#   else prints nothing + returns 1.
#
#   runner-on-PATH is required so a missing toolchain does not get its non-zero exit
#   misread as a "test failure" (that would block work on a machine lacking the
#   toolchain — see tests/hooks/block-commit-if-tests-fail.test.bash cases 6 & 8).
#   Callers decide their own fail-mode on return 1 (commit gate warns+passes; merge
#   gate passes — the agent review record still gated the merge). Pure bash, jq-free.

# detect_test_command — see header. Operates on cwd; callers `cd` to the target tree.
# Include guard — dispatcher が 1 プロセスに複数 gate を source するときの再読込抑止。
[ -n "${_BOOTSTRAP_LIB_DETECT_TEST_SUITE:-}" ] && return 0
_BOOTSTRAP_LIB_DETECT_TEST_SUITE=1

detect_test_command() {
  if [ -f package.json ]; then
    if grep -q '"test"' package.json && command -v npm >/dev/null 2>&1; then
      printf 'npm test --silent'; return 0
    fi
  elif [ -f pyproject.toml ] || [ -f pytest.ini ] || [ -f setup.cfg ]; then
    if command -v uv >/dev/null 2>&1 && [ -d .venv ]; then
      printf 'uv run pytest -q'; return 0
    elif command -v pytest >/dev/null 2>&1; then
      printf 'pytest -q'; return 0
    fi
  elif [ -f go.mod ]; then
    command -v go >/dev/null 2>&1 && { printf 'go test ./...'; return 0; }
  elif [ -f Cargo.toml ]; then
    command -v cargo >/dev/null 2>&1 && { printf 'cargo test --quiet'; return 0; }
  elif [ -f Gemfile ]; then
    command -v bundle >/dev/null 2>&1 && { printf 'bundle exec rspec'; return 0; }
  fi
  return 1
}

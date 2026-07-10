#!/usr/bin/env bash
# Unit tests for hooks/lib/detect-test-suite.sh — the single authority on "what are the
# tests" shared by the commit gate (block-commit-if-tests-fail) and the merge gate
# (block-unreviewed-merge, ADR 0005 guard 1).
#
# Contract under test: a project marker maps to its runner command ONLY when the runner
# is on PATH (a missing toolchain must never have its non-zero exit misread as a test
# failure); no marker / no runner => prints nothing, returns 1. Runner presence is made
# deterministic with stub executables prepended to PATH.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"
source "$(cd "$DIR/../../hooks" && pwd)/lib/detect-test-suite.sh"

# detect <dir> [stub-bin...] — run detect_test_command in <dir> with stub runners on
# PATH; print "<rc>|<stdout>" for a single stable assertion.
STUB="$(mktemp -d)"
mkstub() { printf '#!/bin/sh\nexit 0\n' > "$STUB/$1"; chmod +x "$STUB/$1"; }
detect() {
  local d="$1" out rc
  out="$(cd "$d" && PATH="$STUB:$PATH" detect_test_command)"; rc=$?
  printf '%s|%s' "$rc" "$out"
}

# --- package.json ---------------------------------------------------------------------
D="$(mktemp -d)"
printf '{"scripts":{"test":"exit 0"}}' > "$D/package.json"
mkstub npm
test_case "package.json with a test script and npm on PATH -> npm test --silent"
assert_eq '0|npm test --silent' "$(detect "$D")"

D="$(mktemp -d)"
printf '{"scripts":{"build":"exit 0"}}' > "$D/package.json"
test_case "package.json WITHOUT a test script -> not detected (rc 1)"
assert_eq '1|' "$(detect "$D")"

# --- go.mod / Cargo.toml / Gemfile with stubbed runners --------------------------------
D="$(mktemp -d)"
printf 'module x\n' > "$D/go.mod"
mkstub go
test_case "go.mod with go on PATH -> go test ./..."
assert_eq '0|go test ./...' "$(detect "$D")"

D="$(mktemp -d)"
printf '[package]\nname="x"\n' > "$D/Cargo.toml"
mkstub cargo
test_case "Cargo.toml with cargo on PATH -> cargo test --quiet"
assert_eq '0|cargo test --quiet' "$(detect "$D")"

D="$(mktemp -d)"
printf 'source "https://rubygems.org"\n' > "$D/Gemfile"
mkstub bundle
test_case "Gemfile with bundle on PATH -> bundle exec rspec"
assert_eq '0|bundle exec rspec' "$(detect "$D")"

# --- runner-absent guard (the false-block bug this lib carries the fix for) ------------
# A marker whose runner is NOT on PATH must not be detected. Assert only when the real
# environment genuinely lacks the runner (same technique as the commit-gate tests).
if ! command -v go >/dev/null 2>&1; then
  D="$(mktemp -d)"
  printf 'module x\n' > "$D/go.mod"
  test_case "go.mod with go ABSENT -> rc 1 (missing toolchain is not a test failure)"
  out="$(cd "$D" && detect_test_command)"; rc=$?
  assert_eq '1|' "$rc|$out"
fi

# --- pyproject: uv requires .venv, else pytest ------------------------------------------
D="$(mktemp -d)"
printf '[project]\nname = "x"\n' > "$D/pyproject.toml"
mkdir "$D/.venv"
mkstub uv
test_case "pyproject + .venv + uv on PATH -> uv run pytest -q"
assert_eq '0|uv run pytest -q' "$(detect "$D")"

# --- no marker at all --------------------------------------------------------------------
D="$(mktemp -d)"
test_case "empty directory -> nothing detected (rc 1)"
assert_eq '1|' "$(detect "$D")"

finish

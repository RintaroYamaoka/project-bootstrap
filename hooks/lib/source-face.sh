#!/usr/bin/env bash
# Shared classifier: is a repo-relative path an implementation "source face"?
# Single authority so block-unplanned-feature-build.sh (creating a NEW source face
# without a sprint judgment) and block-uniso-main-edit.sh (ADR 0005 guard 2: mutating
# a source face in the shared main tree while parallel lanes are active) cannot drift
# on what counts as source vs test/config/doc — drift in a gate signal IS the
# silent-bypass class this repo treats as a first-class bug.
#
# is_source_path <repo-relative-path>:
#   return 0 = implementation source (a "feature face")
#   return 1 = test file / config / docs / throwaway scripts / non-source extension
#   Callers fail OPEN (pass) on return 1 — these are never feature faces, so they are
#   not the act either gate is designed to catch. Pure bash, jq-free.
# Include guard — dispatcher が 1 プロセスに複数 gate を source するときの再読込抑止。
[ -n "${_BOOTSTRAP_LIB_SOURCE_FACE:-}" ] && return 0
_BOOTSTRAP_LIB_SOURCE_FACE=1

is_source_path() {
  local rel="$1"
  case "$rel" in
    # NOTE: the path is repo-RELATIVE, so the test dirs need BOTH the `*/tests/*`
    # (nested) and the `tests/*` (repo-root) anchors — with only the former, a
    # top-level tests/unit/foo.ts was misclassified as a source face (over-block:
    # found by tests/hooks/source-face.test.bash, 2026-07-10).
    *.test.*|*.spec.*|*_test.*|test_*.py|*/tests/*|*/test/*|*/__tests__/*|*/_test/*) return 1 ;;
    tests/*|test/*|__tests__/*|_test/*) return 1 ;;
    *.md|*.json|*.yaml|*.yml|*.toml|*.ini|*.cfg|*.lock|*.txt|*.env|*.gitignore|*.dockerignore) return 1 ;;
    *Dockerfile*|*Makefile*|*.sql) return 1 ;;
    */scripts/_*|scripts/_*) return 1 ;;
  esac
  case "${rel##*.}" in
    ts|tsx|js|jsx|mjs|cjs|py|go|rs|rb|php|java|cs|cpp|cc|c|h|hpp|swift|kt|scala|ex|exs|clj|hs|ml) return 0 ;;
    *) return 1 ;;
  esac
}

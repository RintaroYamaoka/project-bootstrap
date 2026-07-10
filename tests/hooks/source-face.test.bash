#!/usr/bin/env bash
# Unit tests for hooks/lib/source-face.sh — the shared classifier "is this repo-relative
# path an implementation source face?" used by block-unplanned-feature-build (new source
# face without a sprint judgment) and block-uniso-main-edit (un-isolated main-tree
# mutation, ADR 0005 guard 2). Single authority: if the two gates classified source vs
# test/config/doc independently, they would drift and one would silently fail-open.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"
source "$(cd "$DIR/../../hooks" && pwd)/lib/source-face.sh"

face() { if is_source_path "$1"; then echo yes; else echo no; fi; }

# --- implementation source faces -----------------------------------------------------
test_case "src/foo.ts is a source face"
assert_eq yes "$(face 'src/foo.ts')"

test_case "app/page.tsx is a source face"
assert_eq yes "$(face 'app/page.tsx')"

test_case "pkg/mod.go is a source face"
assert_eq yes "$(face 'pkg/mod.go')"

test_case "lib/x.py is a source face"
assert_eq yes "$(face 'lib/x.py')"

# --- test files are never source faces ------------------------------------------------
test_case "foo.test.ts is not a source face"
assert_eq no "$(face 'src/foo.test.ts')"

test_case "foo.spec.ts is not a source face"
assert_eq no "$(face 'src/foo.spec.ts')"

test_case "a file under tests/ is not a source face"
assert_eq no "$(face 'tests/unit/foo.ts')"

test_case "a file under __tests__/ is not a source face"
assert_eq no "$(face 'src/__tests__/foo.ts')"

test_case "test_foo.py is not a source face"
assert_eq no "$(face 'test_foo.py')"

# --- config / docs / non-source -------------------------------------------------------
test_case "README.md is not a source face"
assert_eq no "$(face 'README.md')"

test_case "package.json is not a source face"
assert_eq no "$(face 'package.json')"

test_case "config.yaml is not a source face"
assert_eq no "$(face 'config.yaml')"

test_case "Makefile is not a source face"
assert_eq no "$(face 'Makefile')"

test_case "migration.sql is not a source face"
assert_eq no "$(face 'db/migration.sql')"

test_case "a shell script is not a source face (.sh not in the source-extension enum)"
assert_eq no "$(face 'scripts/deploy.sh')"

test_case "scripts/_probe.mjs (ephemeral debug namespace) is not a source face"
assert_eq no "$(face 'scripts/_probe.mjs')"

test_case "an extensionless path is not a source face"
assert_eq no "$(face 'bin/tool')"

finish

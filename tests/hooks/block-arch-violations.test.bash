#!/usr/bin/env bash
# Tests for hooks/block-arch-violations.sh — the commit-time authoritative gate.
# On `git commit`, it validates every file in a declared layer against the
# `.bootstrap-arch` dependency contract and blocks the commit on any violation.
# No manifest => fail-open (non-arch repos unaffected).

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"

setup_archrepo() {
  local tmp; tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  REPO="$(git -C "$tmp" rev-parse --show-toplevel)"
  git -C "$REPO" config user.email t@t.test
  git -C "$REPO" config user.name tester
  cat > "$REPO/.bootstrap-arch" <<'EOF'
layer app   = app/**
layer infra = infrastructure/**
layer core  = core/**
alias @/ => ./
allow app   -> infra, core
allow infra -> core
EOF
}
addf() { mkdir -p "$REPO/$(dirname "$1")"; printf '%s' "$2" > "$REPO/$1"; git -C "$REPO" add "$1"; }
commit_input() { printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"cwd":"%s"}' "$REPO"; }

# 1. All imports respect the declared direction -> commit allowed.
setup_archrepo
addf "app/page.ts"   "import { e } from '@/core/entity';"
addf "core/entity.ts" "export const e = 1;"
RUN_DIR="$REPO"
test_case "commit passes when imports respect direction"
run_hook block-arch-violations.sh "$(commit_input)"
assert_exit 0

# 2. core importing infrastructure violates the contract -> commit blocked.
setup_archrepo
addf "core/service.ts"     "import { db } from '@/infrastructure/db';"
addf "infrastructure/db.ts" "export const db = 1;"
RUN_DIR="$REPO"
test_case "commit blocked when core imports infra"
run_hook block-arch-violations.sh "$(commit_input)"
assert_exit 2
assert_stderr_contains "disallowed"

# 3. No .bootstrap-arch manifest -> fail-open (commit allowed).
setup_archrepo
rm "$REPO/.bootstrap-arch"
addf "core/service.ts" "import x from '@/infrastructure/db';"
RUN_DIR="$REPO"
test_case "no manifest: fail-open"
run_hook block-arch-violations.sh "$(commit_input)"
assert_exit 0

# 4. Non-commit command passes straight through.
setup_archrepo
RUN_DIR="$REPO"
test_case "non-commit command passes"
run_hook block-arch-violations.sh "$(printf '{"tool_name":"Bash","tool_input":{"command":"git status"},"cwd":"%s"}' "$REPO")"
assert_exit 0

finish

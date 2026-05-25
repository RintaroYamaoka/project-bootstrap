#!/usr/bin/env bash
# Tests for scripts/arch-check.sh — the Claude-independent dependency-direction CLI.
# CI (GitHub Actions) and git pre-commit hooks call this so the SAME .bootstrap-arch
# contract is enforced for everyone, not just Claude PreToolUse. Usage:
#   arch-check.sh [file...]   — check given files; with no args, check staged files.
# Exits 1 if any declared-layer file violates the contract, 0 otherwise (and 0 with
# no .bootstrap-arch, so non-arch repos are unaffected).

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"
CLI="$(cd "$DIR/../.." && pwd)/scripts/arch-check.sh"

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
  mkdir -p "$REPO/core" "$REPO/infrastructure"
  printf 'export const db = 1;\n' > "$REPO/infrastructure/db.ts"
  printf "import { db } from '@/infrastructure/db';\n" > "$REPO/core/bad.ts"
  printf 'export const ok = 1;\n' > "$REPO/core/good.ts"
}
# run_cli <args...> — runs the CLI in $REPO, captures exit + stderr.
run_cli() {
  local errf; errf="$(mktemp)"
  ( cd "$REPO" && bash "$CLI" "$@" ) 2>"$errf"
  CLI_EXIT=$?
  CLI_ERR="$(cat "$errf")"; rm -f "$errf"
}

# 1. explicit violating file -> exit 1
setup_archrepo
test_case "violating file passed explicitly fails (exit 1)"
run_cli core/bad.ts
assert_eq 1 "$CLI_EXIT"

# 2. clean file -> exit 0
setup_archrepo
test_case "clean file passes (exit 0)"
run_cli core/good.ts
assert_eq 0 "$CLI_EXIT"

# 3. no .bootstrap-arch -> exit 0 (unaffected)
setup_archrepo
rm "$REPO/.bootstrap-arch"
test_case "no manifest: exit 0"
run_cli core/bad.ts
assert_eq 0 "$CLI_EXIT"

# 4. no args -> checks staged files (git diff --cached)
setup_archrepo
git -C "$REPO" add core/bad.ts infrastructure/db.ts
test_case "no args: staged violating file fails (exit 1)"
run_cli
assert_eq 1 "$CLI_EXIT"

# 5. no args, only clean file staged -> exit 0
setup_archrepo
git -C "$REPO" add core/good.ts
test_case "no args: only clean file staged passes (exit 0)"
run_cli
assert_eq 0 "$CLI_EXIT"

finish

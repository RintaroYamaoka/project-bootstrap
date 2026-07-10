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

# 5. Pre-existing committed violation (NOT staged in this commit) does NOT block.
#    The gate checks only STAGED files (git diff --cached) — correct pre-commit
#    semantics — so a repo can adopt .bootstrap-arch with existing debt without
#    every unrelated commit being blocked. Only newly staged/touched violations block.
setup_archrepo
addf "core/legacy.ts"      "import { db } from '@/infrastructure/db';"
addf "infrastructure/db.ts" "export const db = 1;"
git -C "$REPO" commit -qm "pre-existing debt" >/dev/null 2>&1
printf 'export const ok = 1;' > "$REPO/core/clean.ts"   # unrelated, clean
git -C "$REPO" add core/clean.ts
RUN_DIR="$REPO"
test_case "committed (unstaged) violation does not block; only staged files checked"
run_hook block-arch-violations.sh "$(commit_input)"
assert_exit 0

# 6. A newly STAGED violation IS blocked (the gate still catches what you commit).
setup_archrepo
addf "infrastructure/db.ts" "export const db = 1;"
addf "core/new.ts"          "import { db } from '@/infrastructure/db';"
RUN_DIR="$REPO"
test_case "newly staged violation is blocked"
run_hook block-arch-violations.sh "$(commit_input)"
assert_exit 2

# 7. Detector bypasses (2026-07-10 audit): path-prefixed git / global options slipped
#    the old regex, letting a staged violation commit straight past the gate.
commit_input_cmd() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' "$1" "$REPO"; }
setup_archrepo
addf "infrastructure/db.ts" "export const db = 1;"
addf "core/new.ts"          "import { db } from '@/infrastructure/db';"
RUN_DIR="$REPO"
test_case "/usr/bin/git commit is detected and gated (path-prefix bypass)"
run_hook block-arch-violations.sh "$(commit_input_cmd '/usr/bin/git commit -m x')"
assert_exit 2

test_case "git -c k=v commit is detected and gated (global-option bypass)"
run_hook block-arch-violations.sh "$(commit_input_cmd 'git -c user.name=x commit -m x')"
assert_exit 2

finish

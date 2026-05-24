#!/usr/bin/env bash
# Tests for hooks/block-cross-layer-import.sh — the edit-time early gate.
# When an Edit/Write introduces an import that violates the `.bootstrap-arch`
# dependency direction, it blocks the edit the moment it is written (fast feedback,
# before the work is wasted). The commit-time hook is the authoritative full-repo net.
# No manifest, or a file outside any declared layer => fail-open.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"

setup_archrepo() {
  local tmp; tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  REPO="$(git -C "$tmp" rev-parse --show-toplevel)"
  cat > "$REPO/.bootstrap-arch" <<'EOF'
layer app   = app/**
layer infra = infrastructure/**
layer core  = core/**
alias @/ => ./
allow app   -> infra, core
allow infra -> core
EOF
}
# edit_input <repo-rel-file> <new_string>
edit_input() {
  printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/%s","new_string":"%s"},"cwd":"%s"}' "$REPO" "$1" "$2" "$REPO"
}

# 1. core introducing an infra import is blocked at edit time.
setup_archrepo
RUN_DIR="$REPO"
test_case "edit: core importing infra is blocked"
run_hook block-cross-layer-import.sh "$(edit_input "core/service.ts" "import { db } from '@/infrastructure/db';")"
assert_exit 2

# 2. app importing infra is allowed.
setup_archrepo
RUN_DIR="$REPO"
test_case "edit: app importing infra is allowed"
run_hook block-cross-layer-import.sh "$(edit_input "app/page.ts" "import { db } from '@/infrastructure/db';")"
assert_exit 0

# 3. same-layer import allowed.
setup_archrepo
RUN_DIR="$REPO"
test_case "edit: core importing core sibling is allowed"
run_hook block-cross-layer-import.sh "$(edit_input "core/a.ts" "import { b } from './b';")"
assert_exit 0

# 4. no manifest -> fail-open.
setup_archrepo
rm "$REPO/.bootstrap-arch"
RUN_DIR="$REPO"
test_case "edit: no manifest fail-open"
run_hook block-cross-layer-import.sh "$(edit_input "core/service.ts" "import x from '@/infrastructure/db';")"
assert_exit 0

# 5. file outside any declared layer -> fail-open.
setup_archrepo
RUN_DIR="$REPO"
test_case "edit: unlayered file fail-open"
run_hook block-cross-layer-import.sh "$(edit_input "scripts/tool.ts" "import x from '@/infrastructure/db';")"
assert_exit 0

# 6. external import from core is fine.
setup_archrepo
RUN_DIR="$REPO"
test_case "edit: external import from core allowed"
run_hook block-cross-layer-import.sh "$(edit_input "core/a.ts" "import React from 'react';")"
assert_exit 0

finish

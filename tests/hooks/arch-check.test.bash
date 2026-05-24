#!/usr/bin/env bash
# Unit tests for the dependency-direction engine hooks/lib/arch-check.sh.
#
# The engine is generic: it ships no rules. A project declares its layers, path
# aliases, and allowed dependency edges in a `.bootstrap-arch` manifest, and the
# engine answers: which layer does a file belong to (`arch_layer_of`), what repo
# path does an import specifier resolve to (`arch_resolve`), what specifiers does a
# source file import (`arch_extract`), and does a file's imports violate the
# declared direction (`arch_check_imports`, rc=1 on any violation). Cross-layer is
# default-deny; same-layer and external (undeclared) targets are always allowed.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"
source "$(cd "$DIR/../../hooks" && pwd)/lib/arch-check.sh"

MAN="$(mktemp)"
cat > "$MAN" <<'EOF'
# generic clean-arch contract used by these tests
layer app   = app/**, middleware.ts
layer infra = infrastructure/**
layer core  = core/**
alias @/ => ./
allow app   -> infra, core
allow infra -> core
# core: no allow line => may import no other declared layer
EOF
arch_load_manifest "$MAN"

# --- arch_layer_of -------------------------------------------------------------
test_case "layer_of: app glob";          assert_eq "app"  "$(arch_layer_of app/page.ts)"
test_case "layer_of: single-file glob";  assert_eq "app"  "$(arch_layer_of middleware.ts)"
test_case "layer_of: nested core";       assert_eq "core" "$(arch_layer_of core/domain/entity.ts)"
test_case "layer_of: unlayered file";    assert_eq ""     "$(arch_layer_of README.md)"

# --- arch_resolve --------------------------------------------------------------
test_case "resolve: alias prefix";       assert_eq "infrastructure/db" "$(arch_resolve '@/infrastructure/db' app/page.ts)"
test_case "resolve: relative up twice";  assert_eq "core/entity"       "$(arch_resolve '../../core/entity' app/sub/page.ts)"
test_case "resolve: sibling relative";   assert_eq "core/util"         "$(arch_resolve './util' core/util-caller.ts)"
test_case "resolve: external package";   assert_eq ""                  "$(arch_resolve 'react' app/page.ts)"
test_case "resolve: scoped external";    assert_eq ""                  "$(arch_resolve '@tanstack/query' app/page.ts)"

# --- arch_extract (ts/js) ------------------------------------------------------
test_case "extract: import/require/export-from specifiers"
got="$(printf "import { a } from '@/infrastructure/db';\nimport React from \"react\";\nconst x = require('./cjs');\nexport { y } from './util';\n" | arch_extract ts | tr '\n' ',')"
assert_eq "@/infrastructure/db,react,./cjs,./util," "$got"

# --- arch_check_imports (rc=1 on violation) ------------------------------------
printf "import { db } from '@/infrastructure/db';\n" | arch_check_imports core/service.ts ts >/dev/null; rc=$?
test_case "check: core -> infra is forbidden (rc=1)"; assert_eq "1" "$rc"

printf "import { db } from '@/infrastructure/db';\n" | arch_check_imports app/page.ts ts >/dev/null; rc=$?
test_case "check: app -> infra is allowed (rc=0)"; assert_eq "0" "$rc"

printf "import { h } from '@/app/handler';\n" | arch_check_imports infrastructure/db.ts ts >/dev/null; rc=$?
test_case "check: infra -> app is forbidden (rc=1)"; assert_eq "1" "$rc"

printf "import { sib } from './sibling';\n" | arch_check_imports core/a.ts ts >/dev/null; rc=$?
test_case "check: same-layer import allowed (rc=0)"; assert_eq "0" "$rc"

printf "import React from 'react';\n" | arch_check_imports core/a.ts ts >/dev/null; rc=$?
test_case "check: external import allowed even from core (rc=0)"; assert_eq "0" "$rc"

# --- Python dotted-module resolution ------------------------------------------
test_case "resolve: python dotted module"
assert_eq "core/domain/entity" "$(arch_resolve 'core.domain.entity' app/main.py)"
printf "from core.domain.entity import E\n" | arch_check_imports infrastructure/repo.py py >/dev/null; rc=$?
test_case "check: py infra -> core allowed (rc=0)"; assert_eq "0" "$rc"
printf "from app.handler import H\n" | arch_check_imports core/svc.py py >/dev/null; rc=$?
test_case "check: py core -> app forbidden (rc=1)"; assert_eq "1" "$rc"

finish

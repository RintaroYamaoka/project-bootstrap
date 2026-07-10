#!/usr/bin/env bash
# Unit tests for hooks/lib/lane-match.sh — the shared lane-matching engine used by the
# edit-time gate (block-out-of-lane-edit) and the commit-time gate
# (block-out-of-lane-commit). Single authority: if the two gates interpreted lane globs
# independently, the looser one would become the hole (ADR 0017 / ADR 0005 guard 1).

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"
source "$(cd "$DIR/../../hooks" && pwd)/lib/lane-match.sh"

allows() { if lane_allows "$1" "$2"; then echo yes; else echo no; fi; }

LANE="$(mktemp)"
cat > "$LANE" <<'EOF'
# comment line — never a pattern
src/auth/**

  tests/auth/*
docs/exact.md
EOF

# --- lane_allows ----------------------------------------------------------------------
test_case "a path under a ** glob is allowed"
assert_eq yes "$(allows 'src/auth/deep/nested/login.ts' "$LANE")"

test_case "a single-star glob also crosses / in bash [[ ]] (documented semantics)"
assert_eq yes "$(allows 'tests/auth/a/b.test.ts' "$LANE")"

test_case "an exact path entry matches"
assert_eq yes "$(allows 'docs/exact.md' "$LANE")"

test_case "a path outside every glob is rejected"
assert_eq no "$(allows 'src/billing/pay.ts' "$LANE")"

test_case "a comment line is not a pattern"
assert_eq no "$(allows '# comment line — never a pattern' "$LANE")"

test_case "surrounding whitespace on a pattern line is trimmed"
assert_eq yes "$(allows 'tests/auth/x.test.ts' "$LANE")"

test_case "missing lane file rejects (caller treats file presence as the opt-in)"
assert_eq no "$(allows 'src/auth/login.ts' '/nonexistent/lane-file')"

rm -f "$LANE"

# --- lane_owning_worktree ---------------------------------------------------------------
git config --global user.email >/dev/null 2>&1 || git config --global user.email "test@example.com"
git config --global user.name  >/dev/null 2>&1 || git config --global user.name  "test"

tmp="$(mktemp -d)"
git -C "$tmp" init -q
MAIN="$(git -C "$tmp" rev-parse --show-toplevel)"
git -C "$MAIN" config user.email t@t.test
git -C "$MAIN" config user.name tester
git -C "$MAIN" commit -q --allow-empty -m seed
WT="$(mktemp -d)/lane-wt"
git -C "$MAIN" worktree add -q -b feat/lane "$WT" >/dev/null 2>&1
WT="$(cd "$WT" && pwd)"

owning() {
  local out rc
  out="$(cd "$2" && lane_owning_worktree "$1" "$2")"; rc=$?
  printf '%s|%s' "$rc" "$out"
}

test_case "an absolute path inside ANOTHER worktree resolves to that worktree (fail-closed grounds)"
assert_eq "0|$MAIN" "$(owning "$MAIN/some/file.ts" "$WT")"

test_case "a path inside the CALLER's own worktree is not 'another' worktree"
assert_eq '1|' "$(owning "$WT/some/file.ts" "$WT")"

test_case "a path outside every worktree has no owner (fail-open grounds)"
assert_eq '1|' "$(owning '/tmp/scratch/x.ts' "$WT")"

finish

#!/usr/bin/env bash
# Unit tests for hooks/lib/resolve-wip-limit.sh — the shared resolver for the
# wip_limit display value injected by sprint-trigger-reminder.sh and
# block-unplanned-feature-build.sh.
#
# The bug this replaces: a single all-forms "2-3" ceiling was hardcoded as advisory text in both hooks
# (and 4 docs). A project that declares a different limit per-experiment had no
# single place to do it — board.json is per-sprint ephemeral state (goes stale
# when a sprint ends), so it cannot carry the project default. `.bootstrap-wip`
# (one integer at repo root, same opt-in idiom as .bootstrap-arch/-lane/-protected)
# is the project-level declaration; this lib turns it into a display string.
#
# Contract:
#   no stdin; resolves git toplevel from cwd
#   stdout = "<n> (.bootstrap-wip)"  when toplevel/.bootstrap-wip's first
#            non-comment non-blank line is digits-only (after trim)
#          = "worker 既定 3-4・…"     otherwise (form-aware default, ADR 0006: absent / non-git / unparseable)
#   always returns 0 — this value is checklist DISPLAY, not a blocking signal,
#   so absence/garbage is fail-open to the default (doctor warns on garbage).

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"
source "$(cd "$DIR/../../hooks" && pwd)/lib/resolve-wip-limit.sh"

# resolve_in <dir> — run the resolver with <dir> as cwd.
resolve_in() { (cd "$1" && resolve_wip_limit); }
# resolve_int_in <dir> — run the blocking-gate integer variant; echo "<val>:<rc>".
resolve_int_in() { local v rc; v="$( (cd "$1" && resolve_wip_limit_int) )"; rc=$?; printf '%s:%s' "$v" "$rc"; }

make_repo() {
  local tmp; tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  git -C "$tmp" rev-parse --show-toplevel
}

# 1. Not a git repo => default (no basis to locate a declaration).
NOGIT="$(mktemp -d)"
test_case "non-git dir falls back to default"
assert_eq "worker 既定 3-4・Workflow lane は wip 非対象" "$(resolve_in "$NOGIT")"

# 2. Git repo without .bootstrap-wip => default (opt-in absent).
REPO="$(make_repo)"
test_case "repo without .bootstrap-wip falls back to default"
assert_eq "worker 既定 3-4・Workflow lane は wip 非対象" "$(resolve_in "$REPO")"

# 3. Declared integer is surfaced with its provenance.
REPO="$(make_repo)"
printf '4\n' > "$REPO/.bootstrap-wip"
test_case "declared integer is used"
assert_eq "4 (.bootstrap-wip)" "$(resolve_in "$REPO")"

# 4. Comment and blank lines before the value are skipped.
REPO="$(make_repo)"
printf '# project default lanes\n\n3\n' > "$REPO/.bootstrap-wip"
test_case "comments/blank lines are skipped"
assert_eq "3 (.bootstrap-wip)" "$(resolve_in "$REPO")"

# 5. Non-integer content falls back (doctor warns; resolver stays silent).
REPO="$(make_repo)"
printf 'abc\n' > "$REPO/.bootstrap-wip"
test_case "non-integer content falls back to default"
assert_eq "worker 既定 3-4・Workflow lane は wip 非対象" "$(resolve_in "$REPO")"

# 6. Trailing junk on the value line is NOT tolerated (strict: digits only).
REPO="$(make_repo)"
printf '4 lanes\n' > "$REPO/.bootstrap-wip"
test_case "trailing junk on value line falls back to default"
assert_eq "worker 既定 3-4・Workflow lane は wip 非対象" "$(resolve_in "$REPO")"

# 7. Surrounding whitespace is trimmed.
REPO="$(make_repo)"
printf '  5  \n' > "$REPO/.bootstrap-wip"
test_case "whitespace-padded value is trimmed"
assert_eq "5 (.bootstrap-wip)" "$(resolve_in "$REPO")"

# 8. Empty file => default.
REPO="$(make_repo)"
: > "$REPO/.bootstrap-wip"
test_case "empty file falls back to default"
assert_eq "worker 既定 3-4・Workflow lane は wip 非対象" "$(resolve_in "$REPO")"

# 9. Resolution works from a subdirectory (declaration lives at toplevel).
REPO="$(make_repo)"
printf '4\n' > "$REPO/.bootstrap-wip"
mkdir -p "$REPO/src/deep"
test_case "resolves toplevel declaration from a subdirectory"
assert_eq "4 (.bootstrap-wip)" "$(resolve_in "$REPO/src/deep")"

# 9b. New consolidated layout: .bootstrap/wip is read, and its provenance label
#     reflects the new path.
REPO="$(make_repo)"; mkdir -p "$REPO/.bootstrap"; printf '6\n' > "$REPO/.bootstrap/wip"
test_case "new layout .bootstrap/wip is used with new-path provenance"
assert_eq "6 (.bootstrap/wip)" "$(resolve_in "$REPO")"

# 9c. New wins over legacy when both exist.
REPO="$(make_repo)"; mkdir -p "$REPO/.bootstrap"; printf '6\n' > "$REPO/.bootstrap/wip"; printf '2\n' > "$REPO/.bootstrap-wip"
test_case "new layout wins over legacy when both present"
assert_eq "6 (.bootstrap/wip)" "$(resolve_in "$REPO")"

# --- resolve_wip_limit_int (the blocking-gate variant, ADR 0005 guard 3) ---
# Returns the raw integer + rc 0 only when declared & parseable; else no stdout + rc 1.
# Callers (block-over-wip-parallel.sh) fail OPEN on rc 1 to preserve opt-in.

# 10. Non-git dir => rc 1, no value.
test_case "int: non-git dir returns rc 1"
assert_eq ":1" "$(resolve_int_in "$(mktemp -d)")"

# 11. Repo without .bootstrap-wip => rc 1 (undeclared, opt-in).
REPO="$(make_repo)"
test_case "int: undeclared returns rc 1"
assert_eq ":1" "$(resolve_int_in "$REPO")"

# 12. Declared integer => the bare integer + rc 0.
REPO="$(make_repo)"; printf '3\n' > "$REPO/.bootstrap-wip"
test_case "int: declared integer returns value + rc 0"
assert_eq "3:0" "$(resolve_int_in "$REPO")"

# 13. Comments/blank lines skipped, integer surfaced.
REPO="$(make_repo)"; printf '# lanes\n\n5\n' > "$REPO/.bootstrap-wip"
test_case "int: comments skipped"
assert_eq "5:0" "$(resolve_int_in "$REPO")"

# 14. Non-integer content => rc 1 (fail-open at the caller).
REPO="$(make_repo)"; printf 'abc\n' > "$REPO/.bootstrap-wip"
test_case "int: garbage returns rc 1"
assert_eq ":1" "$(resolve_int_in "$REPO")"

# 15. Trailing junk on the value line => rc 1 (strict digits-only).
REPO="$(make_repo)"; printf '4 lanes\n' > "$REPO/.bootstrap-wip"
test_case "int: trailing junk returns rc 1"
assert_eq ":1" "$(resolve_int_in "$REPO")"

# 16. Empty file => rc 1.
REPO="$(make_repo)"; : > "$REPO/.bootstrap-wip"
test_case "int: empty file returns rc 1"
assert_eq ":1" "$(resolve_int_in "$REPO")"

finish

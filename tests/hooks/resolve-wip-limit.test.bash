#!/usr/bin/env bash
# Unit tests for hooks/lib/resolve-wip-limit.sh — the shared resolver for the
# wip_limit display value injected by sprint-trigger-reminder.sh and
# block-unplanned-feature-build.sh.
#
# The bug this replaces: "既定 2-3" was hardcoded as advisory text in both hooks
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
#          = "既定 2-3"              otherwise (absent / non-git / unparseable)
#   always returns 0 — this value is checklist DISPLAY, not a blocking signal,
#   so absence/garbage is fail-open to the default (doctor warns on garbage).

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"
source "$(cd "$DIR/../../hooks" && pwd)/lib/resolve-wip-limit.sh"

# resolve_in <dir> — run the resolver with <dir> as cwd.
resolve_in() { (cd "$1" && resolve_wip_limit); }

make_repo() {
  local tmp; tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  git -C "$tmp" rev-parse --show-toplevel
}

# 1. Not a git repo => default (no basis to locate a declaration).
NOGIT="$(mktemp -d)"
test_case "non-git dir falls back to default"
assert_eq "既定 2-3" "$(resolve_in "$NOGIT")"

# 2. Git repo without .bootstrap-wip => default (opt-in absent).
REPO="$(make_repo)"
test_case "repo without .bootstrap-wip falls back to default"
assert_eq "既定 2-3" "$(resolve_in "$REPO")"

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
assert_eq "既定 2-3" "$(resolve_in "$REPO")"

# 6. Trailing junk on the value line is NOT tolerated (strict: digits only).
REPO="$(make_repo)"
printf '4 lanes\n' > "$REPO/.bootstrap-wip"
test_case "trailing junk on value line falls back to default"
assert_eq "既定 2-3" "$(resolve_in "$REPO")"

# 7. Surrounding whitespace is trimmed.
REPO="$(make_repo)"
printf '  5  \n' > "$REPO/.bootstrap-wip"
test_case "whitespace-padded value is trimmed"
assert_eq "5 (.bootstrap-wip)" "$(resolve_in "$REPO")"

# 8. Empty file => default.
REPO="$(make_repo)"
: > "$REPO/.bootstrap-wip"
test_case "empty file falls back to default"
assert_eq "既定 2-3" "$(resolve_in "$REPO")"

# 9. Resolution works from a subdirectory (declaration lives at toplevel).
REPO="$(make_repo)"
printf '4\n' > "$REPO/.bootstrap-wip"
mkdir -p "$REPO/src/deep"
test_case "resolves toplevel declaration from a subdirectory"
assert_eq "4 (.bootstrap-wip)" "$(resolve_in "$REPO/src/deep")"

finish

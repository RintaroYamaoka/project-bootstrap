#!/usr/bin/env bash
# Unit tests for hooks/lib/lane-set.sh — the shared lane-branch set builder for the two
# integration gates (block-unreviewed-merge, block-merge-if-verification-unclosed).
#
# Why extracted: ~40 lines of set-building (active-board task branches ∪ linked-worktree
# branches, ADR 0004) lived verbatim in BOTH gates. Duplicated gate-signal code drifts —
# one gate's lane becomes the other's blind spot — so the set is now a single authority
# (same policy as merge-targets.sh / lane-match.sh).

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"
source "$(cd "$DIR/../../hooks" && pwd)/lib/lane-set.sh"

git config --global user.email >/dev/null 2>&1 || git config --global user.email "test@example.com"
git config --global user.name  >/dev/null 2>&1 || git config --global user.name  "test"

# mkrepo — temp repo with one seed commit; REPO is git's own toplevel view.
mkrepo() {
  local tmp; tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  REPO="$(git -C "$tmp" rev-parse --show-toplevel)"
  git -C "$REPO" config user.email t@t.test
  git -C "$REPO" config user.name tester
  git -C "$REPO" commit -q --allow-empty -m seed
}
lanes() { lane_branches "$REPO" | grep -v '^$' | sort | paste -sd, -; }
contains() { if lane_set_contains "$1" "$2"; then echo yes; else echo no; fi; }

# --- (a) active board task branches --------------------------------------------------
mkrepo
mkdir -p "$REPO/docs/sprint"
cat > "$REPO/docs/sprint/board.json" <<'EOF'
{"tasks":[
  {"id":"T1","branch":"feat/a","status":"doing"},
  {"id":"T2","branch":"feat/b","status":"done"}
]}
EOF
test_case "active board contributes its task branches"
assert_eq 'feat/a,feat/b' "$(lanes)"

# --- board liveness: a stale all-done board contributes NOTHING ----------------------
mkrepo
mkdir -p "$REPO/docs/sprint"
cat > "$REPO/docs/sprint/board.json" <<'EOF'
{"tasks":[{"id":"T1","branch":"feat/a","status":"done"}]}
EOF
test_case "all-done (stale) board contributes no branches (liveness, not existence)"
assert_eq '' "$(lanes)"

# --- (b) linked worktree branches ----------------------------------------------------
mkrepo
WT="$(mktemp -d)/wt"
git -C "$REPO" worktree add -q -b feat/wt "$WT" >/dev/null 2>&1
test_case "a linked worktree's checked-out branch is a lane"
assert_eq 'feat/wt' "$(lanes)"

test_case "the main worktree's own branch is NOT a lane"
CUR="$(git -C "$REPO" rev-parse --abbrev-ref HEAD)"
assert_eq no "$(contains "$CUR" "$(lane_branches "$REPO")")"

# --- union of both sources ------------------------------------------------------------
mkdir -p "$REPO/docs/sprint"
cat > "$REPO/docs/sprint/board.json" <<'EOF'
{"tasks":[{"id":"T1","branch":"feat/board","status":"doing"}]}
EOF
test_case "board branches and worktree branches union"
assert_eq 'feat/board,feat/wt' "$(lanes)"

# --- no sources -> empty set ----------------------------------------------------------
mkrepo
test_case "no board and no linked worktree -> empty lane set"
assert_eq '' "$(lanes)"

# --- lane_set_contains ----------------------------------------------------------------
SET=$'feat/a\n\nfeat/b'
test_case "lane_set_contains finds an exact member"
assert_eq yes "$(contains feat/a "$SET")"

test_case "lane_set_contains ignores empty lines and rejects non-members"
assert_eq no "$(contains feat/c "$SET")"

test_case "empty token never matches (empty lines are not lanes)"
assert_eq no "$(contains '' "$SET")"

finish

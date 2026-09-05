#!/usr/bin/env bash
# Unit tests for scripts/branch-cleanup.sh — the verified branch teardown.
#
# The script exists because integrate(skill)'s old `git branch -d` step could not complete
# under GitHub squash merge (the squash commit is not a descendant, so -d always refuses)
# while `-D` is blocked by block-dangerous-git-ops.sh. So the contract under test is not
# "deletes branches" but "deletes ONLY what it has grounds for, and keeps everything else":
#
#   (a) branch is an ancestor of the main ref            -> delete
#   (b) branch is the head of a MERGED PR (gh)           -> delete
#   anything else — including every branch when gh is unavailable — -> KEEP
#
# `gh` is faked on PATH so the (b) path and the degraded path are both exercised offline.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"
SCRIPT="$(cd "$DIR/../.." && pwd)/scripts/branch-cleanup.sh"

git config --global user.email >/dev/null 2>&1 || git config --global user.email "test@example.com"
git config --global user.name  >/dev/null 2>&1 || git config --global user.name  "test"

GIT_Q=(-c user.email=t@e.x -c user.name=t)

# mkrepo — repo with one commit on main and a LOCAL refs/remotes/origin/main at that commit.
# No network anywhere in this file.
mkrepo() {
  local r; r="$(mktemp -d)"
  git -C "$r" init -q -b main
  git -C "$r" "${GIT_Q[@]}" commit -q --allow-empty -m c0
  git -C "$r" update-ref refs/remotes/origin/main "$(git -C "$r" rev-parse HEAD)"
  printf '%s' "$r"
}

# fake_gh <dir> <lines…> — put a `gh` on PATH that answers `auth status` (ok) and
# `pr list` with the given "<headRefName>|<STATE>" lines. Echoes the bin dir.
fake_gh() {
  local bin="$1"; shift
  mkdir -p "$bin"
  printf '%s\n' "$@" > "$bin/prs.txt"
  cat > "$bin/gh" <<'GH'
#!/usr/bin/env bash
case "$1" in
  auth) exit 0 ;;
  pr)   cat "$(dirname "$0")/prs.txt"; exit 0 ;;
esac
exit 1
GH
  chmod +x "$bin/gh"
  printf '%s' "$bin"
}

# branches <repo> — the repo's local branch names, space separated, sorted.
branches() { git -C "$1" for-each-ref --format='%(refname:short)' refs/heads | sort | tr '\n' ' ' | sed 's/ $//'; }

# --- dry-run is inert ----------------------------------------------------------------
R="$(mkrepo)"
git -C "$R" branch merged-1 HEAD
test_case "dry-run deletes nothing"
bash "$SCRIPT" --repo "$R" >/dev/null 2>&1
assert_eq "main merged-1" "$(branches "$R")"

# --- (a) ancestor of the main ref -----------------------------------------------------
test_case "a branch already in the main ref is deleted"
bash "$SCRIPT" --repo "$R" --apply --no-backup >/dev/null 2>&1
assert_eq "main" "$(branches "$R")"

# REGRESSION (2026-09-05): `git branch -d` judges against HEAD, not against the main ref.
# When local main lags origin/main, -d calls an already-merged branch "not fully merged"
# and the teardown silently failed. Grounds (a) are already in hand, so the script falls
# back to -D for exactly that case.
R="$(mkrepo)"
BASE="$(git -C "$R" rev-parse HEAD)"
git -C "$R" "${GIT_Q[@]}" commit -q --allow-empty -m c1
git -C "$R" branch feat-done HEAD                       # in origin/main once we move the ref
git -C "$R" update-ref refs/remotes/origin/main "$(git -C "$R" rev-parse HEAD)"
git -C "$R" update-ref refs/heads/main "$BASE"          # local main now BEHIND origin/main
test_case "merged branch is removed even when local main lags the main ref"
bash "$SCRIPT" --repo "$R" --apply --no-backup >/dev/null 2>&1
case " $(branches "$R") " in *" feat-done "*) assert_eq "feat-done gone" "still present" ;; *) assert_eq ok ok ;; esac

# --- branches with no grounds are KEPT ------------------------------------------------
R="$(mkrepo)"
git -C "$R" branch wip HEAD
git -C "$R" "${GIT_Q[@]}" commit -q --allow-empty -m ahead
git -C "$R" branch -f wip HEAD
git -C "$R" update-ref refs/heads/main "$(git -C "$R" rev-parse refs/remotes/origin/main)"
test_case "an unmerged branch with no PR is kept (it may hold the only copy)"
bash "$SCRIPT" --repo "$R" --apply --no-backup >/dev/null 2>&1
case " $(branches "$R") " in *" wip "*) assert_eq ok ok ;; *) assert_eq "wip kept" "deleted" ;; esac

# --- (b) squash-merged PR, and the degraded path --------------------------------------
# `sq` is NOT an ancestor of origin/main — exactly the shape squash merge leaves behind.
mksquash() {
  local r; r="$(mkrepo)"
  git -C "$r" branch sq HEAD
  git -C "$r" "${GIT_Q[@]}" -c core.hooksPath=/dev/null commit -q --allow-empty -m "on sq" 2>/dev/null
  git -C "$r" branch -f sq HEAD
  git -C "$r" update-ref refs/heads/main "$(git -C "$r" rev-parse refs/remotes/origin/main)"
  git -C "$r" symbolic-ref HEAD refs/heads/main
  git -C "$r" reset -q --hard refs/heads/main
  printf '%s' "$r"
}

R="$(mksquash)"
test_case "without gh the squash-merged branch is KEPT (no grounds → no deletion)"
PATH="/nonexistent-bin-xyz:$PATH" bash "$SCRIPT" --repo "$R" --apply --no-backup >/dev/null 2>&1
case " $(branches "$R") " in *" sq "*) assert_eq ok ok ;; *) assert_eq "sq kept" "deleted" ;; esac

test_case "with gh reporting the PR MERGED, the squash-merged branch is deleted"
BIN="$(fake_gh "$(mktemp -d)/bin" 'sq|MERGED')"
PATH="$BIN:$PATH" bash "$SCRIPT" --repo "$R" --apply --no-backup >/dev/null 2>&1
case " $(branches "$R") " in *" sq "*) assert_eq "sq deleted" "still present" ;; *) assert_eq ok ok ;; esac

R="$(mksquash)"
test_case "an OPEN PR branch is never deleted"
BIN="$(fake_gh "$(mktemp -d)/bin" 'sq|OPEN')"
PATH="$BIN:$PATH" bash "$SCRIPT" --repo "$R" --apply --no-backup >/dev/null 2>&1
case " $(branches "$R") " in *" sq "*) assert_eq ok ok ;; *) assert_eq "sq kept" "deleted" ;; esac

# --- worktree-held branches -----------------------------------------------------------
R="$(mkrepo)"
git -C "$R" branch lane HEAD
WT="$(mktemp -d)/lane"
git -C "$R" worktree add -q "$WT" lane
test_case "a branch a worktree has checked out is kept (git could not delete it anyway)"
bash "$SCRIPT" --repo "$R" --apply --no-backup >/dev/null 2>&1
case " $(branches "$R") " in *" lane "*) assert_eq ok ok ;; *) assert_eq "lane kept" "deleted" ;; esac
git -C "$R" worktree remove --force "$WT" 2>/dev/null

# --- backup ---------------------------------------------------------------------------
R="$(mkrepo)"
git -C "$R" branch gone-soon HEAD
BK="$(mktemp -d)/bk"
bash "$SCRIPT" --repo "$R" --apply --backup "$BK" >/dev/null 2>&1
test_case "a backup file with name+sha is written before deleting"
N=0; for f in "$BK"/*.refs; do [ -f "$f" ] && N=$((N+1)); done
assert_eq "1" "$N"
test_case "...and it records the deleted branch so it can be restored"
case "$(cat "$BK"/*.refs 2>/dev/null)" in *"refs/heads/gone-soon"*) assert_eq ok ok ;; *) assert_eq "recorded" "missing" ;; esac

# --- argument handling ----------------------------------------------------------------
test_case "an unknown option is a usage error, not a silent no-op"
bash "$SCRIPT" --wat >/dev/null 2>&1
assert_eq "1" "$?"
test_case "a non-repo directory exits 2 without touching anything"
bash "$SCRIPT" --repo "$(mktemp -d)" >/dev/null 2>&1
assert_eq "2" "$?"

finish

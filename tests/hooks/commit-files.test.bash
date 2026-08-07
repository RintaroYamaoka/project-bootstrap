#!/usr/bin/env bash
# Unit tests for hooks/lib/commit-files.sh — the single authority on "which files will
# this `git commit` carry?" shared by the lane gate (block-out-of-lane-commit) and the
# lint gate (block-commit-if-lint-fails). Two gates reading the index independently
# would drift on the `-a` handling and one would become the looser hole (ADR 0018).
#
# Contract under test: staged files always; `-a`/`-am`/`--all` additionally sweep
# unstaged TRACKED changes; deleted files are included (removing an out-of-lane file
# is still a lane violation); output is repo-relative, newline-separated, sort -u.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"
source "$(cd "$DIR/../../hooks" && pwd)/lib/commit-files.sh"

mkrepo() {
  local tmp; tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  REPO="$(git -C "$tmp" rev-parse --show-toplevel)"
  git -C "$REPO" config user.email t@t.test
  git -C "$REPO" config user.name tester
}
# files <cmd> — run the resolver from inside the repo, join lines with commas.
files() { ( cd "$REPO" && commit_files_from_cmd "$1" ) | paste -sd, -; }

# --- staged-only commit --------------------------------------------------------------
mkrepo
mkdir -p "$REPO/src"
echo a > "$REPO/src/a.ts"; git -C "$REPO" add src/a.ts
echo b > "$REPO/src/b.ts"                     # untracked, NOT staged
test_case "plain commit carries only staged files (untracked never swept)"
assert_eq 'src/a.ts' "$(files 'git commit -m x')"

# --- -a sweeps unstaged TRACKED changes ----------------------------------------------
mkrepo
mkdir -p "$REPO/src"
echo a > "$REPO/src/a.ts"; git -C "$REPO" add src/a.ts; git -C "$REPO" commit -qm seed
echo mod > "$REPO/src/a.ts"                   # tracked, modified, unstaged
echo new > "$REPO/src/new.ts"; git -C "$REPO" add src/new.ts
test_case "git commit -a additionally carries unstaged tracked changes"
assert_eq 'src/a.ts,src/new.ts' "$(files 'git commit -a -m x')"

test_case "git commit -am (combined short flag) also sweeps"
assert_eq 'src/a.ts,src/new.ts' "$(files 'git commit -am x')"

test_case "git commit --all also sweeps"
assert_eq 'src/a.ts,src/new.ts' "$(files 'git commit --all -m x')"

test_case "plain -m commit does NOT sweep the unstaged tracked change"
assert_eq 'src/new.ts' "$(files 'git commit -m x')"

test_case "a bare word containing 'a' in the message does not trigger the -a sweep"
assert_eq 'src/new.ts' "$(files 'git commit -m all')"

# --- deleted files are carried too ----------------------------------------------------
mkrepo
mkdir -p "$REPO/src"
echo a > "$REPO/src/gone.ts"; git -C "$REPO" add src/gone.ts; git -C "$REPO" commit -qm seed
git -C "$REPO" rm -q src/gone.ts
test_case "a staged deletion is included (deleting out-of-lane is still a violation)"
assert_eq 'src/gone.ts' "$(files 'git commit -m x')"

# --- duplicates collapse (staged + also modified) --------------------------------------
mkrepo
mkdir -p "$REPO/src"
echo a > "$REPO/src/a.ts"; git -C "$REPO" add src/a.ts; git -C "$REPO" commit -qm seed
echo v2 > "$REPO/src/a.ts"; git -C "$REPO" add src/a.ts
echo v3 > "$REPO/src/a.ts"                    # staged AND unstaged-modified
test_case "a file both staged and re-modified appears once under -a (sort -u)"
assert_eq 'src/a.ts' "$(files 'git commit -am x')"

# --- empty index ------------------------------------------------------------------------
mkrepo
test_case "empty index yields an empty set"
assert_eq '' "$(files 'git commit -m x')"

# --- commit_stages_all: the -a predicate, shared with lib/retired-terms.sh -----------------
# retired-terms.sh needs the same answer to choose `git diff --cached` vs `git diff HEAD`
# for the added-line scan. A second copy of the regex would drift on exactly the case it
# exists for (`-m all` must not count) and the looser copy becomes the silent hole.
stages() { commit_stages_all "$1" && echo yes || echo no; }
test_case "commit_stages_all recognizes every sweeping form"
assert_eq yes "$(stages 'git commit -a -m x')"
assert_eq yes "$(stages 'git commit -am x')"
assert_eq yes "$(stages 'git commit --all -m x')"
test_case "commit_stages_all rejects the non-sweeping forms"
assert_eq no "$(stages 'git commit -m x')"
assert_eq no "$(stages 'git commit -m all')"
assert_eq no "$(stages 'git commit -m "add a thing"')"

# --- commit_added_files: only what this commit ADDS ---------------------------------------
# The commission coverage gate asks "is this NEW source face covered by an ordered WO?",
# so a modification or a deletion must not be mistaken for a creation (bug fixes and
# refactors would trip the gate on every commit).
mkrepo
mkdir -p "$REPO/src"
echo old > "$REPO/src/old.ts"; git -C "$REPO" add src/old.ts
git -C "$REPO" commit -qm base
echo changed > "$REPO/src/old.ts"
echo new > "$REPO/src/new.ts"
git -C "$REPO" add -A
added() { ( cd "$REPO" && commit_added_files ) | paste -sd, -; }
test_case "commit_added_files lists creations only, not modifications"
assert_eq 'src/new.ts' "$(added)"

git -C "$REPO" commit -qm second
git -C "$REPO" rm -q src/old.ts
test_case "a deletion is not an addition"
assert_eq '' "$(added)"

# --- commit_file_content: the version this commit CARRIES ---------------------------------
# Reading the worktree while listing files from the index makes a completeness check
# inspect content that is not what gets committed — a fail-OPEN hole for `git add -p`.
mkrepo
mkdir -p "$REPO/docs"
printf 'staged\n' > "$REPO/docs/wo.md"
git -C "$REPO" add docs/wo.md
printf 'worktree\n' > "$REPO/docs/wo.md"        # staged and worktree now differ
content() { commit_file_content "$REPO" docs/wo.md "$1"; }

test_case "a plain commit reads the INDEX version, not the working tree"
assert_eq 'staged' "$(content 'git commit -m x')"

test_case "commit -a reads the working tree (that is what -a will stage)"
assert_eq 'worktree' "$(content 'git commit -am x')"

test_case "an untracked file falls back to the working tree"
printf 'fresh\n' > "$REPO/docs/other.md"
assert_eq 'fresh' "$(commit_file_content "$REPO" docs/other.md 'git commit -m x')"

test_case "a path in neither index nor worktree yields nothing"
assert_eq '' "$(commit_file_content "$REPO" docs/gone.md 'git commit -m x')"

finish

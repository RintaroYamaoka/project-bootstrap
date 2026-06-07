#!/usr/bin/env bash
# Tests for scripts/velocity.sh — 週次 throughput / defect rate の横断計測 CLI。
#
# Why this exists: レビューを trust ladder で薄くする (Stage 2) とき、「薄くしても壊れて
# いない」ことを判定する唯一の客観データが defect rate (= fix/revert 率) の推移。user は
# 複数プロジェクトを並行担当するため、計測は単一 repo でなく複数 repo 横断で集計する。
# 出力は TSV (machine-greppable): <repo>\tw<weeks-ago>\t<commits>\t<merges>\t<fixrev>、
# 末尾に TOTAL 行と 4 週合算の defect 率。

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"

SCRIPTS_DIR="$(cd "$DIR/../../scripts" && pwd)"

VEL_OUT=""
VEL_EXIT=0
run_velocity() {
  local outf; outf="$(mktemp)"
  bash "$SCRIPTS_DIR/velocity.sh" "$@" >"$outf" 2>&1
  VEL_EXIT=$?
  VEL_OUT="$(cat "$outf")"
  rm -f "$outf"
}
assert_out_contains() {
  TESTS_RUN=$((TESTS_RUN + 1))
  case "$VEL_OUT" in
    *"$1"*) echo "  ok   [$CURRENT_TEST] out contains '$1'" ;;
    *) TESTS_FAILED=$((TESTS_FAILED + 1)); echo "  FAIL [$CURRENT_TEST] out missing '$1'"; printf '    out: %s\n' "$(printf '%s' "$VEL_OUT" | head -5)" ;;
  esac
}
assert_velocity_exit() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$VEL_EXIT" = "$1" ]; then echo "  ok   [$CURRENT_TEST] exit $1"
  else TESTS_FAILED=$((TESTS_FAILED + 1)); echo "  FAIL [$CURRENT_TEST] expected exit $1, got $VEL_EXIT"; fi
}

NOW=$(date +%s)
# commit_at <repo> <days-ago> <subject> — 日付固定で空 commit を積む
commit_at() {
  local repo="$1" days="$2" subj="$3" epoch
  epoch=$((NOW - days * 86400))
  GIT_AUTHOR_DATE="@$epoch" GIT_COMMITTER_DATE="@$epoch" \
    git -C "$repo" commit -q --allow-empty -m "$subj"
}
make_repo() {
  local tmp; tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  git -C "$tmp" config user.email t@t.test
  git -C "$tmp" config user.name tester
  printf '%s' "$tmp"
}

# repo A: 今週 feat×2 + fix×1、先週 feat×1
REPO_A="$(make_repo)"
commit_at "$REPO_A" 9 "feat: old work"
commit_at "$REPO_A" 2 "feat: a"
commit_at "$REPO_A" 1 "fix: broken a"
commit_at "$REPO_A" 1 "feat: b"

# repo B: 今週 revert×1
REPO_B="$(make_repo)"
commit_at "$REPO_B" 1 "Revert \"feat: bad\""

# 1. 単一 repo: 今週 (w0) は commits=3, fixrev=1。
test_case "single repo week-0 counts"
run_velocity "$REPO_A"
assert_velocity_exit 0
assert_out_contains "$REPO_A	w0	3	0	1"

# 2. 先週 (w1) は commits=1, fixrev=0。
test_case "single repo week-1 counts"
assert_out_contains "$REPO_A	w1	1	0	0"

# 3. 複数 repo 横断: TOTAL の w0 は A(3)+B(1)=4 commits, fixrev=2。
test_case "cross-repo TOTAL aggregates"
run_velocity "$REPO_A" "$REPO_B"
assert_velocity_exit 0
assert_out_contains "TOTAL	w0	4	0	2"

# 4. 4 週合算行に defect 率が出る (5 commits 中 2 fixrev = 40%)。
test_case "4-week summary carries defect rate"
assert_out_contains "TOTAL	4w	5	0	2	defect=40%"

# 5. merge commit は merges 列に数える。
REPO_C="$(make_repo)"
commit_at "$REPO_C" 3 "feat: base"
git -C "$REPO_C" switch -q -c feat/x
commit_at "$REPO_C" 2 "feat: x"
git -C "$REPO_C" switch -q - 2>/dev/null || git -C "$REPO_C" switch -q master 2>/dev/null || git -C "$REPO_C" switch -q main
NOWE=$((NOW - 86400))
GIT_AUTHOR_DATE="@$NOWE" GIT_COMMITTER_DATE="@$NOWE" git -C "$REPO_C" merge -q --no-ff -m "merge feat/x" feat/x
test_case "merge commits are counted"
run_velocity "$REPO_C"
assert_out_contains "$REPO_C	w0	2	1	0"

# 6. 非 git path は警告してスキップ、有効 repo が 1 つも無ければ exit 1。
test_case "non-git path alone exits 1"
run_velocity "$(mktemp -d)"
assert_velocity_exit 1

finish

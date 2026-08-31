#!/usr/bin/env bash
# Shared resolver for "which files will this `git commit` carry?"
#
# commit 関所は複数ある (lane 判定 / lint 判定)。それぞれが独自に index を読むと、`-a` の扱い
# のような細部で drift して片方だけが緩い穴になる (= detect-test-suite.sh を test/merge 両関所で
# 共有しているのと同じ理由、ADR 0005 guard 1)。単一権威にする。
#
# commit_files_from_cmd <git-commit-command>
#   stdout = repo 相対 path の改行区切り (sort -u)。**削除された file も含む** —
#   「lane 外の file を消した」も lane 違反なので、存在確認は呼び出し側の責務。
#   git が無い / repo 外なら空。

# commit_stages_all <git-commit-command>
#   return 0 = this commit form ALSO sweeps unstaged tracked changes (`-a` / `-am` / `--all`).
#   Split out as its own predicate because a second consumer needs the same answer:
#   lib/retired-terms.sh must pick `git diff --cached` vs `git diff HEAD` to decide which
#   ADDED lines the commit will actually carry. Two copies of this regex would drift on
#   exactly the case it was written for (`-m all` must NOT count), and the looser copy
#   becomes the silent hole — same single-authority reason this file exists at all.
#   (`-m` の引数に紛れた `-a` を拾わないよう、option 位置の短縮 flag だけを見る)
# Include guard — dispatcher が 1 プロセスに複数 gate を source するときの再読込抑止。
[ -n "${_BOOTSTRAP_LIB_COMMIT_FILES:-}" ] && return 0
_BOOTSTRAP_LIB_COMMIT_FILES=1

commit_stages_all() {
  printf '%s' "$1" | grep -qE '(^|[[:space:]])-[a-zA-Z]*a[a-zA-Z]*([[:space:]]|$)|(^|[[:space:]])--all([[:space:]]|$)'
}

commit_files_from_cmd() {
  local cmd="$1" staged

  staged=$(git diff --cached --name-only 2>/dev/null)

  # `git commit -a` / `-am` / `--all` は tracked の未 stage 変更もその場で stage する → 対象。
  if commit_stages_all "$cmd"; then
    staged=$(printf '%s\n%s\n' "$staged" "$(git diff --name-only 2>/dev/null)")
  fi

  printf '%s\n' "$staged" | grep -v '^[[:space:]]*$' | sort -u
}

# commit_added_files <git-commit-command>
#   stdout = repo 相対 path の改行区切り。**この commit が新しく足す file だけ** (A)。
#   `-a` / `--all` は untracked を stage しない (git の仕様) ので、追加は index 経由に限られる
#   = `--cached --diff-filter=A` が唯一の権威。「新規 source 面を作った」を commit 側で判定する
#   関所 (block-commit-if-impl-uncovered.sh) が使う。
commit_added_files() {
  git diff --cached --diff-filter=A --name-only 2>/dev/null | grep -v '^[[:space:]]*$' | sort -u
}

# commit_file_content <top> <rel> <git-commit-command>
#   stdout = **この commit が実際に運ぶ中身**。
#
#   なぜ worktree を直接読まないか: commit 関所が「commit に載る file 名」を index から取りながら
#   中身を disk から読むと、`git add -p` の部分 stage や stage 後の編集で **検査した中身と commit
#   される中身が別物**になる。完全性検査がそのズレを踏むと fail-open (未完成のまま通る) 側に倒れる。
#   retired 名 gate が `git diff --cached` 側の追加行を見ているのと同じ原則を、file 全体を読む
#   関所 (WO の完全性) にも適用するための単一権威。
#
#   `-a` / `--all` のときは worktree の内容がその場で stage される → worktree が正。
#   それ以外は index (`git show :<path>`) が正。index に無い (= untracked) なら worktree に fallback。
commit_file_content() {
  local top="$1" rel="$2" cmd="$3"

  if commit_stages_all "$cmd" && [ -f "$top/$rel" ]; then
    cat "$top/$rel"
    return 0
  fi
  git -C "$top" show ":$rel" 2>/dev/null && return 0
  [ -f "$top/$rel" ] && cat "$top/$rel"
  return 0
}

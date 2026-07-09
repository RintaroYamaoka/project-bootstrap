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

commit_files_from_cmd() {
  local cmd="$1" staged

  staged=$(git diff --cached --name-only 2>/dev/null)

  # `git commit -a` / `-am` / `--all` は tracked の未 stage 変更もその場で stage する → 対象。
  # (`-m` の引数に紛れた `-a` を拾わないよう、option 位置の短縮 flag だけを見る)
  if printf '%s' "$cmd" | grep -qE '(^|[[:space:]])-[a-zA-Z]*a[a-zA-Z]*([[:space:]]|$)|(^|[[:space:]])--all([[:space:]]|$)'; then
    staged=$(printf '%s\n%s\n' "$staged" "$(git diff --name-only 2>/dev/null)")
  fi

  printf '%s\n' "$staged" | grep -v '^[[:space:]]*$' | sort -u
}

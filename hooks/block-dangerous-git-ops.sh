#!/usr/bin/env bash
# Hook C — PreToolUse on Bash
# 並列 Claude / 別ターミナルの作業を消す destructive git op を blocking。
#
# 検出して exit 2 する pattern:
#   - git reset --hard                 (= uncommitted を全消去 / 他 session WIP も消える)
#   - git push -f / --force            (= 他 session の commit を remote から消す)
#   - git checkout -- . / -- <pathspec>  (= unstaged を消去)
#   - git restore .  / git restore --staged .  (= 全 restore)
#   - git clean -f / -fd / -fx          (= untracked を消去 / 他 session の新規 file)
#   - git branch -D / --delete --force  (= 未 merge branch 強制削除)
#
# `--force-with-lease` は通す (= 競合検出付き force push、相対安全)。
#
# user が明示的に必要とする場合は /permissions で hook を deny に変えて手動実行する。
# AI が default 経路で destructive op を踏まないことが規律の本旨。

set -u

INPUT=$(cat)
# shellcheck source=lib/parse-command.sh
. "$(dirname "$0")/lib/parse-command.sh"
if ! CMD="$(printf '%s' "$INPUT" | parse_command)"; then
  echo "project-bootstrap: could not parse the tool command from hook input — blocking to fail safe (fail-closed). If this is a false positive, disable this hook via /permissions." >&2
  exit 2
fi

[ -z "$CMD" ] && exit 0

# git で始まる command でなければ素通し
# printf '%s' で渡す (echo は先頭 '-' / backslash を解釈しうる — 全 hook で統一)
printf '%s' "$CMD" | grep -qE '(^|[[:space:]&|;()`]+)git[[:space:]]' || exit 0

# 危険 pattern check 関数
match() {
  printf '%s' "$CMD" | grep -qE "$1"
}

REASON=""

# git reset --hard (= 全 uncommitted 消去)
if match '(^|[[:space:]&|;()`]+)git[[:space:]]+reset[[:space:]]+(-[A-Za-z]*[hH]|--hard)([[:space:]]|$)'; then
  REASON="git reset --hard"

# git push --force / -f (= 他人の commit を remote から消去)。--force-with-lease は除外。
elif match '(^|[[:space:]&|;()`]+)git[[:space:]]+push([[:space:]]+[^&|;]*)*[[:space:]]+(--force[[:space:]]|--force$|-f[[:space:]]|-f$)'; then
  if ! match '(^|[[:space:]&|;()`]+)git[[:space:]]+push([[:space:]]+[^&|;]*)*[[:space:]]+--force-with-lease'; then
    REASON="git push --force / -f"
  fi

# git checkout -- (= unstaged を消去)
elif match '(^|[[:space:]&|;()`]+)git[[:space:]]+checkout[[:space:]]+--([[:space:]]|$)'; then
  REASON="git checkout -- <path>"

# git restore .  (cwd 全) / git restore --staged . (cwd 全 staged 戻し)
elif match '(^|[[:space:]&|;()`]+)git[[:space:]]+restore([[:space:]]+--staged)?[[:space:]]+(\.|--source=[^ ]+[[:space:]]+\.)([[:space:]]|$)'; then
  REASON="git restore . (全ファイル restore)"

# git clean -f / -fd / -fx / -df / --force。
# flag cluster の任意位置に f/F があれば block (= 旧 `[fF]` 末尾固定だと `-fd` `-fx` が漏れた)。
elif match '(^|[[:space:]&|;()`]+)git[[:space:]]+clean[[:space:]]+(-[A-Za-z]*[fF][A-Za-z]*|--force)([[:space:]]|$)'; then
  REASON="git clean -f (untracked 消去)"

# git branch -D / --delete --force
elif match '(^|[[:space:]&|;()`]+)git[[:space:]]+branch[[:space:]]+(-D|--delete[[:space:]]+--force|-d[[:space:]]+--force|--force[[:space:]]+--delete)'; then
  REASON="git branch -D (未 merge branch 強制削除)"
fi

[ -z "$REASON" ] && exit 0

cat >&2 <<EOF
project-bootstrap: blocking destructive git op — "$REASON"

このコマンドは並走している別 Claude / 別ターミナルの作業を消す可能性がある:
  - reset --hard / clean -f → uncommitted / untracked を消去
  - push -f → remote から他人の commit を消去
  - checkout -- / restore . → unstaged を消去
  - branch -D → 未 merge branch を消去

代替案:
  - 巻き戻したい変更がある    → 特定 file を git restore <path> で指定 / git stash で退避
  - 強い意図で force push 必要 → git push --force-with-lease (競合検出付き) を使う
  - 並走 session の影響を確認  → git status / git log --all --oneline -20 / git stash list を先に読む

それでも実行が必要なら、user に「destructive な X を実行して良いか」と明示確認してから /permissions で本 hook を一時 deny にする。
EOF
exit 2

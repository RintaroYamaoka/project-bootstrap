#!/usr/bin/env bash
# Hook D — PreToolUse on Bash
# 同一 working tree で並走する別 Claude / 別ターミナルの WIP を `git add -A` 等で
# 巻き込んで commit/stash する事故を構造的に block する。
#
# 検出して exit 2 する pattern:
#   - git add -A / --all              (= 全 tracked + untracked を stage)
#   - git add .  / git add ./         (= cwd 配下を全 stage)
#   - git add -u / --update           (= 全 tracked を stage)
#   - git commit -a / -am / --all     (= 全 tracked を auto-stage)
#   - git stash -u / --include-untracked (= 他人の untracked を巻き込む)
#   - git stash  (引数なし, 全 modified を退避 — 他人の WIP も拾う)
#
# 個別 file 指定 (`git add path/to/file`) は素通し。
# 規律: 自分が編集した file だけを path 指定で add する。
#
# 並走 Claude が居ない単独セッションでも本 hook は発火するが、
# 個別 file add に矯正することで「自分が触ったもの」の意識を default で保つ。

set -u

INPUT=$(cat)

# shellcheck source=lib/parse-command.sh
. "$(dirname "$0")/lib/parse-command.sh"
if ! CMD="$(printf '%s' "$INPUT" | parse_command)"; then
  echo "project-bootstrap: could not parse the tool command from hook input — blocking to fail safe (fail-closed). If this is a false positive, disable this hook via /permissions." >&2
  exit 2
fi

[ -z "$CMD" ] && exit 0

echo "$CMD" | grep -qE '(^|[[:space:]&|;()`]+)git[[:space:]]' || exit 0

match() {
  echo "$CMD" | grep -qE "$1"
}

REASON=""

# git add -A / --all
if match '(^|[[:space:]&|;()`]+)git[[:space:]]+add([[:space:]]+[^[:space:]]+)*[[:space:]]+(-A|--all)([[:space:]]|$)'; then
  REASON="git add -A / --all"

# git add -u / --update
elif match '(^|[[:space:]&|;()`]+)git[[:space:]]+add([[:space:]]+[^[:space:]]+)*[[:space:]]+(-u|--update)([[:space:]]|$)'; then
  REASON="git add -u / --update"

# git add .  / git add ./
elif match '(^|[[:space:]&|;()`]+)git[[:space:]]+add[[:space:]]+\./?([[:space:]]|$)'; then
  REASON="git add ."

# git commit -a / -am / -aim / --all (短 flag は -[a-z]*a[a-z]* で拾う)
elif match '(^|[[:space:]&|;()`]+)git[[:space:]]+commit([[:space:]]+[^[:space:]]+)*[[:space:]]+-[A-Za-z]*a[A-Za-z]*([[:space:]]|$)'; then
  REASON="git commit -a / -am (全 tracked auto-stage)"
elif match '(^|[[:space:]&|;()`]+)git[[:space:]]+commit([[:space:]]+[^[:space:]]+)*[[:space:]]+--all([[:space:]]|$)'; then
  REASON="git commit --all"

# git stash -u / --include-untracked
elif match '(^|[[:space:]&|;()`]+)git[[:space:]]+stash([[:space:]]+(push|save))?([[:space:]]+[^[:space:]]+)*[[:space:]]+(-u|--include-untracked)([[:space:]]|$)'; then
  REASON="git stash -u / --include-untracked"

# git stash 引数なし (= 全 modified 退避)
elif match '(^|[[:space:]&|;()`]+)git[[:space:]]+stash([[:space:]]*$|[[:space:]]+(push|save)([[:space:]]*$|[[:space:]]+-m))'; then
  # ただし -- <pathspec> 付き / -m <msg> 後にメッセージのみ / push -p (patch) は通す。
  # 簡易判定: stash 直後の token が path-like (= path指定あり) なら通す。
  REST=$(echo "$CMD" | sed -E 's/^.*git[[:space:]]+stash([[:space:]]+(push|save))?//')
  if echo "$REST" | grep -qE '(^|[[:space:]])--([[:space:]]|$)'; then
    # `-- <pathspec>` 付き = 対象限定 stash (= 他人の WIP を巻き込まない) なので通す。
    # `--message` は `--` の後に space/end が来ないのでここに該当しない。
    :
  elif echo "$REST" | grep -qE '(^|[[:space:]])(-m|--message)[[:space:]]+'; then
    # message 指定だけで pathspec が無いケースは「全退避」なので block
    REASON="git stash (path 指定なし、全 modified 退避)"
  elif [ -z "$(echo "$REST" | tr -d '[:space:]')" ]; then
    REASON="git stash (引数なし、全 modified 退避)"
  fi
fi

[ -z "$REASON" ] && exit 0

cat >&2 <<EOF
project-bootstrap: blocking bulk-staging op — "$REASON"

このコマンドは並走している別 Claude / 別ターミナル / IDE の WIP を巻き込む可能性がある:
  - git add -A / . / -u は cwd 配下の全 modified/untracked を stage する
  - git commit -a は全 tracked を auto-stage して commit する
  - git stash (path 指定なし) は他人の WIP も退避してしまう

規律: **自分が編集した file を path 指定で add する**。
  例) git add path/to/foo.ts path/to/foo.test.ts
      git commit -m "..."

確認手順:
  1. git status --porcelain で staged / unstaged / untracked を列挙
  2. 自分が編集した file だけを git add <path> で個別に stage
  3. 残った変更が他人 WIP かどうか確認 (= 触っていないなら別 session の作業の可能性)

それでも全 add が必要なら、user に「他 session の変更を一緒に commit して良いか」と明示確認してから /permissions で本 hook を一時 deny にする。
EOF
exit 2

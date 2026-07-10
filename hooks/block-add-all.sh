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

# 高速素通し: "git" が文字列に無ければ tokenize するまでもない。
case "$CMD" in *git*) ;; *) exit 0 ;; esac

# 判定は segment 単位の token walk (単一権威 lib/git-invocation.sh、ADR 0019)。
# 旧実装は (1) 検出 regex が path-prefixed git / git グローバルオプション形を素通りさせ、
# (2) stash 判定の greedy sed が compound command の最後の segment しか見なかった
# (`git stash && echo done` の bare stash が素通り — 2026-07-10 監査で実測)。
# shellcheck source=lib/git-invocation.sh
. "$(dirname "$0")/lib/git-invocation.sh"

REASON=""

# noglob で word-split する (token に * / ? が混ざっても filesystem 展開させない)。
NOGLOB=0
case $- in *f*) ;; *) NOGLOB=1; set -f ;; esac

# ── git add: bulk-staging flag / 先頭 `.` pathspec (segment ごとに判定)
while IFS= read -r line; do
  # shellcheck disable=SC2086
  set -- $line
  FIRST=1
  while [ $# -gt 0 ]; do
    tok="$1"; shift
    case "$tok" in
      -A|--all)    REASON="git add -A / --all"; break ;;
      -u|--update) REASON="git add -u / --update"; break ;;
    esac
    if [ "$FIRST" = 1 ]; then
      # `git add .` / `git add ./` は add 直後の `.` のみ block (`git add -- .` は
      # 明示 pathspec separator 付き = 素通し、従来挙動)。
      case "$tok" in .|./) REASON="git add ."; break ;; esac
      FIRST=0
    fi
  done
  [ -n "$REASON" ] && break
done < <(git_subcommand_arglines "$CMD" add)

# ── git commit -a / -am / -aim / --all (短 flag 結合は -...a... で拾う)
if [ -z "$REASON" ]; then
  while IFS= read -r line; do
    # shellcheck disable=SC2086
    set -- $line
    while [ $# -gt 0 ]; do
      tok="$1"; shift
      case "$tok" in
        --all) REASON="git commit --all"; break ;;
        --*) ;;   # long flag (--amend 等) は auto-stage ではない
        -*)
          if [[ "$tok" =~ ^-[A-Za-z]*a[A-Za-z]*$ ]]; then
            REASON="git commit -a / -am (全 tracked auto-stage)"; break
          fi ;;
      esac
    done
    [ -n "$REASON" ] && break
  done < <(git_subcommand_arglines "$CMD" commit)
fi

# ── git stash: -u / --include-untracked、および pathspec なしの全退避
if [ -z "$REASON" ]; then
  while IFS= read -r line; do
    # shellcheck disable=SC2086
    set -- $line
    case "${1:-}" in push|save) shift ;; esac
    HAS_MSG=0; HAS_SEP=0; HAS_OTHER=0
    while [ $# -gt 0 ]; do
      tok="$1"; shift
      case "$tok" in
        -u|--include-untracked) REASON="git stash -u / --include-untracked"; break ;;
        --)                     HAS_SEP=1 ;;
        -m|--message|--message=*) HAS_MSG=1 ;;
        *)                      HAS_OTHER=1 ;;
      esac
    done
    [ -n "$REASON" ] && break
    if [ "$HAS_SEP" = 1 ]; then
      # `-- <pathspec>` 付き = 対象限定 stash (= 他人の WIP を巻き込まない) なので通す。
      :
    elif [ "$HAS_MSG" = 1 ]; then
      # message 指定だけで pathspec が無いケースは「全退避」なので block
      REASON="git stash (path 指定なし、全 modified 退避)"
    elif [ "$HAS_OTHER" = 0 ]; then
      REASON="git stash (引数なし、全 modified 退避)"
    fi
    [ -n "$REASON" ] && break
  done < <(git_subcommand_arglines "$CMD" stash)
fi

[ "$NOGLOB" = 1 ] && set +f

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

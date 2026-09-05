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

# shellcheck source=lib/parse-command.sh
. "${BASH_SOURCE[0]%/*}/lib/parse-command.sh"
# shellcheck source=lib/git-invocation.sh
. "${BASH_SOURCE[0]%/*}/lib/git-invocation.sh"

# ── なぜ regex をやめて walker に寄せたか (ADR 0019 の単一権威に合流、2026-09-05)
#
# 旧実装は `git[[:space:]]+push([[:space:]]+[^&|;]*)*[[:space:]]+(-f|--force)` の類を
# CMD 全体に当てていた。この形は「git push という文字列」と「後ろのどこかにある -f」を
# 別々の場所から拾えるので、**git を一切起動しないコマンドを block した**:
#
#   pkill -9 -f "git push origin --delete"      → 「git push … -f」に見える
#   grep -f patterns.txt -- "git push"          → 同上
#
# 実測 (2026-09-04): remote branch の後片付け中に pkill が止められた。MAINTENANCE.md が
# 書いているとおり「誤検知は安全側ではなく、規律を回避する動機を作る」。
#
# 現実装は lib/git-invocation.sh の walker で **各 git 起動の argline を取り出し**、
# その invocation 自身の token だけを見る。引用の中の "git push" は token `"git` になり
# git head と一致しないので拾わない。危険 flag も他の invocation から借りてこられない。
# 検出力は落ちない (path 前置 /usr/bin/git・global option `git -C dir push` は walker が
# 従来どおり拾う)。walker 既知の残余 (`sh -c "git push --force"` の under-detect) は
# ADR 0019 に記載のとおりで、ここでも同じ (commit 時 gate と server 側が net)。

# _dg_tok <token> <argline> — argline に <token> が独立 token として在るか。
_dg_tok() {
  local l=" $2 "
  case "$l" in *" $1 "*) return 0 ;; esac
  return 1
}

# _dg_short_cluster <letters> <argline> — `-fd` `-xf` のような単一 dash の flag cluster に
# <letters> のどれかが含まれるか (`--force` のような long option は対象外)。
_dg_short_cluster() {
  local letters="$1" line="$2" t c i
  for t in $line; do
    case "$t" in
      --*) continue ;;
      -?*) ;;
      *) continue ;;
    esac
    i=1
    while [ "$i" -lt "${#t}" ]; do
      c="${t:$i:1}"
      case "$letters" in *"$c"*) return 0 ;; esac
      i=$((i+1))
    done
  done
  return 1
}

# _dg_any <sub> <predicate> — `git <sub>` の各起動の argline を predicate に掛ける。
# cmd_invokes_git_subcommand (fork ゼロ) で先に絞るので、その subcommand を実際に
# 起動していない command では argline 収集の fork が起きない。
_dg_any() {
  local sub="$1" pred="$2" lines line
  cmd_invokes_git_subcommand "$CMD" "$sub" || return 1
  lines=$(git_subcommand_arglines "$CMD" "$sub")
  while IFS= read -r line || [ -n "$line" ]; do
    "$pred" "$line" && return 0
  done <<<"$lines"
  return 1
}

_dg_is_reset_hard()   { _dg_tok --hard "$1" || _dg_short_cluster hH "$1"; }
_dg_is_force_push()   {
  _dg_tok --force-with-lease "$1" && return 1
  _dg_tok --force "$1" || _dg_tok -f "$1"
}
_dg_is_checkout_dd()  { _dg_tok -- "$1"; }
_dg_is_restore_all()  { _dg_tok . "$1"; }
_dg_is_clean_force()  { _dg_tok --force "$1" || _dg_short_cluster fF "$1"; }
_dg_is_branch_force() {
  _dg_tok -D "$1" && return 0
  _dg_tok --force "$1" || return 1
  _dg_tok --delete "$1" || _dg_tok -d "$1"
}

# gate 本体 — 契約は lib/standalone.sh ヘッダ参照 (global CMD を読む / return 0=pass, 2=block)。
gate_block_dangerous_git_ops() {
  local REASON=""

  # 高速素通し (fork ゼロ): "git" が無ければ walker を回すまでもない。
  case "$CMD" in *git*) ;; *) return 0 ;; esac

  if   _dg_any reset    _dg_is_reset_hard;   then REASON="git reset --hard"
  elif _dg_any push     _dg_is_force_push;   then REASON="git push --force / -f"
  elif _dg_any checkout _dg_is_checkout_dd;  then REASON="git checkout -- <path>"
  elif _dg_any restore  _dg_is_restore_all;  then REASON="git restore . (全ファイル restore)"
  elif _dg_any clean    _dg_is_clean_force;  then REASON="git clean -f (untracked 消去)"
  elif _dg_any branch   _dg_is_branch_force; then REASON="git branch -D (未 merge branch 強制削除)"
  fi

[ -z "$REASON" ] && return 0

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
  - merge 済 branch を片付けたい → scripts/branch-cleanup.sh (PR 状態を根拠に取ってから消す。-D を手で叩かない)

それでも実行が必要なら、user に「destructive な X を実行して良いか」と明示確認してから /permissions で本 hook を一時 deny にする。
EOF
return 2
}

# 単体起動 (tests / vendoring 消費者) — dispatcher からは source されるので走らない。
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  # shellcheck source=lib/standalone.sh
  . "${BASH_SOURCE[0]%/*}/lib/standalone.sh"
  bootstrap_standalone_bash_gate gate_block_dangerous_git_ops
fi

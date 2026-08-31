#!/usr/bin/env bash
# Hook N — PreToolUse on Bash for `git worktree add`
# WIP 上限を fail-closed で強制する gate (ADR 0005 guard 3)。
#
# 背景: `.bootstrap-wip` はこれまで resolve-wip-limit.sh が checklist に**表示**するだけの値で、
# 並列度がそれを超えても何も block しなかった (= 強制なき宣言)。scrum の本質は WIP 制限であり、
# review 帯域 (= 複数 repo 共有の単一資源) を守るには lane を開く数そのものを縛る必要がある。
# 本 hook は「並列 lane を 1 本開く行為」= `git worktree add` を信号に、既存の linked worktree が
# 宣言 wip_limit に達していれば exit 2。
#
# 限界 (ADR 0005): hook は Workflow 内部の isolation worktree 生成を観測できない (main session の
# Bash tool 呼び出しではないため)。本 hook が縛るのは観測可能な `git worktree add` (skill / 人間 /
# lead が開く lane)。Workflow 内部 lane の暴走は統合の入口 (block-unreviewed-merge.sh: 各 lane に
# review 記録 + 実スイート) が review 帯域を守る最終 net。
#
# fail-mode (memory feedback_gate_signal_and_failmode 準拠):
#   - コマンド解析不能 = fail-closed (parse-command の契約。bypass 防止)
#   - 根拠不在 = fail-open: 非 worktree-add / 非 git / docs/bootstrap/sprint 未採用 (opt-in) /
#     .bootstrap-wip 未宣言 or 整数として解析不能 (= 宣言した repo でだけ縛る。opt-in 尊重)
#
# opt-in: docs/bootstrap/sprint/ が在るときだけ発火。jq 非依存。

set -u

# shellcheck source=lib/parse-command.sh
. "${BASH_SOURCE[0]%/*}/lib/parse-command.sh"
# shellcheck source=lib/resolve-docs.sh
. "${BASH_SOURCE[0]%/*}/lib/resolve-docs.sh"
# shellcheck source=lib/resolve-wip-limit.sh
. "${BASH_SOURCE[0]%/*}/lib/resolve-wip-limit.sh"
# shellcheck source=lib/repo-top.sh
. "${BASH_SOURCE[0]%/*}/lib/repo-top.sh"

# gate 本体 — 契約は lib/standalone.sh ヘッダ参照 (global CMD を読む / return 0=pass, 2=block)。
gate_block_over_wip_parallel() {
  local TOP LIMIT TOTAL LINKED

# 高速素通し (fork ゼロ): "git" が無ければ下の grep を払うまでもない。
case "$CMD" in *git*) ;; *) return 0 ;; esac

# `git worktree add` でなければ素通し (remove / list / prune / move は lane 生成ではない)。
# printf '%s' で渡す (echo は先頭 '-' / backslash を解釈しうる — 全 hook で統一)
printf '%s' "$CMD" | grep -qE '(^|[[:space:]&|;()`]+)git[[:space:]]+worktree[[:space:]]+add([[:space:]]|$)' || return 0

# repo root を解決。非 git は根拠不在 → fail-open。
repo_top_var
TOP="$REPO_TOP"
[ -z "$TOP" ] && return 0

# opt-in: sprint flow を採用した project でのみ発火。
# ディレクトリは `docs/bootstrap/sprint` (新) / `docs/sprint` (旧) どちらでも可 (ADR 0020)。
[ -d "$(resolve_docs_dir "$TOP" sprint)" ] || return 0

# 宣言された wip_limit を整数で取る。未宣言/解析不能は fail-open (opt-in を尊重)。
# 判定は表示版 resolve_wip_limit と同じ lib (= 単一権威。drift 防止)。
LIMIT="$(resolve_wip_limit_int)" || return 0

# 現在の linked worktree 数 = (全 worktree 行) - 1 (= main worktree を除く)。
TOTAL=$(git worktree list --porcelain 2>/dev/null | grep -c '^worktree ')
[ "$TOTAL" -ge 1 ] 2>/dev/null || TOTAL=1
LINKED=$((TOTAL - 1))

# 既存 lane 数が上限に達していれば、もう 1 本開く行為を block (LINKED + 1 > LIMIT)。
if [ "$LINKED" -ge "$LIMIT" ]; then
  cat >&2 <<EOF
project-bootstrap: blocking 'git worktree add' — WIP 上限 ($LIMIT lanes) に達している (現在 $LINKED 本)。

この cap は **terminal worker lane の路** (= `git worktree add`) にだけ掛かる。scrum の本質は並列の
最大化でなく WIP の制限で、worker 路の律速は人間のレビュー帯域 (複数 repo 共有の単一資源) — lane を
増やしてもレビューが律速で throughput は増えない。対処:
  1. 開いている lane を 1 本 integrate (merge + 統合 verify) して閉じてから次を開く
  2. その lane の必要性が本当に高く、leaf が完全 disjoint なら、.bootstrap-wip の整数を 1 つ上げる
     (= per-project の既定変更。sprint 固有の逸脱なら board.json の wip_limit + _wip_note に理由を書く)
  3. read-only の探索/監査/レビューを並列化したいだけなら worktree は不要 — それは lane ではなく
     breadth ファンアウト (ADR 0005) で、wip_limit の対象外
  4. もっと並列が要るなら **Workflow/subagent 路**に回す — main session が orchestrate する mutation
     lane は engine 上限 (min(16, cores-2)) 律速で wip 非対象、帯域は統合関所 (block-unreviewed-merge)
     が自動で守る (ADR 0006)。worker 路の帯域天井に縛られているのはこの hook が見る路だけ
EOF
  return 2
fi

return 0
}

# 単体起動 (tests / vendoring 消費者) — dispatcher からは source されるので走らない。
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  # shellcheck source=lib/standalone.sh
  . "${BASH_SOURCE[0]%/*}/lib/standalone.sh"
  bootstrap_standalone_bash_gate gate_block_over_wip_parallel
fi

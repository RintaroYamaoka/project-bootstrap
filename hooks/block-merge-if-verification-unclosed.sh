#!/usr/bin/env bash
# Hook — PreToolUse on Bash for `git merge`
# 統合の入口で「動作テスト計画 (verification plan) が閉じている」ことを fail-closed に強制する。
#
# 背景 (docs/decisions/0007 + appo-followup dogfood): コードレベルのバグは TDD hook + レビューで
# 潰れた。残余リスクは継ぎ目 (cross-repo 契約 / 要件 / 「実物を見ずの完了」/ 環境) に移動した。
# それらは repo 内 unit test の射程外で、しかも緑の unit test が誤った契約を固定して false
# confidence を配る (mood incident: zod min(1) の test は緑のまま実予約を全 reject)。防御は
# verification を「永続・共有・fail-closed な成果物」にし、その成果物が閉じていることを統合の
# precondition にすること。「良いテスト」は強制できないが「計画の存在と未解決行ゼロ」は強制できる
# (TDD hook が test の存在を、review gate が verdict の存在を強制するのと同型)。
#
# 信号 = 統合行為 (= 並列 lane branch の git merge)。「どの方式で並列開発したか」に依存しないよう、
# review gate (block-unreviewed-merge) と同じ lane 集合を使う:
#   (a) 活性 board の task branch  (b) linked worktree に checkout された branch (ADR 0004)。
#
# fail-mode (memory feedback_gate_signal_and_failmode 準拠):
#   - コマンド解析不能 = fail-closed (parse-command の契約。bypass 防止)
#   - 根拠不在 = fail-open: 非 merge / 非 git / docs/verification/ 未採用 (= opt-in) /
#     merge 対象が lane branch でない (通常の merge を一切妨げない)
#   - 採用済みで lane branch を merge するのに計画が無い / 空 / 未解決行が残る = fail-closed
#     (= 「計画を書かない」で gate を素通りさせない。強制したい判定を advisory に逃さない)
#
# 射程の境界 (ADR 0007 で明示): この gate は統合 (= lane branch の merge) を信号にするので、
# branch を切らない逐次作業は捕まえない。そこは `verification` skill (plan 時の precondition) と
# doctor (配備可視化) が担う。trunk への全変更を縛る universal 版は push-to-protected への拡張余地。
#
# bypass: 例外的に必要なら /permissions で本 hook を一時 deny。

set -u

INPUT=$(cat)
# shellcheck source=lib/parse-command.sh
. "$(dirname "$0")/lib/parse-command.sh"
if ! CMD="$(printf '%s' "$INPUT" | parse_command)"; then
  echo "project-bootstrap: could not parse the tool command from hook input — blocking to fail safe (fail-closed). If this is a false positive, disable this hook via /permissions." >&2
  exit 2
fi

[ -z "$CMD" ] && exit 0

# git merge でなければ素通し
echo "$CMD" | grep -qE '(^|[[:space:]&|;()`]+)git[[:space:]]+merge([[:space:]]|$)' || exit 0

# repo root を解決。非 git は根拠不在 → fail-open。
command -v git >/dev/null 2>&1 || exit 0
TOP=$(git rev-parse --show-toplevel 2>/dev/null | tr '\\' '/' | tr -s '/')
[ -z "$TOP" ] && exit 0

# opt-in: verification flow を採用した project (= docs/verification/ が在る) でのみ発火。
[ -d "$TOP/docs/verification" ] || exit 0

# 並列 lane の branch 集合を組み立てる (review gate と同じ信号)。
# (a) 活性 board の task branch (docs/sprint 採用かつ活性のときのみ。存在ではなく活性)。
LANE_BRANCHES=""
BOARD="$TOP/docs/sprint/board.json"
if [ -d "$TOP/docs/sprint" ]; then
  # shellcheck source=lib/board-liveness.sh
  . "$(dirname "$0")/lib/board-liveness.sh"
  if board_has_active_tasks "$BOARD"; then
    LANE_BRANCHES=$(grep -oE '"branch"[[:space:]]*:[[:space:]]*"[^"]*"' "$BOARD" | sed 's/.*"branch"[[:space:]]*:[[:space:]]*"//; s/"$//')
  fi
fi

# (b) linked worktree に checkout されている branch。最初の block は main worktree 自身なので除外。
WT_BRANCHES=$(git worktree list --porcelain 2>/dev/null | sed -n '/^$/,$p' | sed -n 's|^branch refs/heads/||p')
if [ -n "$WT_BRANCHES" ]; then
  LANE_BRANCHES=$(printf '%s\n%s' "$LANE_BRANCHES" "$WT_BRANCHES")
fi

# lane が 1 つも無ければ判定根拠なし → fail-open (通常の merge を一切妨げない)。
[ -z "$(printf '%s' "$LANE_BRANCHES" | tr -d '[:space:]')" ] && exit 0

is_lane_branch() {
  local tok="$1" b
  while IFS= read -r b; do
    [ -n "$b" ] && [ "$tok" = "$b" ] && return 0
  done <<< "$LANE_BRANCHES"
  return 1
}

# `git merge` 以降の引数から merge 対象 branch を探す (review gate と同じ解析)。
ARGS=$(printf '%s' "$CMD" | sed -E 's/^.*git[[:space:]]+merge//')
BRANCH=""
SKIP_NEXT=0
# shellcheck disable=SC2086
set -- $ARGS
while [ $# -gt 0 ]; do
  tok="$1"; shift
  if [ "$SKIP_NEXT" = 1 ]; then SKIP_NEXT=0; continue; fi
  case "$tok" in
    -m|--message|-F|--file|--into-name|-S|--gpg-sign|--strategy|-s|--strategy-option|-X) SKIP_NEXT=1; continue ;;
    -*) continue ;;
  esac
  if is_lane_branch "$tok"; then
    BRANCH="$tok"
    break
  fi
done

# merge 対象が並列 lane の branch でない → 根拠不在 → fail-open。
[ -z "$BRANCH" ] && exit 0

# shellcheck source=lib/verification-plan.sh
. "$(dirname "$0")/lib/verification-plan.sh"
PLAN="$TOP/docs/verification/$(printf '%s' "$BRANCH" | tr '/' '_').md"

if [ ! -s "$PLAN" ]; then
  cat >&2 <<EOF
project-bootstrap: blocking merge of "$BRANCH" — no verification plan.

並列 lane の branch を、動作テスト計画なしに統合しようとした。verification flow を採用した
repo (docs/verification/) では、統合の precondition として計画が要る。対処 (verification skill):
  1. 意図と「跨いだ境界」から検証すべき挙動を導く (実装からでなく — 実装追認テストを避ける)
  2. $PLAN に記録する。各行: STATUS | kind | behaviour | oracle | by | evidence
  3. 自動行を実行して PASS に、人間しか採点できない行は HUMAN にして実施・記録、テストしないと
     決めた行は理由つき DROP にする。OPEN 行 (TODO/FAIL/HUMAN) が残る限り統合は通らない

計画を skip したい例外時は /permissions で本 hook を一時 deny にする。
EOF
  exit 2
fi

ROWS="$(vplan_row_count "$PLAN")"
if [ "$ROWS" = 0 ]; then
  cat >&2 <<EOF
project-bootstrap: blocking merge of "$BRANCH" — verification plan has no test cases.

計画ファイル ($PLAN) は在るが、データ行 (STATUS | kind | behaviour | ...) が 1 つも無い。
空の計画は「検証ゼロ」を緑に見せる儀式。検証すべき挙動を最低 1 行書く (テストしないと判断した
ものは理由つき DROP 行で明示する — 無音で省かない)。
EOF
  exit 2
fi

OPEN="$(vplan_open_rows "$PLAN")"
BAD="$(vplan_bad_drops "$PLAN")"

if [ -n "$OPEN" ] || [ -n "$BAD" ]; then
  cat >&2 <<EOF
project-bootstrap: blocking merge of "$BRANCH" — verification plan is not closed.

計画ファイル: $PLAN
EOF
  if [ -n "$OPEN" ]; then
    echo "" >&2
    echo "未解決の行 (TODO=未実施 / FAIL=失敗 / HUMAN=人間の実施待ち):" >&2
    printf '  %s\n' "$OPEN" >&2
  fi
  if [ -n "$BAD" ]; then
    echo "" >&2
    echo "理由なき DROP (テストしない判断には理由が要る — 無音カット禁止):" >&2
    printf '  %s\n' "$BAD" >&2
  fi
  cat >&2 <<'EOF'

対処: OPEN 行を PASS (オラクルで検証) / 理由つき DROP に解決してから統合する。
PASS にする前に各行へ kill-question を一度問う: 「このテストが緑のまま、ユーザーが困る
状態はありうるか?」— Yes ならオラクルが間違っている (mood の罠)。
EOF
  exit 2
fi

exit 0

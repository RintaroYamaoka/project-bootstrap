#!/usr/bin/env bash
# Hook M — PreToolUse on Bash for `git merge`
# AI レビューを統合の precondition として fail-closed に強制する gate (trust ladder の Stage 2)。
#
# 背景: 並列フローの throughput 天井は「人間が全 diff を直列レビューする」ことに在る
# (sprint-plan/SKILL.md が明文化)。Stage 2 では一次レビューを read-only の adversarial AI
# レビュー (integrate skill Step 2) に移し、人間は verdict + 指摘 + サンプル + 統合境界だけを
# 読む。だが「レビューを済ませた」を advisory にすると忘れられる — 本 hook は TDD hook が
# test の存在を強制するのと同型に、**統合行為 (= 活性 sprint 中の task branch の git merge)**
# を信号として、レビュー記録 (docs/sprint/reviews/<branch>.md, `/`→`_`) の存在と verdict を
# precondition 化する。「良いレビュー」は強制できないが「レビューの存在と結論」は強制できる。
#
# fail-mode (memory feedback_gate_signal_and_failmode 準拠):
#   - コマンド解析不能 = fail-closed (parse-command の契約。bypass 防止)
#   - 根拠不在 = fail-open: 非 merge コマンド / 非 git / docs/sprint 未採用 / sprint 非活性
#     (= board の活性判定は lib/board-liveness.sh。存在ではなく活性 — 2026-06-07 incident) /
#     merge 対象が board の task branch でない (通常の merge を一切妨げない)
#   - verdict: reject の記録がある merge は**より強く** block (却下の踏み越えを許さない)
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

# 活性 sprint 中でなければ素通し (存在ではなく活性 — 完了済み board の残置で発火しない)。
BOARD="$TOP/docs/sprint/board.json"
# shellcheck source=lib/board-liveness.sh
. "$(dirname "$0")/lib/board-liveness.sh"
board_has_active_tasks "$BOARD" || exit 0

# board に宣言された task branch 集合を取り出す (exact 文字列比較 — regex escape 問題を回避)。
TASK_BRANCHES=$(grep -oE '"branch"[[:space:]]*:[[:space:]]*"[^"]*"' "$BOARD" | sed 's/.*"branch"[[:space:]]*:[[:space:]]*"//; s/"$//')
[ -z "$TASK_BRANCHES" ] && exit 0   # branch 宣言の無い board は判定根拠なし → fail-open

is_task_branch() {
  local tok="$1" b
  while IFS= read -r b; do
    [ "$tok" = "$b" ] && return 0
  done <<< "$TASK_BRANCHES"
  return 1
}

# `git merge` 以降の引数から merge 対象 branch を探す。flag はスキップ、引数を取る flag
# (-m/-F 等) はその値もスキップ (= message が branch に見える誤検知を防ぐ)。
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
  if is_task_branch "$tok"; then
    BRANCH="$tok"
    break
  fi
done

# merge 対象が task branch でない → 根拠不在 → fail-open。
[ -z "$BRANCH" ] && exit 0

REVIEW="$TOP/docs/sprint/reviews/$(printf '%s' "$BRANCH" | tr '/' '_').md"

if [ -s "$REVIEW" ]; then
  if grep -qiE '^[[:space:]]*verdict:[[:space:]]*approve' "$REVIEW"; then
    exit 0
  fi
  if grep -qiE '^[[:space:]]*verdict:[[:space:]]*reject' "$REVIEW"; then
    cat >&2 <<EOF
project-bootstrap: blocking merge of "$BRANCH" — review verdict is REJECT.

レビュー記録 ($REVIEW) が verdict: reject を持つ branch を merge しようとした。
却下されたレビューを踏み越える統合は許可しない。対処:
  1. 指摘を worker lane で修正し、re-review を回して verdict: approve に更新する
  2. 指摘が誤りなら、レビュー記録に反証を追記した上で verdict を更新する (記録を消さない)
EOF
    exit 2
  fi
fi

cat >&2 <<EOF
project-bootstrap: blocking merge of "$BRANCH" — no completed review record.

活性 sprint の task branch を、AI レビューの記録なしに統合しようとした。
統合の前提条件 (integrate skill Step 2):
  1. read-only の adversarial レビュー agent でこの branch の diff を審査する
  2. 結果を $REVIEW に書く — 必須行: "verdict: approve" または "verdict: reject" + 指摘一覧
  3. approve なら merge は通る。reject なら worker lane で修正してから re-review

レビューそのものを skip したい例外時は /permissions で本 hook を一時 deny にする。
EOF
exit 2

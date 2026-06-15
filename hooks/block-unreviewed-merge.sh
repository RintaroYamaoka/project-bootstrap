#!/usr/bin/env bash
# Hook M — PreToolUse on Bash for `git merge`
# AI レビューを統合の precondition として fail-closed に強制する gate (trust ladder の Stage 2)。
#
# 背景: 並列フローの throughput 天井は「人間が全 diff を直列レビューする」ことに在る
# (sprint-plan/SKILL.md が明文化)。Stage 2 では一次レビューを read-only の adversarial AI
# レビュー (integrate skill Step 2) に移し、人間は verdict + 指摘 + サンプル + 統合境界だけを
# 読む。だが「レビューを済ませた」を advisory にすると忘れられる — 本 hook は TDD hook が
# test の存在を強制するのと同型に、**統合行為 (= 並列 lane の branch の git merge)** を信号
# として、レビュー記録 (docs/sprint/reviews/<branch>.md, `/`→`_`) の存在と verdict を
# precondition 化する。「良いレビュー」は強制できないが「レビューの存在と結論」は強制できる。
#
# 「並列 lane の branch」は 2 つの集合の和 (ADR 0004):
#   (a) 活性 board の task branch (= sprint flow の正式 lane)
#   (b) この repo の linked worktree に checkout されている branch (= Workflow サブエージェント
#       の隔離 worktree / 手動 worktree 並走)。実際の並列開発は board を作らない形でも起きており
#       (docs/incidents/2026-06-11-parallel-mode-gate-coverage)、関所が「どの方式で作ったか」に
#       依存すると方式の選択 (= モデルの気分) で gate が無音になる。worktree という物理的痕跡を
#       信号にすれば、どの方式でも統合の入口で必ず捕まる。
#
# fail-mode (memory feedback_gate_signal_and_failmode 準拠):
#   - コマンド解析不能 = fail-closed (parse-command の契約。bypass 防止)
#   - 根拠不在 = fail-open: 非 merge コマンド / 非 git / docs/sprint 未採用 (= opt-in、他 gate
#     と同じ採用宣言) / merge 対象が (a)(b) のどちらでもない (通常の merge を一切妨げない)。
#     board の活性判定は lib/board-liveness.sh (存在ではなく活性 — 2026-06-07 incident)
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

# opt-in: sprint flow を採用した project (= docs/sprint/ が在る) でのみ発火。
[ -d "$TOP/docs/sprint" ] || exit 0

# 並列 lane の branch 集合を組み立てる。
# (a) 活性 board の task branch (存在ではなく活性 — 完了済み board の残置で発火しない)。
BOARD="$TOP/docs/sprint/board.json"
# shellcheck source=lib/board-liveness.sh
. "$(dirname "$0")/lib/board-liveness.sh"
LANE_BRANCHES=""
if board_has_active_tasks "$BOARD"; then
  LANE_BRANCHES=$(grep -oE '"branch"[[:space:]]*:[[:space:]]*"[^"]*"' "$BOARD" | sed 's/.*"branch"[[:space:]]*:[[:space:]]*"//; s/"$//')
fi

# (b) linked worktree に checkout されている branch。porcelain 出力の最初の block は
# main worktree 自身なので除外する (= main の checkout branch は lane ではない)。
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
  if is_lane_branch "$tok"; then
    BRANCH="$tok"
    break
  fi
done

# merge 対象が並列 lane の branch でない → 根拠不在 → fail-open。
[ -z "$BRANCH" ] && exit 0

REVIEW="$TOP/docs/sprint/reviews/$(printf '%s' "$BRANCH" | tr '/' '_').md"

if [ -s "$REVIEW" ]; then
  if grep -qiE '^[[:space:]]*verdict:[[:space:]]*approve' "$REVIEW"; then
    # ADR 0005 guard 1: agent 判定の approve は実検証を代替しない。approve はレビューが
    # 起きた証明であって「テストが通った」証明ではない。関所が自分で検出スイートを回し、
    # fail なら block する (= verdict 行という自由文を信じない。信号は実テストの実行結果)。
    # merge は PreToolUse なので統合"後"の結合状態は測れない (タイミングの限界) が、統合先が
    # 緑であることは保証する — これは agent の approve 単独では担保されない。
    # runner 未検出は fail-open (commit gate と同じ。レビュー記録自体は既に precondition を満たす)。
    # 検出は commit gate と共有エンジン (lib/detect-test-suite.sh) で drift を防ぐ。
    # shellcheck source=lib/detect-test-suite.sh
    . "$(dirname "$0")/lib/detect-test-suite.sh"
    if SUITE="$(cd "$TOP" && detect_test_command)"; then
      echo "project-bootstrap: running $SUITE to verify before merge of \"$BRANCH\" (ADR 0005 guard 1)..." >&2
      if ! ( cd "$TOP" && $SUITE ) >&2; then
        cat >&2 <<EOF
project-bootstrap: blocking merge of "$BRANCH" — the test suite fails (ADR 0005 guard 1).

レビュー記録は verdict: approve だが、関所が実行した実テストスイート ($SUITE) が fail した。
AI レビューの approve は「レビューが起きた」証明であって実検証ではない — 落ちるスイートを
agent の approve で踏み越えて統合することは許可しない。対処:
  1. lane でテストを緑にしてから re-review し、verdict を更新する
  2. 統合境界 (共有 interface の前提ずれ) が原因なら、その根本を直す (症状を隠さない)
EOF
        exit 2
      fi
    fi
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

並列 lane の branch (sprint task branch / worktree lane) を、AI レビューの記録なしに
統合しようとした。統合の前提条件 (integrate skill Step 2):
  1. read-only の adversarial レビュー agent でこの branch の diff を審査する
  2. 結果を $REVIEW に書く — 必須行: "verdict: approve" または "verdict: reject" + 指摘一覧
  3. approve なら merge は通る。reject なら worker lane で修正してから re-review

レビューそのものを skip したい例外時は /permissions で本 hook を一時 deny にする。
EOF
exit 2

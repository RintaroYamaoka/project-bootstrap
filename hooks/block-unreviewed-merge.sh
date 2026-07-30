#!/usr/bin/env bash
# Hook M — PreToolUse on Bash for `git merge`
# AI レビューを統合の precondition として fail-closed に強制する gate (trust ladder の Stage 2)。
#
# 背景: 並列フローの throughput 天井は「人間が全 diff を直列レビューする」ことに在る
# (sprint-plan/SKILL.md が明文化)。Stage 2 では一次レビューを read-only の adversarial AI
# レビュー (integrate skill Step 2) に移し、人間は verdict + 指摘 + サンプル + 統合境界だけを
# 読む。だが「レビューを済ませた」を advisory にすると忘れられる — 本 hook は TDD hook が
# test の存在を強制するのと同型に、**統合行為 (= 並列 lane の branch の git merge)** を信号
# として、レビュー記録 (docs/bootstrap/sprint/reviews/<branch>.md, `/`→`_`) の存在と verdict を
# precondition 化する。「良いレビュー」は強制できないが「レビューの存在と結論」は強制できる。
#
# 「並列 lane の branch」は 2 つの集合の和 (ADR 0004):
#   (a) 活性 board の task branch (= sprint flow の正式 lane)
#   (b) この repo の linked worktree に checkout されている branch (= Workflow サブエージェント
#       の隔離 worktree / 手動 worktree 並走)。実際の並列開発は board を作らない形でも起きており
#       (docs/bootstrap/incidents/2026-06-11-parallel-mode-gate-coverage)、関所が「どの方式で作ったか」に
#       依存すると方式の選択 (= モデルの気分) で gate が無音になる。worktree という物理的痕跡を
#       信号にすれば、どの方式でも統合の入口で必ず捕まる。
#
# fail-mode (memory feedback_gate_signal_and_failmode 準拠):
#   - コマンド解析不能 = fail-closed (parse-command の契約。bypass 防止)
#   - 根拠不在 = fail-open: 非 merge コマンド / 非 git / docs/bootstrap/sprint 未採用 (= opt-in、他 gate
#     と同じ採用宣言) / merge 対象が (a)(b) のどちらでもない (通常の merge を一切妨げない)。
#     board の活性判定は lib/board-liveness.sh (存在ではなく活性 — 2026-06-07 incident)
#   - verdict: reject の記録がある merge は**より強く** block (却下の踏み越えを許さない)
#
# ── 統合の "ずれ" を捕まえる 2 つの追加 (LANE MG) ─────────────────────────────────
# レビュー記録 + 実スイートを通った lane でも、**統合先に対して古い base** の lane は
# 別クラスの事故を起こす。本 hook の signal (= 並列 lane の git merge) は同じだが、verdict
# とは独立に、統合の "ずれ" を 2 つ見る:
#
#   D6 (load-bearing fix・fail-CLOSED). incident 2026-06-25: 統合先より 17 commit 遅れた
#       lane の staged 編集が、すでに merge 済みの fix を**静かに revert**した。git diff/status
#       は HEAD 相手であって main 相手ではないため、巻き戻しが不可視のまま review+suite を
#       素通りした。PreToolUse 時点の merge 先は「いま checkout している HEAD (= merge INTO
#       する branch)」。各 lane target L について「統合先が L に含まれる」=
#       `git merge-base --is-ancestor HEAD <L>` を precondition にする。FALSE なら L は統合先に
#       既にある commit を欠く = 古い base = exit 2 で「先に L を統合先/main に rebase せよ」と
#       指示し、merge-base 起点の乖離 (`git rev-list --left-right --count HEAD...<L>`) を見せる。
#       rebase は機械的作業であって判断ではないので強制してよい。比較 ref は実際の merge 先
#       (HEAD) を優先し、HEAD が detached/trunk でない時のみ drift_main_ref を補助に使う。
#       signal = ancestor 関係 (verdict という自由文ではない)。fail-OPEN: 非 lane merge /
#       target が解決不能 / 非 work tree / ancestor 関係を計算できない (= 決して false-block
#       しない)。offline only (fetch しない)。stale な local ref による過少報告は gate を
#       黙らせるだけで、false-alarm は起こさない (drift lib と同じ under-report=安全の原則)。
#
#   D5 (advisory・決して exit 2 しない). 同じ統合の瞬間 (= 撤去マインドに入っている今) に、
#       merge 済みなのに残っている lane worktree があれば、撤去 (git worktree remove <path>) を
#       促す LOUD advisory を stderr に出す。だが block はしない: 残った worktree は未コミットを
#       抱えている可能性があり、撤去を強制するのは cry-wolf 失敗 (2026-05-29 記録)。leftover が
#       無ければ沈黙 (advisory bloat を作らない)。判定は lib/repo-drift.sh を READ-ONLY で再利用。
#
# bypass: 例外的に必要なら /permissions で本 hook を一時 deny。

set -u

# ── 小さく source 可能な D6/D5 ヘルパ ───────────────────────────────────────────
# 本 hook の本体 (cat / lib source / 判定) は実行時のみ走らせ (末尾の BUM_SOURCE_ONLY guard)、
# 以下の関数だけは source して real temp git repo に対して直接 unit-test できるようにする。
# いずれも `git -C <dir>` で動き $0 や cwd に依存しない (= test から source しても壊れない)。

# d6_lane_contains_dest <dir> <dest-ref> <lane-ref>
#   return 0 (= contains, pass) when the merge destination <dest-ref> is an ANCESTOR of the
#   lane tip <lane-ref> — i.e. the lane already carries everything on the destination, so it
#   is fresh-based and safe to merge. return 1 (= STALE, block) only when both refs resolve
#   AND the destination is provably NOT contained. fail-OPEN (return 0) whenever the relation
#   cannot be computed: a ref does not resolve, or merge-base errors — never false-block.
d6_lane_contains_dest() {
  local dir="$1" dest="$2" lane="$3" dsha lsha
  dsha=$(git -C "$dir" rev-parse --verify --quiet "$dest^{commit}" 2>/dev/null) || return 0
  lsha=$(git -C "$dir" rev-parse --verify --quiet "$lane^{commit}" 2>/dev/null) || return 0
  [ -n "$dsha" ] && [ -n "$lsha" ] || return 0
  # is-ancestor exits 0 (ancestor) / 1 (not) / other (error). Only a clean "1" means stale;
  # any error class is fail-open so an unresolvable history never false-blocks.
  git -C "$dir" merge-base --is-ancestor "$dsha" "$lsha" 2>/dev/null && return 0
  case $? in
    1) return 1 ;;   # definitively not an ancestor → stale base
    *) return 0 ;;   # could not compute → fail-open
  esac
}

# d6_divergence_count <dir> <dest-ref> <lane-ref>
#   echo "<dest-only>\t<lane-only>" framed against the merge-base (git rev-list --left-right
#   --count <dest>...<lane>): commits on the destination the lane lacks, then commits unique
#   to the lane. echoes nothing on error (caller treats absence as "no number to show").
d6_divergence_count() {
  local dir="$1" dest="$2" lane="$3"
  git -C "$dir" rev-list --left-right --count "$dest...$lane" 2>/dev/null
}

# When sourced for unit-testing the helpers above, stop here: do NOT run the hook body
# (which would `cat` stdin and resolve libs via $0). Real hook invocations leave the var
# unset, so this short-circuits and the body below executes as before.
[ -n "${BUM_SOURCE_ONLY:-}" ] && return 0

INPUT=$(cat)
# shellcheck source=lib/parse-command.sh
. "$(dirname "$0")/lib/parse-command.sh"
if ! CMD="$(printf '%s' "$INPUT" | parse_command)"; then
  echo "project-bootstrap: could not parse the tool command from hook input — blocking to fail safe (fail-closed). If this is a false positive, disable this hook via /permissions." >&2
  exit 2
fi

[ -z "$CMD" ] && exit 0

# git merge でなければ素通し (path-prefixed git も含め共有エンジンで判定)。
# shellcheck source=lib/merge-targets.sh
. "$(dirname "$0")/lib/merge-targets.sh"
cmd_has_git_merge "$CMD" || exit 0

# repo root を解決。非 git は根拠不在 → fail-open。
command -v git >/dev/null 2>&1 || exit 0
TOP=$(git rev-parse --show-toplevel 2>/dev/null | tr '\\' '/' | tr -s '/')
[ -z "$TOP" ] && exit 0

# opt-in: sprint flow を採用した project (= sprint ディレクトリが在る) でのみ発火。
# `docs/bootstrap/sprint` (新) / `docs/sprint` (旧) どちらでも可 (ADR 0020)。
# shellcheck source=lib/resolve-docs.sh
. "$(dirname "$0")/lib/resolve-docs.sh"
SPRINT_DIR="$(resolve_docs_dir "$TOP" sprint)"
[ -d "$SPRINT_DIR" ] || exit 0

# 並列 lane の branch 集合 (活性 board の task branch ∪ linked worktree の branch、ADR 0004)
# は単一権威 lib/lane-set.sh で組み立てる (= verification gate と drift しない)。
# shellcheck source=lib/lane-set.sh
. "$(dirname "$0")/lib/lane-set.sh"
LANE_BRANCHES=$(lane_branches "$TOP")

# lane が 1 つも無ければ判定根拠なし → fail-open (通常の merge を一切妨げない)。
[ -z "$(printf '%s' "$LANE_BRANCHES" | tr -d '[:space:]')" ] && exit 0

# ここから先は「並列 lane の git merge」= 統合の入口。D6/D5 の比較基準を組み立てる。
# 共有判定 lib/repo-drift.sh を READ-ONLY で source (drift_main_ref / merged_worktree_lines)。
# shellcheck source=lib/repo-drift.sh
. "$(dirname "$0")/lib/repo-drift.sh"

# DEST_REF — D6 が「lane が含んでいるべき統合先」。merge は HEAD に INTO するので実際の
# 統合先は HEAD。ただし HEAD が detached / trunk でない時だけ drift_main_ref を補助に使う
# (= ずれの基準を「いるべき場所」に寄せる)。drift_main_ref は local ref のみ (offline)。
DEST_REF=HEAD
CUR_BRANCH=$(git -C "$TOP" rev-parse --abbrev-ref HEAD 2>/dev/null)
MAIN_REF=$(drift_main_ref "$TOP" 2>/dev/null || true)
if [ -n "$MAIN_REF" ]; then
  MAIN_BRANCH=${MAIN_REF#*/}
  # HEAD が detached ("HEAD") か、trunk 以外の branch に居る時のみ remote-tracking ref を採用。
  if [ "$CUR_BRANCH" = HEAD ] || { [ -n "$CUR_BRANCH" ] && [ "$CUR_BRANCH" != "$MAIN_BRANCH" ]; }; then
    DEST_REF=$MAIN_REF
  fi
fi

# D5 (advisory・NEVER block): 撤去マインドに入っている統合の瞬間に、merge 済みなのに残って
# いる lane worktree があれば撤去を促す。leftover が無ければ沈黙 (advisory bloat 回避)。
# 残置 worktree は未コミットを抱えうるので削除は強制しない (cry-wolf — 2026-05-29 incident)。
if [ -n "$MAIN_REF" ]; then
  D5_LEFTOVERS=$(merged_worktree_lines "$TOP" "$MAIN_REF" 2>/dev/null || true)
  if [ -n "$D5_LEFTOVERS" ]; then
    cat >&2 <<EOF
project-bootstrap: 統合の前に — merge 済みなのに残っている lane worktree があります
(integrate skill は merge の後に worktree を撤去する。いま撤去マインドなら片付け時です):
$D5_LEFTOVERS  撤去: git worktree remove <path> (未コミットが無いか確認してから)。
これは助言であって block ではない — 残置を理由に merge は止めません。
EOF
  fi
fi

is_lane_branch() { lane_set_contains "$1" "$LANE_BRANCHES"; }

# merge 対象 branch を全 segment から enumerate する (複合コマンド対応)。共有エンジン
# lib/merge-targets.sh が貪欲 sed バグ + path-prefixed git を吸収する (単一権威で drift 防止)。
# 各 lane branch を分類: 1 つでも reject / 未レビューがあれば即 block (その branch の理由を出す)。
# 全 lane branch が approve なら、ADR 0005 guard 1 として実スイートを 1 回だけ回す。
HAS_LANE=0
NEEDS_SUITE=0
while IFS= read -r BRANCH; do
  [ -z "$BRANCH" ] && continue
  is_lane_branch "$BRANCH" || continue
  HAS_LANE=1

  # D6 precondition (fail-CLOSED): block a STALE-based lane BEFORE the approve/test path can
  # let it through. An approved+tested lane that does not contain the destination tip can
  # silently revert already-merged fixes (incident 2026-06-25) — verdict is no defense here.
  # fail-OPEN (no block) when the ancestor relation cannot be computed (unresolvable target).
  if ! d6_lane_contains_dest "$TOP" "$DEST_REF" "$BRANCH"; then
    DIV=$(d6_divergence_count "$TOP" "$DEST_REF" "$BRANCH")
    cat >&2 <<EOF
project-bootstrap: blocking merge of "$BRANCH" — stale base (D6, fail-closed).

統合先 ($DEST_REF) にある commit を lane "$BRANCH" が欠いています = 古い base のまま統合
しようとしました。古い base の lane の staged 編集は、すでに merge 済みの fix を**静かに
revert**しえます (git diff/status は HEAD 相手なので不可視 — incident 2026-06-25)。
乖離 (merge-base 起点 / git rev-list --left-right --count $DEST_REF...$BRANCH):
  ${DIV:-<計算不能>}   (左 = 統合先のみ / 右 = lane のみ)
対処 (rebase は機械的作業であって判断ではない — まず先に直す):
  git -C <lane worktree> rebase $DEST_REF      # lane を統合先/main の上に載せ直す
  その後 re-review し直して (diff が変わる) から統合する
EOF
    exit 2
  fi

  REVIEW="$SPRINT_DIR/reviews/$(printf '%s' "$BRANCH" | tr '/' '_').md"

  if [ -s "$REVIEW" ] && grep -qiE '^[[:space:]]*verdict:[[:space:]]*approve' "$REVIEW"; then
    NEEDS_SUITE=1
    continue
  fi
  if [ -s "$REVIEW" ] && grep -qiE '^[[:space:]]*verdict:[[:space:]]*reject' "$REVIEW"; then
    cat >&2 <<EOF
project-bootstrap: blocking merge of "$BRANCH" — review verdict is REJECT.

レビュー記録 ($REVIEW) が verdict: reject を持つ branch を merge しようとした。
却下されたレビューを踏み越える統合は許可しない。対処:
  1. 指摘を worker lane で修正し、re-review を回して verdict: approve に更新する
  2. 指摘が誤りなら、レビュー記録に反証を追記した上で verdict を更新する (記録を消さない)
EOF
    exit 2
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
done < <(merge_target_branches "$CMD")

# merge 対象に並列 lane の branch が無い → 根拠不在 → fail-open (通常の merge を一切妨げない)。
[ "$HAS_LANE" = 0 ] && exit 0

# 全 lane branch が approve だった。ADR 0005 guard 1: agent 判定の approve は実検証を代替しない。
# approve はレビューが起きた証明であって「テストが通った」証明ではない。関所が自分で検出スイートを
# 回し、fail なら block する (= verdict 行という自由文を信じない。信号は実テストの実行結果)。merge は
# PreToolUse なので統合"後"の結合状態は測れない (タイミングの限界) が、統合先が緑であることは保証する。
# runner 未検出は fail-open。検出は commit gate と共有エンジン (lib/detect-test-suite.sh) で drift 防止。
if [ "$NEEDS_SUITE" = 1 ]; then
  # shellcheck source=lib/detect-test-suite.sh
  . "$(dirname "$0")/lib/detect-test-suite.sh"
  if SUITE="$(cd "$TOP" && detect_test_command)"; then
    echo "project-bootstrap: running $SUITE to verify before merge (ADR 0005 guard 1)..." >&2
    if ! ( cd "$TOP" && $SUITE ) >&2; then
      cat >&2 <<EOF
project-bootstrap: blocking merge — the test suite fails (ADR 0005 guard 1).

レビュー記録は verdict: approve だが、関所が実行した実テストスイート ($SUITE) が fail した。
AI レビューの approve は「レビューが起きた」証明であって実検証ではない — 落ちるスイートを
agent の approve で踏み越えて統合することは許可しない。対処:
  1. lane でテストを緑にしてから re-review し、verdict を更新する
  2. 統合境界 (共有 interface の前提ずれ) が原因なら、その根本を直す (症状を隠さない)
EOF
      exit 2
    fi
  fi
fi
exit 0

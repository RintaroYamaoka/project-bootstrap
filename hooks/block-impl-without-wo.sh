#!/usr/bin/env bash
# Hook — PreToolUse on Edit|Write|MultiEdit. The gate at the moment IMPLEMENTATION starts.
#
# 何を強制するか: 新しい feature 面を作る前に、その面をカバーする **発注済み (status: ordered)
# の作業指示書 (WO)** が在ること。WO の完全性そのものは発注 commit の関所
# (block-commit-if-wo-incomplete.sh) が既に証明しているので、ここが見るのは「発注済みの契約に
# 覆われた作業か」だけ。2 つの関所で「完全性」と「被覆」を分担する。
#
# ②信号選び: 信号は sprint gate と同じく **新規 source file を作る行為そのもの**。prompt の
# 語彙は無限で構造的に穴が空く proxy なので使わない。
#
# sprint gate (block-unplanned-feature-build.sh) と信号は同じだが問いが違う:
#   sprint gate   「これは並列レーンに割れるか、判定したか?」
#   この gate     「これを作ってよいと発注した契約は在るか?」
# 別の判断なので別の関所にする。片方を通したことがもう片方の免除になってはいけない
# (= 1 つの記録が 2 つの判断の証拠を兼ねると、安い方だけ済ませて両方を名乗れる)。
#
# fail-mode (memory feedback_gate_signal_and_failmode に準拠):
#   - 根拠不在 = fail-open。file_path 不在 / 非 git / docs/bootstrap/commission 未採用 /
#     既存 file の編集 / test・config・doc / 非 source 拡張子 → 素通し。
#     **bug fix / refactor / 既存 file 編集は一切 trip しない。**
#   - commission 自身の state 面 (docs/bootstrap/commission/**) も素通し —
#     gate を解除する書き込みを gate 自身が止めてはならない。
#
# opt-in: docs/bootstrap/commission/ が在るときだけ発火。jq 非依存。

set -u

# shellcheck source=lib/parse-command.sh
. "${BASH_SOURCE[0]%/*}/lib/parse-command.sh"
# shellcheck source=lib/resolve-docs.sh
. "${BASH_SOURCE[0]%/*}/lib/resolve-docs.sh"
# shellcheck source=lib/source-face.sh
. "${BASH_SOURCE[0]%/*}/lib/source-face.sh"
# shellcheck source=lib/wo.sh
. "${BASH_SOURCE[0]%/*}/lib/wo.sh"
# shellcheck source=lib/repo-top.sh
. "${BASH_SOURCE[0]%/*}/lib/repo-top.sh"

# gate 本体 — 契約は lib/standalone.sh ヘッダ参照 (global FILE を読む / return 0=pass, 2=block)。
gate_block_impl_without_wo() {
  local TOP CDIR CREL FILE_NORM REL ORDERED wo REASON

repo_top_var
TOP="$REPO_TOP"
[ -z "$TOP" ] && return 0

CDIR="$(resolve_docs_dir "$TOP" commission)"
CREL="$(resolve_docs_label "$TOP" commission)"
[ -d "$CDIR" ] || return 0   # 未採用 → 素通し

norm_path_var "$FILE"
FILE_NORM="$NORM_PATH"
case "$FILE_NORM" in
  "$TOP"/*) REL="${FILE_NORM#"$TOP"/}" ;;
  /*|[A-Za-z]:/*) return 0 ;;   # worktree 外の絶対 path は判断不能 → fail-open
  *) REL="$FILE_NORM" ;;
esac

# このサブシステム自身の成果物への書き込みは決して止めない (両レイアウトを見る)。
docs_state_face "$REL" commission && return 0

# 既存 file の編集/上書きは「新規 feature 面の作成」ではない → fail-open。
[ -e "$TOP/$REL" ] && return 0

# test / config / docs / 非 source 拡張子は feature 面ではない。判定は共有エンジン
# (sprint gate・guard 2 と「source 面とは何か」を単一権威に保つ)。
is_source_path "$REL" || return 0

ORDERED=0
for wo in "$CDIR"/wo/*.md; do
  [ -f "$wo" ] || continue
  case "$wo" in */TEMPLATE.md) continue ;; esac
  [ "$(wo_frontmatter "$wo" status)" = "ordered" ] || continue
  ORDERED=$((ORDERED + 1))
  if wo_covers_path "$wo" "$REL"; then
    return 0
  fi
done

if [ "$ORDERED" = 0 ]; then
  REASON="発注済み (status: ordered) の WO が 1 つも無い。"
else
  REASON="発注済みの WO は $ORDERED 件あるが、どれも 2 節 (作業範囲) でこの path をカバーしていない。"
fi

cat >&2 <<EOF
project-bootstrap: blocking creation of new source file "$REL" — 発注された作業指示書が無い。

$REASON

$CREL/ が在る = commission (上流工程) を採用した project。新しい feature 面は、
それを作ってよいと決めた契約 (WO) の下でしか作らない。契約が無いまま実装を始めると、
仕様の穴に当たった AI は質問せず「もっともらしい解釈」で埋め、その手戻りが下流の
トークンとして返ってくる。

進め方:
  1. order skill をロードして $CREL/wo/<id>-<slug>.md をドラフトする
     (2 節にこの path を含む glob を書く)
  2. pre-review skill で仮想下流リーダーに仕様を壊させ、指摘を全部決着させる
  3. frontmatter を status: ordered にして commit する
     (このとき完全性を block-commit-if-wo-incomplete.sh が検証する)

既存 file の修正・bug fix・refactor はこの gate の対象外。既に発注済みの作業なのに
2 節の glob が狭すぎるだけなら、WO の 2 節を直して発注し直す
(= 範囲の拡大は契約の変更なので、黙って広げず記録に残す)。
EOF
return 2
}

# 単体起動 (tests / vendoring 消費者) — dispatcher からは source されるので走らない。
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  # shellcheck source=lib/standalone.sh
  . "${BASH_SOURCE[0]%/*}/lib/standalone.sh"
  bootstrap_standalone_edit_gate gate_block_impl_without_wo
fi

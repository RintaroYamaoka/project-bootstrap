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

INPUT=$(cat)

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/parse-command.sh
. "$DIR/lib/parse-command.sh"
FILE=$(printf '%s' "$INPUT" | parse_json_string_field file_path)
if [ -z "$FILE" ]; then
  FILE=$(printf '%s' "$INPUT" | parse_json_string_field path)
fi
[ -z "$FILE" ] && exit 0   # 根拠不在 → fail-open

command -v git >/dev/null 2>&1 || exit 0
TOP=$(git rev-parse --show-toplevel 2>/dev/null | tr '\\' '/' | tr -s '/')
[ -z "$TOP" ] && exit 0

# shellcheck source=lib/resolve-docs.sh
. "$DIR/lib/resolve-docs.sh"
CDIR="$(resolve_docs_dir "$TOP" commission)"
CREL="$(resolve_docs_label "$TOP" commission)"
[ -d "$CDIR" ] || exit 0   # 未採用 → 素通し

FILE_NORM=$(printf '%s' "$FILE" | tr '\\' '/' | tr -s '/')
case "$FILE_NORM" in
  "$TOP"/*) REL="${FILE_NORM#"$TOP"/}" ;;
  /*|[A-Za-z]:/*) exit 0 ;;   # worktree 外の絶対 path は判断不能 → fail-open
  *) REL="$FILE_NORM" ;;
esac

# このサブシステム自身の成果物への書き込みは決して止めない (両レイアウトを見る)。
docs_state_face "$REL" commission && exit 0

# 既存 file の編集/上書きは「新規 feature 面の作成」ではない → fail-open。
[ -e "$TOP/$REL" ] && exit 0

# test / config / docs / 非 source 拡張子は feature 面ではない。判定は共有エンジン
# (sprint gate・guard 2 と「source 面とは何か」を単一権威に保つ)。
# shellcheck source=lib/source-face.sh
. "$DIR/lib/source-face.sh"
is_source_path "$REL" || exit 0

# shellcheck source=lib/wo.sh
. "$DIR/lib/wo.sh"

ORDERED=0
for wo in "$CDIR"/wo/*.md; do
  [ -f "$wo" ] || continue
  case "$wo" in */TEMPLATE.md) continue ;; esac
  [ "$(wo_frontmatter "$wo" status)" = "ordered" ] || continue
  ORDERED=$((ORDERED + 1))
  if wo_covers_path "$wo" "$REL"; then
    exit 0
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
exit 2

#!/usr/bin/env bash
# Hook G — PreToolUse on Edit|Write|MultiEdit
# 並列開発 (sprint) の lane 強制。各ワーカーは自分の git worktree で作業し、worktree root の
# `.bootstrap-lane` (1 行 1 glob) が「触ってよい file」を宣言する。宣言外の file を編集しようと
# したら exit 2。これで「1 task = 1 owner = 1 worktree」を決定論的な境界にする。
#
# `.bootstrap-lane` が無ければ fail-open (= sprint を使っていない通常作業は一切妨げない)。
# jq 非依存 (= 多くの環境に jq が無いため)。
#
# board.json (= sprint の rich な真実) は lead / skill が読み書きする。hook が読むのは
# worktree-local な .bootstrap-lane だけ (= cwd で完結、cross-worktree 解決も jq も不要)。

set -u

INPUT=$(cat)

FILE=$(printf '%s' "$INPUT" | grep -oE '"file_path"[^,}]*' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//; s/"[[:space:]]*$//')
if [ -z "$FILE" ]; then
  FILE=$(printf '%s' "$INPUT" | grep -oE '"path"[^,}]*' | head -1 | sed 's/.*"path"[[:space:]]*:[[:space:]]*"//; s/"[[:space:]]*$//')
fi
[ -z "$FILE" ] && exit 0

# git worktree root を解決。repo 外 / git 不在なら fail-open。
command -v git >/dev/null 2>&1 || exit 0
TOP=$(git rev-parse --show-toplevel 2>/dev/null | tr '\\\\' '/' | tr -s '/')
[ -z "$TOP" ] && exit 0

# lane marker は `.bootstrap/lane` (新) / `.bootstrap-lane` (旧) どちらでも可。
# shellcheck source=lib/resolve-marker.sh
. "$(dirname "$0")/lib/resolve-marker.sh"
LANE="$(resolve_marker "$TOP" lane)"
# lane 宣言が無ければ sprint 非適用 → 素通し
[ -f "$LANE" ] || exit 0

# lane 照合は共有エンジンに委ねる (commit 関所と単一権威。drift 防止)。
# shellcheck source=lib/lane-match.sh
. "$(dirname "$0")/lib/lane-match.sh"

# 編集対象を repo 相対 path に正規化
FILE_NORM=$(printf '%s' "$FILE" | tr '\\\\' '/' | tr -s '/')
case "$FILE_NORM" in
  "$TOP"/*) REL="${FILE_NORM#"$TOP"/}" ;;
  /*|[A-Za-z]:/*)
    # worktree 外の絶対 path。**同一 repo の別 worktree の中**なら「lane 外」と確定できるので
    # block する (= 解析できて違反と分かる → fail-closed)。lane worker がメインリポの file を
    # 絶対 path で直接書く事故がここを素通りしていた (marketing-app 2026-07-09 incident M5)。
    # どの worktree にも属さない path (= /tmp scratchpad, ~/.claude 等) は判断材料が無いので
    # 従来どおり fail-open (= 根拠不在 → fail-open)。
    if OTHER="$(lane_owning_worktree "$FILE_NORM" "$TOP")"; then
      cat >&2 <<EOF
project-bootstrap: blocking edit on "$FILE_NORM" — 別 worktree の file を lane の外から編集しようとした。

このワーカーの worktree : $TOP
編集先が属する worktree : $OTHER

lane の不変条件は「自分の worktree の外を触らない」。別 worktree (典型的にはメインリポ) の file を
直接書くと、その tree を所有する lead / 別ワーカーの作業と無音で衝突する。対処:
  1. その file が別 task の責務なら触らない。その lane のワーカーに任せる
  2. 本 task の正当な scope なら、その file を**自分の worktree の中で**編集する
     (= 同じ path が自分の tree にも在る。絶対 path でなく相対 path で開く)
  3. メインリポ側の独立した debt (lint 落ち等) が commit を阻んでいるなら、それは lane の外の
     問題。lane を出て直すのでなく lead に上げる
EOF
      exit 2
    fi
    exit 0
    ;;
  *) REL="$FILE_NORM" ;;       # 既に相対ならそのまま
esac

lane_allows "$REL" "$LANE" && exit 0

LANES=$(grep -vE '^[[:space:]]*(#|$)' "$LANE" | sed 's/^/  - /')
cat >&2 <<EOF
project-bootstrap: blocking edit on "$REL" — outside this worktree's lane.

このワーカーが所有する lane (= $LANE):
$LANES

"$REL" はどの lane glob にも一致しない。考えられる原因:
  1. 別 task の scope を侵している (= 別ワーカーの担当 file)
  2. task 分解時の scope 漏れ (= この file も本 task の責務なら .bootstrap-lane に追記)
  3. 共有すべき interface/型を触ろうとしている (= それは直列 spine task に切り出す)

対処:
  - 別 task の file なら触らない。その task のワーカー / 別 worktree に任せる
  - 本 task の正当な scope なら .bootstrap-lane に glob を 1 行追記し、board.json の scope も同期
  - 共有依存なら lead に直列 spine task 化を相談 (= 並列の前に先行で済ませる)
EOF
exit 2

#!/usr/bin/env bash
# Hook I — PreToolUse on Edit|Write|MultiEdit
# mutation lane の worktree 隔離を強制する (ADR 0005 guard 2)。
#
# 背景: 並列開発では各 lane は隔離 worktree で mutate する (ADR 0004/0005)。だが
# block-out-of-lane-edit.sh は `.bootstrap-lane` を持つ worktree (= lane) の中でしか効かず、
# 共有 main worktree で source を mutate する行為は素通しだった — Workflow / subagent が
# 隔離 worktree を使わず shared tree で書く collision (= worktree 隔離が防ぐはずの事故) に穴。
# 本 hook はそれを塞ぐ。
#
# 信号の精密さ (誤検知 > false negative — ADR 0004)。全条件が揃ったときだけ block:
#   (a) docs/sprint 採用 (opt-in)
#   (b) main worktree に居る (lane worktree は block-out-of-lane が所有 → 譲る)
#   (c) active な linked worktree lane が在る (= 並列 mutation が物理的に存在)
#   (d) 統合操作中でない (MERGE_HEAD / rebase / cherry-pick / revert — lead の conflict 解決は通す)
#   (e) 編集対象が source 面 (docs/config/test/sprint state は通す。source-face.sh で判定)
# どれか曖昧なら fail-open。jq 非依存。

set -u

INPUT=$(cat)

FILE=$(printf '%s' "$INPUT" | grep -oE '"file_path"[^,}]*' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//; s/"[[:space:]]*$//')
if [ -z "$FILE" ]; then
  FILE=$(printf '%s' "$INPUT" | grep -oE '"path"[^,}]*' | head -1 | sed 's/.*"path"[[:space:]]*:[[:space:]]*"//; s/"[[:space:]]*$//')
fi
[ -z "$FILE" ] && exit 0   # 根拠不在 → fail-open

# git worktree root を解決。repo 外 / git 不在なら fail-open。
command -v git >/dev/null 2>&1 || exit 0
TOP=$(git rev-parse --show-toplevel 2>/dev/null | tr '\\' '/' | tr -s '/')
[ -z "$TOP" ] && exit 0

# (a) opt-in: sprint flow を採用した project でのみ発火。
[ -d "$TOP/docs/sprint" ] || exit 0

# (b) lane worktree (`.bootstrap-lane` 在り) は block-out-of-lane-edit が所有 → 譲る。
[ -f "$TOP/.bootstrap-lane" ] && exit 0
# main worktree でのみ強制する。linked worktree が lane file を欠く異常配置はこの gate の対象外。
# porcelain の最初の `worktree` 行 = main worktree。
MAIN=$(git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | head -1 | tr '\\' '/' | tr -s '/')
[ -n "$MAIN" ] && [ "$TOP" != "$MAIN" ] && exit 0

# (c) active な linked worktree lane が在るか (= 全 worktree 数 > 1)。無ければ並列 mutation
#     の衝突相手が居ない → fail-open。
TOTAL=$(git worktree list --porcelain 2>/dev/null | grep -c '^worktree ')
[ "${TOTAL:-0}" -gt 1 ] 2>/dev/null || exit 0

# (d) 統合操作中 (lead が conflict を解決している) なら通す。
if git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 \
   || git rev-parse -q --verify CHERRY_PICK_HEAD >/dev/null 2>&1 \
   || git rev-parse -q --verify REVERT_HEAD >/dev/null 2>&1 \
   || [ -d "$(git rev-parse --git-path rebase-merge 2>/dev/null)" ] \
   || [ -d "$(git rev-parse --git-path rebase-apply 2>/dev/null)" ]; then
  exit 0
fi

# 編集対象を repo 相対 path に正規化。
FILE_NORM=$(printf '%s' "$FILE" | tr '\\' '/' | tr -s '/')
case "$FILE_NORM" in
  "$TOP"/*) REL="${FILE_NORM#"$TOP"/}" ;;
  /*|[A-Za-z]:/*) exit 0 ;;   # tree 外の絶対 path は判断不能 → fail-open
  *) REL="$FILE_NORM" ;;
esac

# sprint runtime state (board.json / reviews / .gate) の書き込みは決して止めない。
case "$REL" in
  docs/sprint/*|*/docs/sprint/*) exit 0 ;;
esac

# (e) source 面のみ対象。docs/config/test/非 source は fail-open。判定は block-unplanned と
#     共有エンジン (= 単一権威。drift 防止)。
# shellcheck source=lib/source-face.sh
. "$(dirname "$0")/lib/source-face.sh"
is_source_path "$REL" || exit 0

cat >&2 <<EOF
project-bootstrap: blocking edit on "$REL" — un-isolated mutation in the shared main worktree.

並列 lane が活性 (linked worktree が在る) の最中に、共有 main worktree で source 面を
mutate しようとした。隔離されていない並列編集は他 lane の作業と衝突する (= worktree 隔離が
防ぐ事故そのもの。ADR 0005 guard 2)。対処:
  1. この変更が或る lane の責務なら、その lane の worktree の中で行う (= isolation 維持)
  2. 新しい作業面なら新 lane を切る (sprint-plan: git worktree add → .bootstrap-lane)。
     ただし wip_limit を超えないこと (block-over-wip-parallel.sh)
  3. lane を統合している途中なら、conflict 解決は merge/rebase の最中に行う (= その間は通る)
  4. 開いている lane を先に全て integrate して閉じれば、main tree の編集は通常通り通る
EOF
exit 2

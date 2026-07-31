#!/usr/bin/env bash
# retired-check — 引退した名前の混入検査を行う独立 CLI (Claude 非依存)。
# CI (GitHub Actions) が呼び、`.bootstrap/retired` の契約を「全員が通る場所」で強制する
# (= PreToolUse hook は Claude が叩く commit にしか効かない。人が端末で直接 commit する経路と、
#  GitHub UI での PR merge には届かない。server 側が恒久層 = ADR 0012)。
#
# 使い方:
#   retired-check.sh <base>    <base> からの **追加行** を検査する。
#                              <base> はそのまま `git diff` に渡すので、ref (= 二点差分) でも
#                              `origin/main...HEAD` (= 三点 / merge-base 差分) でもよい。
#                              PR では必ず三点を使う — 二点だと base 側の進行分まで「追加行」に
#                              混ざり、他人が持ち込んだ残存で PR が赤くなる。
# exit:
#   0 = 違反なし (or marker 不在 / 有効行 0)
#   1 = 追加行に引退済みの名前あり (一覧を stderr に出力)
#   2 = 使用環境エラー (git 不在 / repo 外 / base 未指定)
#
# 判定エンジンは hooks/lib/retired-terms.sh を hook と共有する。CI が hook より厳しいと
# 「誰も持ち込んでいない残存」で全 PR が赤くなり、緩いと無音の穴になる — どちらも single
# authority でしか防げない。consumer repo へは本 CLI + lib を vendor するか、CI で本リポを
# 取得して呼ぶ。

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# engine + 依存 lib。vendor された場合は同階層も探す (arch-check.sh と同じ作法)。
ENGINE="$SCRIPT_DIR/../hooks/lib/retired-terms.sh"
[ -f "$ENGINE" ] || ENGINE="$SCRIPT_DIR/retired-terms-engine.sh"
[ -f "$ENGINE" ] || { echo "retired-check: engine (hooks/lib/retired-terms.sh) が見つからない" >&2; exit 2; }

RESOLVER="$SCRIPT_DIR/../hooks/lib/resolve-marker.sh"
[ -f "$RESOLVER" ] || RESOLVER="$SCRIPT_DIR/resolve-marker.sh"

BASE="${1:-}"
[ -z "$BASE" ] && { echo "retired-check: usage: retired-check.sh <base-ref|base...HEAD>" >&2; exit 2; }

command -v git >/dev/null 2>&1 || { echo "retired-check: git が必要" >&2; exit 2; }
TOP=$(git rev-parse --show-toplevel 2>/dev/null)
[ -z "$TOP" ] && { echo "retired-check: git repo 外" >&2; exit 2; }

if [ -f "$RESOLVER" ]; then
  # shellcheck source=../hooks/lib/resolve-marker.sh
  . "$RESOLVER"
  MARKER="$(resolve_marker "$TOP" retired)"
else
  MARKER="$TOP/.bootstrap-retired"
fi
[ -f "$MARKER" ] || exit 0   # 未採用 repo の CI を壊さない

# shellcheck source=../hooks/lib/retired-terms.sh
. "$ENGINE"
retired_load "$MARKER" || exit 0   # 宣言だけの no-op (doctor が別途可視化する)

VIOLATIONS="$(retired_added_lines_range "$BASE" | retired_scan_stream)" || exit 0
[ -n "$VIOLATIONS" ] || exit 0

{
  echo "retired-check: this branch ADDS lines that use a RETIRED name (${MARKER#"$TOP"/}):"
  echo
  printf '%s\n' "$VIOLATIONS" | while IFS='|' read -r rel term repl note line; do
    if [ -n "$repl" ]; then
      printf '  - %s: "%s" は引退済み → "%s" を使う\n' "$rel" "$term" "$repl"
    else
      printf '  - %s: "%s" は引退済み (置換先は未記入)\n' "$rel" "$term"
    fi
    [ -n "$note" ] && printf '      note: %s\n' "$note"
    printf '      + %s\n' "$line"
  done
  cat <<EOF

検査対象は **このブランチが新しく足した行だけ**。既存行に残っている同じ語は対象外なので、
この赤を消すために無関係な一括改名をしないこと。語そのものが引退していない / 射程が広すぎる
なら、${MARKER#"$TOP"/} の該当行を意図的に直す (3 列目の scope glob で射程を絞れる)。
EOF
} >&2
exit 1

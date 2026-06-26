#!/usr/bin/env bash
# arch-check — dependency-direction の独立 CLI (Claude 非依存)。
# CI (GitHub Actions) と git pre-commit hook が呼び、`.bootstrap-arch` 契約を
# 「全員が通る場所」で強制する (= PreToolUse hook は Claude のみ、こちらは誰でも)。
#
# 使い方:
#   arch-check.sh [file...]   引数の file を検査。引数なしなら staged file (git diff --cached) を検査。
# exit:
#   0 = 違反なし (or .bootstrap-arch 不在)
#   1 = 宣言 layer の file に依存方向違反あり (一覧を stderr に出力)
#   2 = 使用環境エラー (git 不在等)
#
# エンジンは hooks/lib/arch-check.sh を共有 (DRY)。consumer repo へは本 CLI + lib を
# vendor するか、CI で本リポを取得して呼ぶ。

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENGINE="$SCRIPT_DIR/../hooks/lib/arch-check.sh"
# vendor された場合は同階層も探す
[ -f "$ENGINE" ] || ENGINE="$SCRIPT_DIR/arch-check-engine.sh"
[ -f "$ENGINE" ] || { echo "arch-check: engine (hooks/lib/arch-check.sh) が見つからない" >&2; exit 2; }

# marker resolver (`.bootstrap/arch` 新 / `.bootstrap-arch` 旧)。engine と同階層に置かれる。
RESOLVER="$SCRIPT_DIR/../hooks/lib/resolve-marker.sh"
[ -f "$RESOLVER" ] || RESOLVER="$SCRIPT_DIR/resolve-marker.sh"

command -v git >/dev/null 2>&1 || { echo "arch-check: git が必要" >&2; exit 2; }
TOP=$(git rev-parse --show-toplevel 2>/dev/null)
[ -z "$TOP" ] && { echo "arch-check: git repo 外" >&2; exit 2; }

if [ -f "$RESOLVER" ]; then
  # shellcheck source=../hooks/lib/resolve-marker.sh
  . "$RESOLVER"
  MANIFEST="$(resolve_marker "$TOP" arch)"
else
  MANIFEST="$TOP/.bootstrap-arch"
fi
[ -f "$MANIFEST" ] || exit 0   # 契約が無ければ何もしない

# shellcheck source=../hooks/lib/arch-check.sh
. "$ENGINE"
arch_load_manifest "$MANIFEST" || exit 0

# 検査対象 file: 引数 or staged
if [ "$#" -gt 0 ]; then
  FILES=$(printf '%s\n' "$@")
else
  FILES=$(git diff --cached --name-only 2>/dev/null)
fi

VIOLATIONS=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  case "$f" in *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.py) ;; *) continue ;; esac
  [ -n "$(arch_layer_of "$f")" ] || continue
  [ -f "$TOP/$f" ] || continue
  out="$(arch_check_imports "$f" "${f##*.}" < "$TOP/$f")"
  [ -n "$out" ] && VIOLATIONS="${VIOLATIONS}${out}
"
done <<EOF
$FILES
EOF

[ -z "$(printf '%s' "$VIOLATIONS" | tr -d '[:space:]')" ] && exit 0

cat >&2 <<EOF
arch-check: dependency-direction violations (.bootstrap-arch):

$(printf '%s' "$VIOLATIONS" | sed '/^$/d; s/^/  - /')

依存方向の契約に反する import がある。import 側の責務を正しい layer に移すか、port で
依存を反転するか、契約 (.bootstrap-arch の allow 辺) を意図的に見直すこと。
EOF
exit 1

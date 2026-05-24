#!/usr/bin/env bash
# Hook H — PreToolUse on Bash for `git commit`
# commit 時の権威ゲート。`.bootstrap-arch` で宣言された layer 配下の全 file の import を
# 検証し、依存方向の違反があれば exit 2 で commit を blocking する。これで「どの commit も
# アーキテクチャ契約を満たす」ことを deterministic に保証する (= 散文の advisory ではなく gate)。
#
# `.bootstrap-arch` が無ければ fail-open (= 非アーキ project は一切影響しない)。
# ルールは project-local。本 hook は汎用で、project 固有のルールは一切持たない。

set -u

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | grep -oE '"command"[^,}]*' | head -1 | sed 's/.*"command"[[:space:]]*:[[:space:]]*"//; s/"[[:space:]]*$//')
[ -z "$CMD" ] && exit 0

# git commit でなければ素通し
echo "$CMD" | grep -qE '(^|[[:space:]&|;()`]+)git[[:space:]]+commit($|[[:space:]])' || exit 0

# git repo / manifest の解決
command -v git >/dev/null 2>&1 || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
TOP=$(git rev-parse --show-toplevel 2>/dev/null)
[ -z "$TOP" ] && exit 0
MANIFEST="$TOP/.bootstrap-arch"
[ -f "$MANIFEST" ] || exit 0   # fail-open

# shellcheck source=lib/arch-check.sh
. "$(dirname "$0")/lib/arch-check.sh"
arch_load_manifest "$MANIFEST" || exit 0

# 宣言 layer に属する tracked file を全部検証する
VIOLATIONS=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -n "$(arch_layer_of "$f")" ] || continue
  [ -f "$TOP/$f" ] || continue
  out="$(arch_check_imports "$f" "${f##*.}" < "$TOP/$f")"
  [ -n "$out" ] && VIOLATIONS="${VIOLATIONS}${out}
"
done < <(git ls-files)

[ -z "$(printf '%s' "$VIOLATIONS" | tr -d '[:space:]')" ] && exit 0

cat >&2 <<EOF
project-bootstrap: blocking commit — dependency-direction violations (.bootstrap-arch):

$(printf '%s' "$VIOLATIONS" | sed '/^$/d; s/^/  - /')

依存方向の契約に反する import がある。対処:
  - import 側の責務が間違っている        → 正しい layer に処理を移す
  - 依存が本来許されるべき               → .bootstrap-arch の allow 辺を見直す (= 契約変更は意図的に)
  - 共通の型/interface を跨いで使いたい  → port (= 内側の層が公開する interface) 経由にして依存を反転する

契約そのものを変えたいなら .bootstrap-arch を編集する。例外的に通すだけなら /permissions で本 hook を一時 deny。
EOF
exit 2

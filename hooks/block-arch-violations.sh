#!/usr/bin/env bash
# Hook H — PreToolUse on Bash for `git commit`
# commit 時のゲート。`.bootstrap-arch` で宣言された依存方向に反する import を `staged file` の
# 中から検出し、あれば exit 2 で commit を blocking する (= 散文の advisory ではなく gate)。
# staged のみ検査するので、既存 debt のあるリポでも adopt でき、新規/変更分の違反だけ捕まえる
# (全 repo 網羅 scan は CI の領分)。edit 時の早期 gate は block-cross-layer-import.sh。
#
# `.bootstrap-arch` が無ければ fail-open (= 非アーキ project は一切影響しない)。
# ルールは project-local。本 hook は汎用で、project 固有のルールは一切持たない。

set -u

INPUT=$(cat)
# shellcheck source=lib/parse-command.sh
. "$(dirname "$0")/lib/parse-command.sh"
if ! CMD="$(printf '%s' "$INPUT" | parse_command)"; then
  echo "project-bootstrap: could not parse the tool command from hook input — blocking to fail safe (fail-closed). If this is a false positive, disable this hook via /permissions." >&2
  exit 2
fi
[ -z "$CMD" ] && exit 0

# git commit でなければ素通し
echo "$CMD" | grep -qE '(^|[[:space:]&|;()`]+)git[[:space:]]+commit($|[[:space:]])' || exit 0

# git repo / manifest の解決
command -v git >/dev/null 2>&1 || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
TOP=$(git rev-parse --show-toplevel 2>/dev/null)
[ -z "$TOP" ] && exit 0
# arch manifest は `.bootstrap/arch` (新) / `.bootstrap-arch` (旧) どちらでも可。
# shellcheck source=lib/resolve-marker.sh
. "$(dirname "$0")/lib/resolve-marker.sh"
MANIFEST="$(resolve_marker "$TOP" arch)"
[ -f "$MANIFEST" ] || exit 0   # fail-open

# shellcheck source=lib/arch-check.sh
. "$(dirname "$0")/lib/arch-check.sh"
arch_load_manifest "$MANIFEST" || exit 0

# この commit で staged な file だけ検証する (= 正しい pre-commit セマンティクス)。
# 全 tracked を scan すると既存 debt のあるリポで無関係な commit まで全ブロックされ adopt 不能。
# staged-only なら「触ったものだけ gate」になり、既存 debt は止めず新規違反だけ捕まえる
# (全 repo の網羅 scan は CI の領分)。
VIOLATIONS=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -n "$(arch_layer_of "$f")" ] || continue
  [ -f "$TOP/$f" ] || continue
  out="$(arch_check_imports "$f" "${f##*.}" < "$TOP/$f")"
  [ -n "$out" ] && VIOLATIONS="${VIOLATIONS}${out}
"
done < <(git diff --cached --name-only)

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

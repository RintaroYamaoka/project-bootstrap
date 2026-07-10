#!/usr/bin/env bash
# Hook I — PreToolUse on Edit|Write|MultiEdit
# 依存方向の早期ゲート。編集が `.bootstrap-arch` の依存方向に反する import を導入しようと
# した瞬間に exit 2 で blocking する (= 書いた瞬間に止めて手戻りを防ぐ)。commit 時の
# block-arch-violations.sh が全 file の権威網で、これはその場フィードバック版。
#
# PreToolUse なので新内容はまだ disk に無い。hook input JSON を unescape して
# 新内容 (new_string / content) 中の import specifier を抽出し検査する。
# manifest 不在 / layer 外 file は fail-open。

set -u

INPUT=$(cat)

# field 抽出は単一権威 lib/parse-command.sh の decoder に委ねる。旧 grep 抽出は path 中の
# `,` `}` / escape で途中切りし、この gate を無音 fail-open にした (2026-07-10 監査)。
# shellcheck source=lib/parse-command.sh
. "$(dirname "$0")/lib/parse-command.sh"
FILE=$(printf '%s' "$INPUT" | parse_json_string_field file_path)
if [ -z "$FILE" ]; then
  FILE=$(printf '%s' "$INPUT" | parse_json_string_field path)
fi
[ -z "$FILE" ] && exit 0

command -v git >/dev/null 2>&1 || exit 0
TOP=$(git rev-parse --show-toplevel 2>/dev/null | tr '\\\\' '/' | tr -s '/')
[ -z "$TOP" ] && exit 0
# arch manifest は `.bootstrap/arch` (新) / `.bootstrap-arch` (旧) どちらでも可。
# shellcheck source=lib/resolve-marker.sh
. "$(dirname "$0")/lib/resolve-marker.sh"
MANIFEST="$(resolve_marker "$TOP" arch)"
[ -f "$MANIFEST" ] || exit 0   # fail-open

FILE_NORM=$(printf '%s' "$FILE" | tr '\\\\' '/' | tr -s '/')
case "$FILE_NORM" in
  "$TOP"/*) REL="${FILE_NORM#"$TOP"/}" ;;
  *) exit 0 ;;   # worktree 外は判断不能 → fail-open
esac

# shellcheck source=lib/arch-check.sh
. "$(dirname "$0")/lib/arch-check.sh"
arch_load_manifest "$MANIFEST" || exit 0

# layer 外の file は強制対象外
[ -n "$(arch_layer_of "$REL")" ] || exit 0

# JSON を最小 unescape して新内容を blob 化 (\n → 改行、\" → ")。
# import specifier は content 中に現れる。file_path 等の他 field は import パターンに
# 合致しないので arch_extract の誤検出にはならない。
BLOB="${INPUT//\\n/$'\n'}"
BLOB="${BLOB//\\\"/\"}"

if VIO="$(printf '%s' "$BLOB" | arch_check_imports "$REL" "${REL##*.}")"; then
  exit 0
fi

cat >&2 <<EOF
project-bootstrap: blocking edit on "$REL" — introduces a disallowed cross-layer import.

$(printf '%s' "$VIO" | sed '/^$/d; s/^/  - /')

この編集は .bootstrap-arch の依存方向に反する。対処:
  - その処理は別 layer の責務 → 正しい layer に書く
  - 内側の層の機能が必要        → port (interface) を内側に定義して依存を反転する
  - 契約自体を変えるべき        → .bootstrap-arch の allow 辺を意図的に編集する

例外的に通すだけなら /permissions で本 hook を一時 deny。
EOF
exit 2

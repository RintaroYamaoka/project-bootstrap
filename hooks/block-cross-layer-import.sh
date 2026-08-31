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

# field 抽出は単一権威 lib/parse-command.sh の decoder に委ねる。旧 grep 抽出は path 中の
# `,` `}` / escape で途中切りし、この gate を無音 fail-open にした (2026-07-10 監査)。
# shellcheck source=lib/parse-command.sh
. "${BASH_SOURCE[0]%/*}/lib/parse-command.sh"
# shellcheck source=lib/resolve-marker.sh
. "${BASH_SOURCE[0]%/*}/lib/resolve-marker.sh"
# shellcheck source=lib/arch-check.sh
. "${BASH_SOURCE[0]%/*}/lib/arch-check.sh"
# shellcheck source=lib/repo-top.sh
. "${BASH_SOURCE[0]%/*}/lib/repo-top.sh"

# gate 本体 — 契約は lib/standalone.sh ヘッダ参照 (global INPUT / FILE を読む)。
gate_block_cross_layer_import() {
  local TOP MANIFEST FILE_NORM REL BLOB VIO

repo_top_var
TOP="$REPO_TOP"
[ -z "$TOP" ] && return 0
# arch manifest は `.bootstrap/arch` (新) / `.bootstrap-arch` (旧) どちらでも可。
MANIFEST="$(resolve_marker "$TOP" arch)"
[ -f "$MANIFEST" ] || return 0   # fail-open

norm_path_var "$FILE"
FILE_NORM="$NORM_PATH"
case "$FILE_NORM" in
  "$TOP"/*) REL="${FILE_NORM#"$TOP"/}" ;;
  *) return 0 ;;   # worktree 外は判断不能 → fail-open
esac

arch_load_manifest "$MANIFEST" || return 0

# layer 外の file は強制対象外
[ -n "$(arch_layer_of "$REL")" ] || return 0

# JSON を最小 unescape して新内容を blob 化 (\n → 改行、\" → ")。
# import specifier は content 中に現れる。file_path 等の他 field は import パターンに
# 合致しないので arch_extract の誤検出にはならない。
BLOB="${INPUT//\\n/$'\n'}"
BLOB="${BLOB//\\\"/\"}"

if VIO="$(printf '%s' "$BLOB" | arch_check_imports "$REL" "${REL##*.}")"; then
  return 0
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
return 2
}

# 単体起動 (tests / vendoring 消費者) — dispatcher からは source されるので走らない。
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  # shellcheck source=lib/standalone.sh
  . "${BASH_SOURCE[0]%/*}/lib/standalone.sh"
  bootstrap_standalone_edit_gate gate_block_cross_layer_import
fi

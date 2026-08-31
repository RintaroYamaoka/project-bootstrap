#!/usr/bin/env bash
# 単体実行エントリ (ADR 0026) — 各 gate script は「関数定義 + この footer」の二面構成:
#
#   - dispatcher (hooks/dispatch.sh) は gate file を source して gate_* 関数だけ使う
#     (= 1 tool call 1 プロセス。Windows / MSYS の fork 遅延を踏まない)
#   - tests / vendoring 消費者 (.claude/hooks/ に script を個別配線した repo) は従来
#     どおり `bash <gate>.sh` + stdin JSON で単体起動する。その入口がこの lib。
#
# 契約 (gate 関数側):
#   - 読むのは globals: INPUT (raw JSON) / CMD (bash gate) / FILE (edit gate)。書かない
#   - return 0 = pass、return 2 = block (メッセージは自分で stderr へ)
#   - scratch 変数は必ず local (dispatcher では 22 gate が 1 プロセスを共有する)
#
# fail-mode は従来の gate 別挙動をそのまま写す:
#   - blocking bash gate  = parse 不能で fail-closed (exit 2 + 定型文)
#   - injector (fail-open) = parse 不能で無音 exit 0
#   - edit gate           = file_path/path が取れなければ無音 exit 0

[ -n "${_BOOTSTRAP_LIB_STANDALONE:-}" ] && return 0
_BOOTSTRAP_LIB_STANDALONE=1

# bootstrap_standalone_bash_gate <gate-fn> — blocking bash gate の単体入口 (fail-closed)。
bootstrap_standalone_bash_gate() {
  IFS= read -r -d '' INPUT || :
  if ! parse_command_var "$INPUT"; then
    echo "project-bootstrap: could not parse the tool command from hook input — blocking to fail safe (fail-closed). If this is a false positive, disable this hook via /permissions." >&2
    exit 2
  fi
  CMD="$PARSED_CMD"
  [ -z "$CMD" ] && exit 0
  "$1"
  exit $?
}

# bootstrap_standalone_bash_gate_open <gate-fn> — 何も block しない hook (injector) の
# 単体入口。block する側面が無いので parse 不能は無音 exit 0 (fail-open)。
bootstrap_standalone_bash_gate_open() {
  IFS= read -r -d '' INPUT || :
  parse_command_var "$INPUT" || exit 0
  CMD="$PARSED_CMD"
  [ -z "$CMD" ] && exit 0
  "$1"
  exit $?
}

# bootstrap_standalone_edit_gate <gate-fn> — Edit|Write|MultiEdit gate の単体入口。
bootstrap_standalone_edit_gate() {
  IFS= read -r -d '' INPUT || :
  edit_file_var "$INPUT"
  [ -z "$FILE" ] && exit 0
  "$1"
  exit $?
}

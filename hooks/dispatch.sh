#!/usr/bin/env bash
# dispatch.sh <bash|edit> — PreToolUse gate 群の単一プロセス実行 (ADR 0026)。
#
# WHY: hooks.json は従来 Bash tool call ごとに 16 本、Edit|Write|MultiEdit ごとに 6 本の
# `bash <gate>.sh` を別プロセスで起動していた。各 script はさらに $(cat) / $(dirname) /
# pipeline で ~7 fork を払う。Linux では 1 tool call 合計 ~0.2s で無害だが、Windows
# (Git Bash / MSYS) は fork が 10-30 倍遅く、体感で数秒/回 — 規律の速度税として重すぎ、
# hook を deny する動機 (= 規律を殺す誤検知と同型の逆効果) を作る。
#
# HOW: stdin を builtin `read` で 1 回読み、payload を fork ゼロの変数 API
# (lib/parse-command.sh) で 1 回だけ parse し、各 gate file を source して gate_* 関数を
# hooks.json が配線していた順に同一プロセスで呼ぶ。source は最初に block した gate で
# 止まる (以降の file I/O も払わない)。gate 側の契約は lib/standalone.sh のヘッダ参照。
#
# 挙動の parity (tests/hooks/dispatch.test.bash が固定):
#   - block した gate の exit 2 / stderr banner はそのまま dispatcher の出力
#   - parse 不能な payload は fail-closed (従来は 15 blocker が各自同文で block していた)
#   - command / file_path が空なら exit 0 (全 gate が素通しだった入力)
#   - injector (inject-action-memory) の stdout JSON は最後に 1 本だけなのでそのまま通る
#   - 未知の mode 引数は fail-closed (配線 typo で 22 gate が無音に死ぬのを防ぐ)
#
# 単体起動 (tests / vendoring 消費者) は従来どおり各 gate script が受ける — この file は
# hooks.json 専用の入口で、gate のロジックは一切持たない (単一権威は各 gate 関数)。

set -u

HOOK_DIR="${BASH_SOURCE[0]%/*}"
[ "$HOOK_DIR" = "${BASH_SOURCE[0]}" ] && HOOK_DIR="."
MODE="${1:-}"

IFS= read -r -d '' INPUT || :

# shellcheck source=lib/parse-command.sh
. "$HOOK_DIR/lib/parse-command.sh"

# hooks.json が従来配線していた発火順そのまま。injector は唯一の stdout 出力者なので末尾。
BASH_GATES="block-add-all block-dangerous-git-ops block-cross-claude-wip block-push-to-protected block-stale-write-to-protected block-over-wip-parallel block-unreviewed-merge block-merge-if-verification-unclosed block-arch-violations block-out-of-lane-commit block-commit-if-retired-term block-commit-if-wo-incomplete block-commit-if-impl-uncovered block-commit-if-lint-fails block-commit-if-tests-fail inject-action-memory"
EDIT_GATES="block-out-of-lane-edit block-uniso-main-edit block-unplanned-feature-build block-impl-without-wo block-cross-layer-import require-test-companion"

# run_gates <space-separated gate list> — source → gate_* 呼び出しを順に。非 0 で即 exit
# (block した gate の rc をそのまま返す)。
run_gates() {
  local g fn rc
  for g in $1; do
    # shellcheck disable=SC1090
    . "$HOOK_DIR/$g.sh"
    fn="gate_${g//-/_}"
    "$fn"
    rc=$?
    [ "$rc" -ne 0 ] && exit "$rc"
  done
  return 0
}

case "$MODE" in
  bash)
    if ! parse_command_var "$INPUT"; then
      echo "project-bootstrap: could not parse the tool command from hook input — blocking to fail safe (fail-closed). If this is a false positive, disable this hook via /permissions." >&2
      exit 2
    fi
    CMD="$PARSED_CMD"
    [ -z "$CMD" ] && exit 0
    run_gates "$BASH_GATES"
    ;;
  edit)
    edit_file_var "$INPUT"
    [ -z "$FILE" ] && exit 0
    run_gates "$EDIT_GATES"
    ;;
  *)
    echo "project-bootstrap: dispatch.sh called with unknown matcher mode '${MODE}' — blocking to fail safe (a wiring typo must not silently disarm the gates)." >&2
    exit 2
    ;;
esac

exit 0

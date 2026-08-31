#!/usr/bin/env bash
# bench-hooks.sh — hook 実行コストの実測 (ADR 0026 の検証オラクル)。
#
# 旧配線 (gate script を 1 本ずつ別プロセスで起動) と新配線 (dispatch.sh 1 プロセス) の
# 1 tool call あたりの wall-clock を、同じ payload で N 回ずつ測って比べる。
# Windows (Git Bash / MSYS) でこそ差が出る — fork が Linux の 10-30 倍遅いため。
# 使い方:
#   bash scripts/bench-hooks.sh          # N=20
#   bash scripts/bench-hooks.sh 50       # N=50
#
# 出力はミリ秒/回。オラクルは date +%s%N (GNU coreutils — Git Bash にもある)。

set -u

N="${1:-20}"
HOOKS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../hooks" && pwd)"

BASH_GATES="block-add-all block-dangerous-git-ops block-cross-claude-wip block-push-to-protected block-stale-write-to-protected block-over-wip-parallel block-unreviewed-merge block-merge-if-verification-unclosed block-arch-violations block-out-of-lane-commit block-commit-if-retired-term block-commit-if-wo-incomplete block-commit-if-impl-uncovered block-commit-if-lint-fails block-commit-if-tests-fail inject-action-memory"
EDIT_GATES="block-out-of-lane-edit block-uniso-main-edit block-unplanned-feature-build block-impl-without-wo block-cross-layer-import require-test-companion"

PAYLOAD_BASH='{"tool_name":"Bash","tool_input":{"command":"npm test"}}'
PAYLOAD_EDIT='{"tool_name":"Edit","tool_input":{"file_path":"docs/README.md","old_string":"a","new_string":"b"}}'

now_ms() { echo $(( $(date +%s%N) / 1000000 )); }

# time_loop <label> <iterations> <fn>
time_loop() {
  local label="$1" n="$2" fn="$3" t0 t1 i
  t0=$(now_ms)
  i=0
  while [ "$i" -lt "$n" ]; do
    "$fn"
    i=$((i + 1))
  done
  t1=$(now_ms)
  printf '  %-46s %6s ms/回  (%d 回で %d ms)\n' "$label" "$(( (t1 - t0) / n ))" "$n" "$((t1 - t0))"
}

old_bash() { local g; for g in $BASH_GATES; do printf '%s' "$PAYLOAD_BASH" | bash "$HOOKS/$g.sh" >/dev/null 2>&1; done; }
new_bash() { printf '%s' "$PAYLOAD_BASH" | bash "$HOOKS/dispatch.sh" bash >/dev/null 2>&1; }
old_edit() { local g; for g in $EDIT_GATES; do printf '%s' "$PAYLOAD_EDIT" | bash "$HOOKS/$g.sh" >/dev/null 2>&1; done; }
new_edit() { printf '%s' "$PAYLOAD_EDIT" | bash "$HOOKS/dispatch.sh" edit >/dev/null 2>&1; }

echo "hook 実行コスト ($(uname -s) / bash ${BASH_VERSION%%(*})"
echo
echo "Bash tool call 1 回分 (非 git command):"
time_loop "旧: 16 gate を個別プロセス起動" "$N" old_bash
time_loop "新: dispatch.sh bash (1 プロセス)" "$N" new_bash
echo
echo "Edit tool call 1 回分 (docs file):"
time_loop "旧: 6 gate を個別プロセス起動" "$N" old_edit
time_loop "新: dispatch.sh edit (1 プロセス)" "$N" new_edit

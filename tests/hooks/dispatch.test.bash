#!/usr/bin/env bash
# Tests for hooks/dispatch.sh — the single-process dispatcher (ADR 0026).
#
# WHY dispatch exists: hooks.json used to wire 16 separate `bash <gate>.sh` commands
# on every Bash tool call (6 on every Edit). Each spawn + its ~7 subprocess preamble
# is invisible on Linux (~12ms/hook) but dominant on Windows Git Bash / MSYS, where
# fork is 10-30x slower — multiple SECONDS per tool call. dispatch.sh reads stdin
# once with builtin `read`, parses the payload once (fork-free lib/parse-command.sh
# var API), then sources each gate and calls its gate_* function IN THE SAME PROCESS,
# in the same order hooks.json used to wire them.
#
# The contract pinned here (parity with the per-script wiring):
#   - a gate that blocks => dispatcher exits 2 with that gate's stderr banner
#   - all gates pass     => exit 0
#   - unparseable payload => exit 2 fail-closed (same message the gates each printed)
#   - empty / absent command => exit 0 (no gate fires on nothing)
#   - the injector's stdout JSON (hookSpecificOutput) passes through unchanged
#   - gates run in hooks.json order: an earlier gate's full walk must not
#     contaminate a later gate's verdict (they now share one process)

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"

bash_json() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1"; }

# --- bash matcher: blocking parity ---------------------------------------------

test_case "dispatch bash: bulk-stage (gate 1 in order) blocks through the dispatcher"
run_hook dispatch.sh "$(bash_json 'git add -A')" bash
assert_exit 2
assert_stderr_contains "blocking bulk-staging op"

test_case "dispatch bash: a LATER gate still blocks after earlier gates ran their full walk"
run_hook dispatch.sh "$(bash_json 'git commit -m x && git reset --hard')" bash
assert_exit 2
assert_stderr_contains "git reset --hard"

test_case "dispatch bash: non-git command passes everything"
run_hook dispatch.sh "$(bash_json 'npm test')" bash
assert_exit 0
assert_stdout_empty

test_case "dispatch bash: unparseable payload is fail-closed (exit 2)"
run_hook dispatch.sh '{"tool_input":{"content":"x"}}' bash
assert_exit 2
assert_stderr_contains "could not parse the tool command"

test_case "dispatch bash: empty command exits 0"
run_hook dispatch.sh "$(bash_json '')" bash
assert_exit 0

test_case "dispatch bash: heredoc body is data, not command (ADR 0025 parity)"
run_hook dispatch.sh '{"tool_name":"Bash","tool_input":{"command":"git commit -F - <<MSG\n一括 stage は git add -A を使わない\nMSG"}}' bash
assert_exit 0

test_case "dispatch bash: injector stdout JSON passes through (plugin-default prod-deploy memo)"
run_hook dispatch.sh "$(bash_json 'vercel deploy --prod')" bash
assert_exit 0
assert_stdout_contains '"hookSpecificOutput"'
assert_stdout_contains 'prod-deploy'

# ordering / contamination: run two dispatch calls back-to-back in ONE process is
# impossible from here (each run_hook is a process) — instead pin that a single
# compound command exercising MULTIPLE gates' parsers still yields the FIRST
# blocking gate's banner (gate order is add-all before dangerous-git-ops).
test_case "dispatch bash: when two gates would both block, the FIRST in order wins"
run_hook dispatch.sh "$(bash_json 'git add -A && git reset --hard')" bash
assert_exit 2
assert_stderr_contains "blocking bulk-staging op"

# --- edit matcher ----------------------------------------------------------------

test_case "dispatch edit: payload without file_path exits 0 (fail-open parity)"
run_hook dispatch.sh '{"tool_name":"Edit","tool_input":{"content":"x"}}' edit
assert_exit 0

test_case "dispatch edit: TDD companion gate blocks an impl edit without a test"
FIX="$(mktemp -d)"
mkdir -p "$FIX/src"
RUN_DIR="$FIX" run_hook dispatch.sh "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$FIX/src/foo.ts\",\"old_string\":\"a\",\"new_string\":\"b\"}}" edit
assert_exit 2
rm -rf "$FIX"

test_case "dispatch edit: test file itself passes"
FIX="$(mktemp -d)"
mkdir -p "$FIX/src"
RUN_DIR="$FIX" run_hook dispatch.sh "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$FIX/src/foo.test.ts\",\"old_string\":\"a\",\"new_string\":\"b\"}}" edit
assert_exit 0
rm -rf "$FIX"

# --- mode guard ------------------------------------------------------------------

test_case "dispatch: unknown mode is fail-closed (a wiring typo must not silently disarm 22 gates)"
run_hook dispatch.sh "$(bash_json 'git add -A')" nosuchmode
assert_exit 2

# --- 配線の完全性 (drift net) -------------------------------------------------------
# gate を足して dispatch.sh の GATES に足し忘れると、その gate は plugin 経由で一度も
# 発火しない (無音の配備漏れ)。hooks/ に在る gate script の集合と、dispatch.sh が
# 結線している集合の完全一致をここで機械検査する。非 gate script (doctor / reminder /
# dispatch 自身) は除外リストで明示する — 新しい非 gate script を足すならここに名を書く。

test_case "dispatch wires EVERY gate script in hooks/ (none forgotten, none phantom)"
DISPATCH_LISTED="$(
  bash -c 'BASH_SOURCE_DIR="$1"; set -u
    BOOTSTRAP_DISPATCH_LIST_ONLY=1
    BASH_GATES="$(sed -n "s/^BASH_GATES=\"\(.*\)\"$/\1/p" "$1/dispatch.sh")"
    EDIT_GATES="$(sed -n "s/^EDIT_GATES=\"\(.*\)\"$/\1/p" "$1/dispatch.sh")"
    for g in $BASH_GATES $EDIT_GATES; do echo "$g.sh"; done | sort' _ "$HOOKS_DIR"
)"
ACTUAL="$(cd "$HOOKS_DIR" && ls ./*.sh | sed 's|^\./||' \
  | grep -v -e '^bootstrap-session-doctor\.sh$' -e '^sprint-trigger-reminder\.sh$' -e '^dispatch\.sh$' \
  | sort)"
assert_eq "$ACTUAL" "$DISPATCH_LISTED"

finish

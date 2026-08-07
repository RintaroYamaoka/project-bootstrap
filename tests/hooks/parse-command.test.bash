#!/usr/bin/env bash
# Unit tests for hooks/lib/parse-command.sh — the shared, fail-closed extractor
# for the Bash tool's command string out of a PreToolUse JSON payload.
#
# The bug this replaces: the seven hooks each ran
#   grep -oE '"command"[^,}]*'
# which stops at the FIRST ',' or '}'. A command like
#   git commit -m "fix, bug" && git add -A
# was truncated to `git commit -m "fix` — the trailing `git add -A` vanished, so
# block-add-all (and the other gates) silently passed (fail-OPEN) what they exist
# to block. parse_command must read to the real (unescaped) closing quote, decode
# one level of JSON escapes, and on unparseable input return non-zero so each
# caller can fail CLOSED (block).
#
# Contract:
#   stdin  = raw PreToolUse JSON
#   stdout = decoded value of the first "command" key
#   exit 0 = key found (value may be empty)
#   exit 1 = "command" key absent or string never terminates (unparseable)

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"
source "$(cd "$DIR/../../hooks" && pwd)/lib/parse-command.sh"

# parse <raw-json> — run parse_command, echo stdout (rc is left in $? for callers).
parse() { printf '%s' "$1" | parse_command; }

# --- the regression that motivated this lib -----------------------------------
test_case "comma inside -m message does not truncate; trailing && git add -A survives"
got="$(parse '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"fix, bug\" && git add -A"}}')"
assert_eq 'git commit -m "fix, bug" && git add -A' "$got"

test_case "a closing brace inside the value does not truncate"
got="$(parse '{"command":"echo \"a}b\" && rm -rf x"}')"
assert_eq 'echo "a}b" && rm -rf x' "$got"

# --- escape decoding -----------------------------------------------------------
test_case "escaped double-quotes decode and do not terminate the value early"
got="$(parse '{"command":"echo \"a\" \"b\""}')"
assert_eq 'echo "a" "b"' "$got"

test_case "escaped backslash decodes to a single backslash"
got="$(parse '{"command":"grep \\d file"}')"
assert_eq 'grep \d file' "$got"

test_case "\\n decodes to a real newline"
exp=$'echo a\nb'
got="$(parse '{"command":"echo a\nb"}')"
assert_eq "$exp" "$got"

test_case "a backslash-then-quote (JSON \\\\\\\") decodes to \\\" and does not mis-terminate"
got="$(parse '{"command":"printf \\\"end"}')"
assert_eq 'printf \"end' "$got"

# --- whitespace tolerance ------------------------------------------------------
test_case "whitespace around the colon is tolerated"
got="$(parse '{"command"  :   "ls -la"}')"
assert_eq 'ls -la' "$got"

# --- regression: plain commands pass through unchanged -------------------------
test_case "a plain command with no specials is returned verbatim"
got="$(parse '{"tool_name":"Bash","tool_input":{"command":"git add -A"}}')"
assert_eq 'git add -A' "$got"

# --- fail-closed signalling ----------------------------------------------------
test_case "missing command key returns non-zero (so callers can block)"
parse '{"tool_name":"Bash","tool_input":{"foo":"bar"}}' >/dev/null 2>&1; rc=$?
assert_eq 1 "$rc"

test_case "an unterminated command string returns non-zero"
parse '{"command":"git add -A' >/dev/null 2>&1; rc=$?
assert_eq 1 "$rc"

test_case "an empty command value parses as empty string with exit 0"
got="$(parse '{"command":""}')"; rc=$?
assert_eq '' "$got"
assert_eq 0 "$rc"

# --- parse_json_string_field: the generalized extractor (2026-07-10 audit) ------
# Eight call sites still ran the OLD `grep -oE '"file_path"[^,}]*' | sed` pattern for
# file_path/cwd/transcript_path — the exact truncation class parse_command was built
# to kill. A path containing ',' or '}' or an escaped quote was cut mid-value, and
# the affected Edit-side gates silently fail-OPENed on it.
pfield() { printf '%s' "$2" | parse_json_string_field "$1"; }

test_case "file_path with a comma is NOT truncated (the audited bypass)"
got="$(pfield file_path '{"tool_input":{"file_path":"src/foo,bar/baz.ts","content":"x"}}')"
assert_eq 'src/foo,bar/baz.ts' "$got"

test_case "cwd with a closing brace survives"
got="$(pfield cwd '{"cwd":"/tmp/a}b/repo"}')"
assert_eq '/tmp/a}b/repo' "$got"

test_case "transcript_path with JSON-escaped backslashes decodes"
got="$(pfield transcript_path '{"transcript_path":"C:\\Users\\t\\x.jsonl"}')"
assert_eq 'C:\Users\t\x.jsonl' "$got"

test_case "absent key returns non-zero and prints nothing"
pfield file_path '{"tool_input":{"content":"x"}}' >/dev/null 2>&1; rc=$?
assert_eq 1 "$rc"

test_case "the FIRST occurrence of the key wins (same as the old extractors)"
got="$(pfield file_path '{"file_path":"a.ts","nested":{"file_path":"b.ts"}}')"
assert_eq 'a.ts' "$got"

test_case "parse_command extracts the command like the generalized extractor"
got="$(pfield command '{"command":"git add -A"}')"
assert_eq 'git add -A' "$got"

# ── heredoc 本文は「実行されるコマンド」ではない (ADR 0025 / ai-reception 2026-08-08)
#
# 誤検知の実害: `git commit -F -` の heredoc に「一括 stage は git add -A を使わない」と
# 規約説明を書いた commit が block された。walker は改行を単なる空白として word-split
# するので、heredoc 本文のトークンがコマンド列に流れ込む。同じ穴が raw regex 経路
# (block-dangerous-git-ops) にもあり、**gate が規律の説明そのものを妨げていた** =
# 「gate が自分の bypass を作る」失敗モード。
#
# fail-direction: 本文を落とすのは検出を緩める向きなので、**本文が実際に実行される形
# (シェルに heredoc を食わせる) は落とさない** (fail-closed を維持する)。
strip() { strip_heredoc_bodies "$1"; }

test_case "heredoc 本文は落ちる (quoted label)"
got="$(strip "$(printf 'cat <<%sEOF%s\ngit add -A\nEOF' "'" "'")")"
assert_eq "cat <<'EOF'" "$got"

test_case "heredoc の演算子行そのものは残る (コマンドだから)"
got="$(strip $'git commit -F - <<MSG\n本文に git add -A と書く\nMSG')"
assert_eq 'git commit -F - <<MSG' "$got"

test_case "<<- 形式はタブ字下げの終端ラベルで閉じる"
got="$(strip $'cat <<-EOF\n\tgit add -A\n\tEOF')"
assert_eq 'cat <<-EOF' "$got"

# この行が要る理由 (mutation で判明): 上の `<<-` テストだけでは、タブ除去を消しても
# 「終端が一致せず未終端扱い → 末尾まで落ちる」で**出力が同じ**になり、変異が生存する。
# 終端の後ろに実コマンドを置いて初めて差が出る。しかもその差は「実 git add -A を飲み込む」
# = 検出漏れ (fail-open) の向きなので、ここが緩いと gate が無音で死ぬ。
test_case "<<- の終端が閉じ、その後ろの実コマンドは残る (飲み込まない)"
got="$(strip $'cat <<-EOF\n\t本文\n\tEOF\ngit add -A')"
assert_eq $'cat <<-EOF\ngit add -A' "$got"

test_case "未終端 heredoc は末尾まで本文とみなす"
got="$(strip $'cat <<EOF\ngit add -A\n')"
assert_eq 'cat <<EOF' "$got"

test_case "終端ラベルより後ろの実コマンドは残る (検出を殺さない)"
got="$(strip $'cat <<EOF\nただの本文\nEOF\ngit add -A')"
assert_eq $'cat <<EOF\ngit add -A' "$got"

test_case "シェルに食わせる heredoc は本文を残す (実行されるので fail-closed)"
got="$(strip $'bash <<EOF\ngit add -A\nEOF')"
assert_eq $'bash <<EOF\ngit add -A\nEOF' "$got"

test_case "path 付きシェルでも本文を残す"
got="$(strip $'/bin/sh <<EOF\ngit add -A\nEOF')"
assert_eq $'/bin/sh <<EOF\ngit add -A\nEOF' "$got"

test_case "herestring (<<<) は heredoc ではない — 後続行を食わない"
got="$(strip $'cat <<<"text"\ngit add -A')"
assert_eq $'cat <<<"text"\ngit add -A' "$got"

test_case "1 行に heredoc 2 つ — 本文も 2 つ順に落ちる"
got="$(strip $'cmd <<A <<B\nbody-a\nA\nbody-b\nB\ngit status')"
assert_eq $'cmd <<A <<B\ngit status' "$got"

test_case "heredoc が無ければ素通し (既存挙動を変えない)"
got="$(strip 'git add -A && git commit -m "x"')"
assert_eq 'git add -A && git commit -m "x"' "$got"

test_case "parse_command は heredoc 本文を落として返す (全 gate の単一経路)"
got="$(printf '%s' '{"command":"cat <<EOF\ngit add -A\nEOF"}' | parse_command)"
assert_eq 'cat <<EOF' "$got"

test_case "parse_command は unparseable で非ゼロ (fail-closed の契約は不変)"
printf '%s' '{"tool_input":{"content":"x"}}' | parse_command >/dev/null 2>&1; rc=$?
assert_eq 1 "$rc"

finish

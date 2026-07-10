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

test_case "parse_command remains a thin alias of the generalized extractor"
got="$(pfield command '{"command":"git add -A"}')"
assert_eq 'git add -A' "$got"

finish

#!/usr/bin/env bash
# Shared, fail-closed extractor for string fields of the hook's stdin JSON payload.
#
# Every PreToolUse-on-Bash hook needs the `command` value out of the JSON payload
# Claude Code pipes on stdin, and the Edit/SessionStart hooks need `file_path` /
# `cwd` / `transcript_path`. The hooks used to do:
#   grep -oE '"command"[^,}]*'
# but `[^,}]*` stops at the first ',' or '}', so a command containing either —
#   git commit -m "fix, bug" && git add -A
# — was truncated to `git commit -m "fix`, dropping the trailing `git add -A`. The
# gates (block-add-all, block-dangerous-git-ops, …) then saw a harmless fragment
# and passed (fail-OPEN) commands they exist to block: the exact "silent failure /
# falls to the unsafe side" trap the discipline warns about. The 2026-07-10 audit
# found the SAME truncation pattern still live at eight call sites for file_path /
# cwd / transcript_path (a path containing ',' '}' or an escaped quote was cut
# mid-value and those gates silently fail-OPENed), so the extractor is generalized:
# parse_json_string_field <key> is the single authority for pulling any string
# field out of the payload; parse_command is its `command` alias.
#
# parse_json_string_field reads to the real (unescaped) closing quote and decodes
# one level of JSON string escapes, so commas, braces and embedded quotes are
# handled. When the input is unparseable it returns non-zero AND prints nothing, so
# each caller chooses its fail-mode (blocking gates fail CLOSED on `command`;
# advisory/visibility callers fail OPEN). Pure bash, jq-free — matches lib/arch-check.sh.
#
# Contract (parse_json_string_field <key>):
#   stdin  : raw hook JSON
#   stdout : decoded value of the first "<key>" key
#   return : 0 if the key was found (value may be empty); 1 if absent/unterminated.
#
# Note: \uXXXX is left undecoded (rare in shell commands/paths); every other JSON
# escape (\" \\ \/ \n \t \r \b \f) is decoded. The single left-to-right scan also
# resolves the \\" ambiguity correctly (\\ then ", not \ then escaped-quote).

# parse_json_string_field <key> — see header. Reads stdin, writes decoded value to stdout.
parse_json_string_field() {
  local key="$1" input after c nxt out="" i len

  input="$(cat)"

  # Locate the first "<key>" occurrence. No occurrence => unparseable (caller decides).
  case "$input" in
    *"\"$key\""*) ;;
    *) return 1 ;;
  esac
  after="${input#*\"$key\"}"

  # Skip whitespace, the ':', more whitespace, then require the opening quote.
  after="${after#"${after%%[![:space:]]*}"}"
  [ "${after:0:1}" = ":" ] || return 1
  after="${after:1}"
  after="${after#"${after%%[![:space:]]*}"}"
  [ "${after:0:1}" = '"' ] || return 1
  after="${after:1}"

  # Scan the value char-by-char to the first UNESCAPED '"', decoding as we go.
  len=${#after}
  i=0
  while [ "$i" -lt "$len" ]; do
    c="${after:i:1}"
    if [ "$c" = "\\" ]; then
      nxt="${after:i+1:1}"
      case "$nxt" in
        '"') out="$out\"" ;;
        '\') out="$out\\" ;;
        '/') out="$out/" ;;
        n)   out="$out"$'\n' ;;
        t)   out="$out"$'\t' ;;
        r)   out="$out"$'\r' ;;
        b)   out="$out"$'\b' ;;
        f)   out="$out"$'\f' ;;
        '')  out="$out\\"; i=$((i + 1)); continue ;;  # trailing lone backslash
        *)   out="$out\\$nxt" ;;                        # unknown escape: keep both
      esac
      i=$((i + 2))
      continue
    fi
    if [ "$c" = '"' ]; then
      printf '%s' "$out"
      return 0
    fi
    out="$out$c"
    i=$((i + 1))
  done

  # Reached end of input without a closing quote => unterminated (fail-closed).
  return 1
}

# parse_command — the `command` alias (kept as the blocking gates' entry point so the
# fail-closed contract reads at the call site).
parse_command() {
  parse_json_string_field command
}

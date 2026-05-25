#!/usr/bin/env bash
# Shared, fail-closed extractor for the Bash tool's command string.
#
# Every PreToolUse-on-Bash hook needs the `command` value out of the JSON payload
# Claude Code pipes on stdin. The hooks used to do:
#   grep -oE '"command"[^,}]*'
# but `[^,}]*` stops at the first ',' or '}', so a command containing either —
#   git commit -m "fix, bug" && git add -A
# — was truncated to `git commit -m "fix`, dropping the trailing `git add -A`. The
# gates (block-add-all, block-dangerous-git-ops, …) then saw a harmless fragment
# and passed (fail-OPEN) commands they exist to block: the exact "silent failure /
# falls to the unsafe side" trap the discipline warns about.
#
# parse_command reads to the real (unescaped) closing quote and decodes one level
# of JSON string escapes, so commas, braces and embedded quotes are handled. When
# the input is unparseable it returns non-zero AND prints nothing, so each caller
# can choose to fail CLOSED (block). Pure bash, jq-free — matches lib/arch-check.sh.
#
# Contract:
#   stdin  : raw PreToolUse JSON
#   stdout : decoded value of the first "command" key
#   return : 0 if the key was found (value may be empty); 1 if absent/unterminated.
#
# Note: \uXXXX is left undecoded (rare in shell commands); every other JSON escape
# (\" \\ \/ \n \t \r \b \f) is decoded. The single left-to-right scan also resolves
# the \\" ambiguity correctly (\\ then ", not \ then escaped-quote).

# parse_command — see header. Reads stdin, writes decoded command to stdout.
parse_command() {
  local input after c nxt out="" i len

  input="$(cat)"

  # Locate the first "command" key. No occurrence => unparseable (fail-closed).
  case "$input" in
    *'"command"'*) ;;
    *) return 1 ;;
  esac
  after="${input#*\"command\"}"

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

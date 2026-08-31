#!/usr/bin/env bash
# Hook — PreToolUse(Bash). Surface the recorded memo AT the moment a repeat-prone ACTION
# runs, so a fix already documented in memory is not skipped again.
#
# WHY this exists (the incident): a deploy-author bug recurred ~7 times even though a memory
# documented the exact fix. The memo was never in front of the actor at the moment the prod
# deploy ran, so each session re-discovered the bug. This hook injects that memo as PreToolUse
# additionalContext right before the matched action executes.
#
# WHY it NEVER blocks / NEVER exits 2 (the cardinal design constraint — ADR 0010, ADR 0001):
# this is a VISIBILITY mechanism, not a precondition. An ack/block token would be self-issuable
# by the very actor being gated, so it is abandoned — comprehension is irreducible and we do
# not pretend to enforce it. The hook only injects context and exits 0.
#
# WHY parse failure is fail-OPEN/silent here (not fail-CLOSED like the blocking gates): a gate
# that blocks must fail CLOSED so a malformed payload can't slip an unsafe action past it. This
# hook blocks NOTHING, so there is no unsafe side — an unreadable command simply yields no memo
# and we exit 0 silent. Likewise: no registry (opt-in, so non-adopting repos are undisturbed)
# and no enum-key match are silent by design.
#
# Matching is delegated wholly to lib/action-gate.sh (the shared tokenizer + CLOSED enum) so
# this hook never pattern-matches a raw command itself. The JSON output shape mirrors the other
# context-injecting hook, bootstrap-session-doctor.sh (hookSpecificOutput.additionalContext).
# Pure bash, jq-free.

set -u

# shellcheck source=lib/parse-command.sh
. "${BASH_SOURCE[0]%/*}/lib/parse-command.sh"
# shellcheck source=lib/action-gate.sh
. "${BASH_SOURCE[0]%/*}/lib/action-gate.sh"

# gate 本体 — 契約は lib/standalone.sh ヘッダ参照 (global INPUT / CMD を読む)。
# この hook は決して block しない (常に return 0)。stdout に additionalContext JSON を出す
# 唯一の Bash gate なので、dispatcher は本 gate を発火順の末尾に置く。
gate_inject_action_memory() {
  local KEY CWD REPO GITTOP DEFAULT_MEMO REG_MEMO MEMO BODY ESC

# Only Bash tool calls carry a command to inspect. Anything else: silent pass.
case "$INPUT" in
  *'"tool_name"'*'"Bash"'*|*'"Bash"'*'"tool_name"'*) ;;
  *) return 0 ;;
esac

# Tokenize -> match an enum key. No match => silent pass.
KEY="$(action_key_for_command "$CMD")"
[ -n "$KEY" ] || return 0

# Resolve cwd to read the per-repo registry (opt-in). Single-authority decoder — the
# old grep extraction truncated at ',' '}' inside the path (2026-07-10 audit; harmless
# here beyond a possibly-missed memo, but one authority beats eight copies).
json_field_var cwd "$INPUT" || JSON_FIELD=""
CWD="$JSON_FIELD"
[ -z "$CWD" ] && CWD="$PWD"

# Resolve to the git root so the registry is found regardless of subdir cwd (fall back to
# CWD when not a git repo — opt-in registry there is still honored).
REPO="$CWD"
if command -v git >/dev/null 2>&1; then
  GITTOP=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null | tr '\\' '/' | tr -s '/')
  [ -n "$GITTOP" ] && REPO="$GITTOP"
fi

# Two memo sources (ADR 0013 / ADR 0014):
#   - DEFAULT: a plugin-owned universal doctrine for this key (currently data-backfill (ADR
#     0013) and prod-deploy (ADR 0014)). Fires even when the repo has NOT armed the key — a
#     project-agnostic safety floor.
#   - REGISTRY: the repo's opt-in .bootstrap-actions memo for this key (project-specific).
# We surface whichever exist (default first, then the project memo appended). If neither
# exists (a project-specific key in an unarmed repo), stay silent (opt-in preserved).
DEFAULT_MEMO="$(action_default_memo "$KEY")"
REG_MEMO="$(registry_memo_for_key "$REPO" "$KEY")"
if [ -n "$DEFAULT_MEMO" ] && [ -n "$REG_MEMO" ]; then
  MEMO="$DEFAULT_MEMO
  + this repo: ${REG_MEMO}"
else
  MEMO="${DEFAULT_MEMO}${REG_MEMO}"
fi
[ -n "$MEMO" ] || return 0

# Build the injected body. We name the action-key explicitly so the actor knows WHICH
# repeat-prone action tripped this, then hand the recorded guidance/reminder.
BODY="[project-bootstrap] repeat-prone action detected: ${KEY}.
Recorded guidance for this action — read it BEFORE running:
  ${MEMO}
(This is advisory context, NOT a block. Nothing is required of you but to read it.)"

# Escape the body into a JSON string (jq-free, identical to bootstrap-session-doctor.sh):
# backslash, then double-quote, then newline.
ESC="$BODY"
ESC="${ESC//\\/\\\\}"
ESC="${ESC//\"/\\\"}"
ESC="${ESC//$'\n'/\\n}"

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$ESC"
return 0
}

# 単体起動 (tests / vendoring 消費者) — dispatcher からは source されるので走らない。
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  # shellcheck source=lib/standalone.sh
  . "${BASH_SOURCE[0]%/*}/lib/standalone.sh"
  bootstrap_standalone_bash_gate_open gate_inject_action_memory
fi

#!/usr/bin/env bash
# Tests for hooks/block-add-all.sh
#
# Hook D — PreToolUse on Bash. Pure command-string parsing: it blocks (exit 2)
# bulk-staging commands that could sweep a parallel Claude/terminal's WIP into a
# commit/stash, and passes (exit 0) individual-path ops and non-matching commands.
# No git repo or transcript is needed — only tool_input.command is read.
#
# These are characterization tests: they pin the hook's CURRENT behavior so a
# future regex tweak can't silently change it. Boundary cases that the regex must
# get right (and one case where the spec and the implementation disagree — see the
# "stash push -m with -- pathspec" block below) are called out inline.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"

# input_json <command> — minimal PreToolUse payload. The hook greps the command
# out of the raw JSON (it does not parse JSON), so commands must avoid the chars
# the extractor stops at: line 23 uses '"command"[^,}]*', so a literal ',' or '}'
# inside the command would truncate it. Plain test commands stay clear of both.
input_json() {
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1"
}

# block_case <label> <command> — assert the command is blocked (exit 2) and that
# the canonical block banner is emitted on stderr.
block_case() {
  test_case "$1"
  run_hook block-add-all.sh "$(input_json "$2")"
  assert_exit 2
  assert_stderr_contains "blocking bulk-staging op"
}

# pass_case <label> <command> — assert the command passes (exit 0).
pass_case() {
  test_case "$1"
  run_hook block-add-all.sh "$(input_json "$2")"
  assert_exit 0
}

# ── BLOCK side ────────────────────────────────────────────────────────────────

# git add bulk forms
block_case "git add -A blocks"                "git add -A"
block_case "git add --all blocks"             "git add --all"
block_case "git add . blocks"                 "git add ."
block_case "git add ./ blocks"                "git add ./"
block_case "git add -u blocks"                "git add -u"
block_case "git add --update blocks"          "git add --update"

# git commit auto-stage forms. -am / -aim are caught by the -[A-Za-z]*a[A-Za-z]*
# short-flag pattern; --all by its own branch.
block_case "git commit -a blocks"             "git commit -a"
block_case "git commit -am blocks"            "git commit -am x"
block_case "git commit -aim blocks"           "git commit -aim x"
block_case "git commit --all blocks"          "git commit --all"

# git stash WIP-sweeping forms
block_case "git stash (no args) blocks"       "git stash"
block_case "git stash push (no pathspec)"     "git stash push"
block_case "git stash save (no pathspec)"     "git stash save"
block_case "git stash -u blocks"              "git stash -u"
block_case "git stash --include-untracked"    "git stash --include-untracked"

# stash with a message but NO pathspec is still a full-WIP stash -> block.
block_case "git stash push -m (no pathspec)"  "git stash push -m msg"
block_case "git stash save -m (no pathspec)"  "git stash save -m msg"

# CHARACTERIZATION OF A GAP (see report): the hook blocks `git stash push -m <msg>`
# even when a `-- <pathspec>` follows, because it only checks for the presence of
# -m/--message and never re-checks for a trailing pathspec. The task spec says this
# form SHOULD pass; the implementation blocks it. We pin the ACTUAL behavior here.
block_case "git stash push -m WITH -- pathspec (blocks; spec wanted pass)" \
                                              "git stash push -m msg -- path/to/file"

# Bulk add embedded in a compound command is still caught (leading delimiter regex).
block_case "git add -A after && is caught"    "echo hi && git add -A"

# ── PASS side ─────────────────────────────────────────────────────────────────

# Individual-path adds — the disciplined form the hook steers toward.
pass_case "git add single path passes"        "git add path/to/file.ts"
pass_case "git add multiple paths passes"     "git add src/a.ts src/b.ts"

# `git add -- .` uses an explicit pathspec separator; the `git add .` regex does
# not match it, so it passes (boundary the regex must not over-block).
pass_case "git add -- . passes"               "git add -- ."

# Commit with an explicit message (no auto-stage flag).
pass_case "git commit -m passes"              "git commit -m hello"

# --amend alone is not an auto-stage flag here -> passes (this hook is add/stash
# focused; foreign-staged amend is block-cross-claude-wip.sh's job).
pass_case "git commit --amend passes"         "git commit --amend"

# stash WITH an explicit -- pathspec (and no -m) passes.
pass_case "git stash push -- pathspec passes" "git stash push -- path/to/file"

# Non-git command — hook bails at the early git-presence guard.
pass_case "npm test passes (non-git)"         "npm test"

# Read-only git command — matches git but no bulk-stage pattern.
pass_case "git status passes"                 "git status"

# Empty command (no command extractable) -> early exit 0.
pass_case "empty command passes"              ""

finish

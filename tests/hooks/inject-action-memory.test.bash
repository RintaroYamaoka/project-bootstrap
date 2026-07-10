#!/usr/bin/env bash
# Entry tests for hooks/inject-action-memory.sh — the ONLY hook that had no test on its
# real stdin-JSON -> stdout behaviour (its engine lib/action-gate.sh is unit-tested, but
# the hook's own wiring — tool_name filter, command parse, cwd->registry resolution,
# additionalContext JSON emission — was unpinned).
#
# The hook NEVER blocks (ADR 0010): every path must exit 0. What varies is whether it
# emits a hookSpecificOutput.additionalContext memo on stdout.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"

HOOK=inject-action-memory.sh

# input_json <command> <cwd>
input_json() {
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' "$1" "$2"
}

NONREPO="$(mktemp -d)"

# --- silent paths (all exit 0, no stdout) ---------------------------------------------
test_case "non-Bash tool input is silent"
run_hook "$HOOK" '{"tool_name":"Edit","tool_input":{"file_path":"x.ts"},"cwd":"/tmp"}'
assert_exit 0
assert_stdout_empty

test_case "a non-action command is silent"
run_hook "$HOOK" "$(input_json 'git status' "$NONREPO")"
assert_exit 0
assert_stdout_empty

test_case "a PREVIEW deploy (bare vercel deploy) does not fire the prod memo"
run_hook "$HOOK" "$(input_json 'vercel deploy' "$NONREPO")"
assert_exit 0
assert_stdout_empty

test_case "unparseable payload is silent exit 0 (this hook never blocks — fail-open)"
run_hook "$HOOK" '{"tool_name":"Bash","tool_input":{}}'
assert_exit 0
assert_stdout_empty

# --- plugin-default memos fire even in an UNARMED repo ---------------------------------
test_case "vercel deploy --prod emits the prod-deploy default memo as additionalContext"
run_hook "$HOOK" "$(input_json 'vercel deploy --prod' "$NONREPO")"
assert_exit 0
assert_stdout_contains '"hookSpecificOutput"'
assert_stdout_contains '"additionalContext"'
assert_stdout_contains 'prod-deploy'

test_case "an inline UPDATE through psql emits the data-backfill default memo"
run_hook "$HOOK" "$(input_json 'psql -c UPDATE' "$NONREPO")"
assert_exit 0
assert_stdout_contains 'data-backfill'

# --- key with NO default memo stays silent unless the repo arms it ---------------------
test_case "prisma migrate deploy in an unarmed repo is silent (opt-in preserved)"
run_hook "$HOOK" "$(input_json 'prisma migrate deploy' "$NONREPO")"
assert_exit 0
assert_stdout_empty

# --- armed registry: repo memo is surfaced ----------------------------------------------
git config --global user.email >/dev/null 2>&1 || git config --global user.email "test@example.com"
git config --global user.name  >/dev/null 2>&1 || git config --global user.name  "test"
tmp="$(mktemp -d)"
git -C "$tmp" init -q
REPO="$(git -C "$tmp" rev-parse --show-toplevel)"
mkdir -p "$REPO/.bootstrap"
printf 'prod-db-migrate | docs/memo-slug.md | run backups first\n' > "$REPO/.bootstrap/actions"

RUN_DIR="$REPO"
test_case "an armed key surfaces the repo's registry memo"
run_hook "$HOOK" "$(input_json 'prisma migrate deploy' "$REPO")"
assert_exit 0
assert_stdout_contains 'prod-db-migrate'
assert_stdout_contains 'docs/memo-slug.md'
assert_stdout_contains 'run backups first'

test_case "the armed repo memo is appended AFTER the plugin default for a default-carrying key"
printf 'prod-deploy | docs/deploy-notes.md | check env vars\n' >> "$REPO/.bootstrap/actions"
run_hook "$HOOK" "$(input_json 'vercel deploy --prod' "$REPO")"
assert_exit 0
assert_stdout_contains 'prod-deploy'
assert_stdout_contains 'docs/deploy-notes.md'

finish

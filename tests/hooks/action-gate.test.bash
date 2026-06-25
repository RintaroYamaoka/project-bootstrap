#!/usr/bin/env bash
# Tests for hooks/lib/action-gate.sh (the tokenizer + CLOSED action-key enum + opt-in
# registry reader) and hooks/inject-action-memory.sh (the PreToolUse(Bash) memo injector).
#
# Why this exists (the incident this lane answers): a deploy-author bug recurred ~7 times
# even though a memory documented the exact fix — the memo was never surfaced AT the moment
# the repeat-prone action (a prod deploy) ran. This lane injects the recorded memo as
# PreToolUse additionalContext so the fix is in front of the actor before the action.
#
# The matcher is a SHARED TOKENIZER mapping commands to a CLOSED, plugin-owned ACTION-KEY
# enum (modeled on lib/merge-targets.sh / lib/protected-branch.sh: strip env-prefixes,
# accept path-prefixed bins, walk compound segments, noglob word-split). NOT per-entry user
# regex — per-entry regex would re-import the greedy-sed / string-proxy bug class unreviewed.
# Adding a key is a reviewed plugin-level enum change; the registry only ARMS an existing key.
#
# Hard invariants verified here:
#   - representative commands map to the right enum key, incl. path-prefixed + compound +
#     env-prefixed forms, and benign commands DO NOT false-match (return empty);
#   - the hook injects valid additionalContext JSON when an action is matched AND armed;
#   - the hook is SILENT (exit 0, no stdout) when unmatched, or matched-but-unarmed, or
#     there is no registry at all (opt-in / fail-OPEN);
#   - the hook NEVER exits 2 (it is a visibility mechanism, not a blocking precondition);
#   - parse failure => exit 0 silent (nothing to fail-closed; this hook never blocks).

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"
source "$(cd "$DIR/../../hooks" && pwd)/lib/action-gate.sh"

# key <command> — print the matched action-key (empty if none) for a stable assertion.
key() { action_key_for_command "$1"; }

# --- action_key_for_command: the controlled-vocab matcher --------------------------

test_case "bare 'vercel deploy --prod' maps to prod-deploy"
assert_eq 'prod-deploy' "$(key 'vercel deploy --prod')"

test_case "'vercel --prod deploy' (flag before subcommand) maps to prod-deploy"
assert_eq 'prod-deploy' "$(key 'vercel --prod deploy')"

test_case "path-prefixed /usr/local/bin/vercel deploy --prod maps to prod-deploy"
assert_eq 'prod-deploy' "$(key '/usr/local/bin/vercel deploy --prod')"

test_case "npx-launched 'npx vercel deploy --prod' maps to prod-deploy"
assert_eq 'prod-deploy' "$(key 'npx vercel deploy --prod')"

test_case "env-prefixed 'CI=1 VERCEL_TOKEN=x vercel deploy --prod' maps to prod-deploy"
assert_eq 'prod-deploy' "$(key 'CI=1 VERCEL_TOKEN=x vercel deploy --prod')"

test_case "compound: prod-deploy in the SECOND segment is still matched"
assert_eq 'prod-deploy' "$(key 'npm run build && vercel deploy --prod')"

test_case "'bash -c \"vercel deploy --prod\"' is matched (wrapper unwrap)"
assert_eq 'prod-deploy' "$(key 'bash -c "vercel deploy --prod"')"

# prod-db-migrate enum key (the second representative repeat-prone action).
test_case "'prisma migrate deploy' maps to prod-db-migrate"
assert_eq 'prod-db-migrate' "$(key 'prisma migrate deploy')"

test_case "env-prefixed path-prefixed migrate maps to prod-db-migrate"
assert_eq 'prod-db-migrate' "$(key 'DATABASE_URL=postgres://x ./node_modules/.bin/prisma migrate deploy')"

# --- no false matches on benign / preview commands ---------------------------------
test_case "preview deploy ('vercel deploy' without --prod) does NOT match prod-deploy"
assert_eq '' "$(key 'vercel deploy')"

test_case "'vercel --prod' alone (no deploy subcommand) does NOT match"
assert_eq '' "$(key 'vercel --prod')"

test_case "'git status' does not match any action key"
assert_eq '' "$(key 'git status')"

test_case "a benign 'prisma generate' does not match prod-db-migrate"
assert_eq '' "$(key 'prisma generate')"

test_case "the word 'deploy' inside an echo string does not match"
assert_eq '' "$(key 'echo deploy --prod to production')"

# --- registry reader: opt-in, returns the armed memo --------------------------------
mk_repo() {
  REG_REPO="$(mktemp -d)"
}

test_case "no registry file => no memo (opt-in / fail-open)"
mk_repo
assert_eq '' "$(registry_memo_for_key "$REG_REPO" prod-deploy)"

test_case "registry arms prod-deploy => its memo slug+note is returned"
mk_repo
printf 'prod-deploy | feedback_deploy_author_fix | always pass --build-env AUTHOR\n' > "$REG_REPO/.bootstrap-actions"
out="$(registry_memo_for_key "$REG_REPO" prod-deploy)"
case "$out" in
  *feedback_deploy_author_fix*AUTHOR*) assert_eq pass pass ;;
  *) assert_eq 'memo for prod-deploy' "$out" ;;
esac

test_case "registry does NOT arm the queried key => no memo (silent)"
mk_repo
printf 'prod-db-migrate | feedback_migrate | run in maintenance window\n' > "$REG_REPO/.bootstrap-actions"
assert_eq '' "$(registry_memo_for_key "$REG_REPO" prod-deploy)"

test_case "comment + blank lines in registry are ignored"
mk_repo
printf '# header comment\n\nprod-deploy | slugX | noteX\n' > "$REG_REPO/.bootstrap-actions"
case "$(registry_memo_for_key "$REG_REPO" prod-deploy)" in
  *slugX*noteX*) assert_eq pass pass ;;
  *) assert_eq 'memo' 'no-memo' ;;
esac

# --- orphan audit: an armed key not in the CLOSED enum ------------------------------
test_case "an armed key not in the enum is reported as orphan"
mk_repo
printf 'prod-deploy | slug | ok\nnot-a-real-key | slug | bad\n' > "$REG_REPO/.bootstrap-actions"
case "$(registry_orphan_keys "$REG_REPO")" in
  *not-a-real-key*) assert_eq pass pass ;;
  *) assert_eq 'orphan listed' 'none' ;;
esac

test_case "a registry with only valid enum keys has no orphans"
mk_repo
printf 'prod-deploy | slug | ok\nprod-db-migrate | slug | ok\n' > "$REG_REPO/.bootstrap-actions"
assert_eq '' "$(registry_orphan_keys "$REG_REPO")"

# --- the hook: inject-action-memory.sh ----------------------------------------------
# Build a PreToolUse(Bash) input JSON carrying a command string (jq-free, like the other
# hook tests). RUN_DIR is the repo whose .bootstrap-actions registry the hook reads.
bash_input() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' "$1" "${2:-$PWD}"; }

ARMED="$(mktemp -d)"
printf 'prod-deploy | feedback_deploy_author_fix | always pass --build-env AUTHOR\n' > "$ARMED/.bootstrap-actions"

test_case "matched + armed action injects additionalContext JSON, exit 0"
RUN_DIR="$ARMED" run_hook inject-action-memory.sh "$(bash_input 'vercel deploy --prod' "$ARMED")"
assert_exit 0
assert_stdout_contains '"hookEventName":"PreToolUse"'
assert_stdout_contains 'additionalContext'
assert_stdout_contains 'prod-deploy'
assert_stdout_contains 'feedback_deploy_author_fix'

test_case "matched but UNARMED (registry exists, key not listed) is silent, exit 0"
ONLY_MIGRATE="$(mktemp -d)"
printf 'prod-db-migrate | slug | note\n' > "$ONLY_MIGRATE/.bootstrap-actions"
RUN_DIR="$ONLY_MIGRATE" run_hook inject-action-memory.sh "$(bash_input 'vercel deploy --prod' "$ONLY_MIGRATE")"
assert_exit 0
assert_stdout_empty

test_case "no registry at all (opt-in) is silent, exit 0"
NOREG="$(mktemp -d)"
RUN_DIR="$NOREG" run_hook inject-action-memory.sh "$(bash_input 'vercel deploy --prod' "$NOREG")"
assert_exit 0
assert_stdout_empty

test_case "unmatched benign command is silent even with an armed registry, exit 0"
RUN_DIR="$ARMED" run_hook inject-action-memory.sh "$(bash_input 'git status' "$ARMED")"
assert_exit 0
assert_stdout_empty

test_case "preview deploy (no --prod) is silent even with prod-deploy armed, exit 0"
RUN_DIR="$ARMED" run_hook inject-action-memory.sh "$(bash_input 'vercel deploy' "$ARMED")"
assert_exit 0
assert_stdout_empty

test_case "unparseable input => exit 0 silent (nothing to fail-closed; never blocks)"
RUN_DIR="$ARMED" run_hook inject-action-memory.sh '{"tool_name":"Bash","tool_input":{}}'
assert_exit 0
assert_stdout_empty

test_case "non-Bash tool input is silent, exit 0"
RUN_DIR="$ARMED" run_hook inject-action-memory.sh '{"tool_name":"Edit","tool_input":{"file_path":"x"}}'
assert_exit 0
assert_stdout_empty

# The cardinal invariant: this hook must NEVER exit 2 (it is visibility, not a gate).
# Exercise the armed-match path (the one most tempted to "enforce") and confirm exit != 2.
test_case "armed match NEVER exits 2 (visibility, not a precondition)"
RUN_DIR="$ARMED" run_hook inject-action-memory.sh "$(bash_input 'vercel deploy --prod' "$ARMED")"
if [ "$HOOK_EXIT" = 2 ]; then
  TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
  echo "  FAIL [$CURRENT_TEST] hook exited 2 (must never block)"
else
  TESTS_RUN=$((TESTS_RUN + 1)); echo "  ok   [$CURRENT_TEST] did not exit 2 (exit $HOOK_EXIT)"
fi

finish

#!/usr/bin/env bash
# Tests for hooks/bootstrap-session-doctor.sh (SessionStart).
#
# The hook wraps scripts/doctor.sh and injects its verdict as additionalContext ONLY for
# actionable states (unadopted = offer to set up / partial = warn about a silent coverage gap).
# ok / declined / non-git stay silent (= no advisory bloat). It is advisory, not enforcement —
# adoption needs consent, so it cannot be hook-forced; the per-action gates do the enforcing.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"

HOOK=bootstrap-session-doctor.sh

setup_repo() {
  local tmp; tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  REPO="$(git -C "$tmp" rev-parse --show-toplevel)"
  git -C "$REPO" config user.email t@t.test
  git -C "$REPO" config user.name tester
}
session_input() { printf '{"hook_event_name":"SessionStart","cwd":"%s"}' "$1"; }

# 1. Unadopted repo => offer injected as SessionStart additionalContext.
setup_repo
RUN_DIR="$REPO"
test_case "unadopted repo injects an offer"
run_hook "$HOOK" "$(session_input "$REPO")"
assert_exit 0
assert_stdout_contains '"hookEventName":"SessionStart"'
assert_stdout_contains "unadopted"

# 2. Adopted + consistent (docs/sprint, plugin path) => silent.
setup_repo
mkdir -p "$REPO/docs/sprint"
RUN_DIR="$REPO"
test_case "adopted+consistent repo is silent"
run_hook "$HOOK" "$(session_input "$REPO")"
assert_exit 0
assert_stdout_empty

# 3. Partial (arch declared but empty) => warning injected.
setup_repo
printf '# no directives\n' > "$REPO/.bootstrap-arch"
RUN_DIR="$REPO"
test_case "partial repo injects a warning"
run_hook "$HOOK" "$(session_input "$REPO")"
assert_exit 0
assert_stdout_contains "partial"

# 4. Vendored-coverage gap (sprint adopted, gate hook missing) => warning names the gate.
setup_repo
mkdir -p "$REPO/docs/sprint" "$REPO/.claude/hooks"
for h in require-test-companion.sh block-commit-if-tests-fail.sh block-add-all.sh \
         block-dangerous-git-ops.sh block-cross-claude-wip.sh; do : > "$REPO/.claude/hooks/$h"; done
RUN_DIR="$REPO"
test_case "vendored gap warning names the missing gate"
run_hook "$HOOK" "$(session_input "$REPO")"
assert_stdout_contains "block-unplanned-feature-build.sh"

# 5. Declined repo => silent (no nag).
setup_repo
: > "$REPO/.bootstrap-declined"
RUN_DIR="$REPO"
test_case "declined repo is silent"
run_hook "$HOOK" "$(session_input "$REPO")"
assert_exit 0
assert_stdout_empty

# 6. Non-git cwd => silent (fail-open).
NOGIT="$(mktemp -d)"
RUN_DIR="$NOGIT"
test_case "non-git cwd is silent"
run_hook "$HOOK" "$(session_input "$NOGIT")"
assert_exit 0
assert_stdout_empty

# 7. Missing cwd in input => falls back to RUN_DIR, still valid (no crash).
setup_repo
RUN_DIR="$REPO"
test_case "missing cwd falls back to PWD without crashing"
run_hook "$HOOK" '{"hook_event_name":"SessionStart"}'
assert_exit 0

# 8. Repo drift surfaces INDEPENDENTLY of adoption: adopted+consistent but HEAD behind
#    origin/main => the stale-checkout nudge is injected even though the adoption audit is ok.
setup_repo
mkdir -p "$REPO/docs/sprint"
git -C "$REPO" commit -q --allow-empty -m c0
BASE="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" commit -q --allow-empty -m c1
git -C "$REPO" update-ref refs/remotes/origin/main "$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" reset -q --hard "$BASE"
RUN_DIR="$REPO"
test_case "behind origin/main injects drift nudge even when adoption is ok"
run_hook "$HOOK" "$(session_input "$REPO")"
assert_exit 0
assert_stdout_contains "遅れ"

# 9. Merged-but-leftover worktree => teardown nudge injected.
setup_repo
mkdir -p "$REPO/docs/sprint"
git -C "$REPO" commit -q --allow-empty -m c0
H="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" update-ref refs/remotes/origin/main "$H"
git -C "$REPO" branch feat-old "$H"
WT="$(mktemp -d)/old"; git -C "$REPO" worktree add -q "$WT" feat-old
RUN_DIR="$REPO"
test_case "leftover merged worktree injects teardown nudge"
run_hook "$HOOK" "$(session_input "$REPO")"
assert_exit 0
assert_stdout_contains "worktree remove"

finish

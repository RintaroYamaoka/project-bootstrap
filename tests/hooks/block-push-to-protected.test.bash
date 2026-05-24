#!/usr/bin/env bash
# Tests for hooks/block-push-to-protected.sh
#
# Incident defense-in-depth: the mixed commit reached origin/main directly. Direct
# pushes to main/master are also an anti-pattern in the sprint flow (feature branch +
# PR via the integrate skill). This hook blocks pushes whose target is a protected
# branch, whether named explicitly or implied by the current branch.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"

setup_repo() {
  local tmp; tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  REPO="$(git -C "$tmp" rev-parse --show-toplevel)"
  git -C "$REPO" config user.email t@t.test
  git -C "$REPO" config user.name tester
  echo seed > "$REPO/seed.txt"
  git -C "$REPO" add seed.txt
  git -C "$REPO" commit -qm seed
}
on_branch() { git -C "$REPO" checkout -q -B "$1"; }
push_input() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' "$1" "$REPO"; }

setup_repo
RUN_DIR="$REPO"

on_branch feature/x
test_case "explicit push to main is blocked"
run_hook block-push-to-protected.sh "$(push_input 'git push origin main')"
assert_exit 2

test_case "explicit push to master is blocked"
run_hook block-push-to-protected.sh "$(push_input 'git push origin master')"
assert_exit 2

test_case "push to HEAD:main refspec is blocked"
run_hook block-push-to-protected.sh "$(push_input 'git push origin HEAD:main')"
assert_exit 2

test_case "push to a feature branch passes"
run_hook block-push-to-protected.sh "$(push_input 'git push origin feature/x')"
assert_exit 0

test_case "plain push while on a feature branch passes"
run_hook block-push-to-protected.sh "$(push_input 'git push')"
assert_exit 0

on_branch main
test_case "plain push while on main is blocked"
run_hook block-push-to-protected.sh "$(push_input 'git push')"
assert_exit 2

test_case "push -u origin main is blocked"
run_hook block-push-to-protected.sh "$(push_input 'git push -u origin main')"
assert_exit 2

test_case "non-push git command passes"
run_hook block-push-to-protected.sh "$(push_input 'git status')"
assert_exit 0

finish

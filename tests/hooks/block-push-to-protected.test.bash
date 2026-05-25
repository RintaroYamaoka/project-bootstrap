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
  # opt-in: the hook only enforces when the project declares protected branches.
  printf 'main\nmaster\nrelease/*\n' > "$REPO/.bootstrap-protected"
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

# glob entry: release/* is protected -> push to release/1.2 is blocked.
on_branch feature/x
test_case "push to a glob-matched protected branch is blocked"
run_hook block-push-to-protected.sh "$(push_input 'git push origin release/1.2')"
assert_exit 2

# Regression (the fail-OPEN bug this lib fixes): a comma inside the quoted -m
# message used to truncate the parse at the comma, hiding the trailing
# `git push origin main` so the protected-branch push slipped through.
on_branch feature/x
test_case "comma in -m message does not hide a trailing push to protected main"
push_regress_json='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"x, y\" && git push origin main"},"cwd":"'"$REPO"'"}'
run_hook block-push-to-protected.sh "$push_regress_json"
assert_exit 2

# opt-in: with NO .bootstrap-protected, even a main push is allowed (fail-open).
setup_repo
rm "$REPO/.bootstrap-protected"
git -C "$REPO" checkout -q -B main
RUN_DIR="$REPO"
test_case "no .bootstrap-protected: push to main allowed (opt-in / fail-open)"
run_hook block-push-to-protected.sh "$(push_input 'git push origin main')"
assert_exit 0

finish

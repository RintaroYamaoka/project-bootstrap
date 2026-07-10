#!/usr/bin/env bash
# Unit tests for hooks/lib/protected-branch.sh — the shared push-destination enumerator
# and protected-branch authority for the push gate (block-push-to-protected.sh).
#
# The two LIVE bugs this lib replaces (both the same "string proxy for an action" class
# the doctrine condemns, mirrored on lib/merge-targets.sh):
#   1. The detector keyed on a bare `git push` token with no `/` allowance, so
#        /usr/bin/git push origin main      was invisible      → push past the gate
#   2. Arg extraction used `sed 's/^.*git push//'` (greedy → only the LAST push of a
#      compound command), so
#        git push origin main && git push origin feat/x
#      inspected ONLY the feat/x push and let the protected `main` push through with
#      zero enforcement. This lib walks every segment and accepts path-prefixed git.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"
source "$(cd "$DIR/../../hooks" && pwd)/lib/protected-branch.sh"

# dests <command> — join enumerated destination branches with commas for a stable assertion.
dests() { push_destination_branches "$1" | paste -sd, -; }
has_push() { if cmd_has_git_push "$1"; then echo yes; else echo no; fi; }
# protected <branch> <file> — yes/no wrapper over is_protected for assertions.
protected() { if is_protected "$1" "$2"; then echo yes; else echo no; fi; }

# --- cmd_has_git_push --------------------------------------------------------------
test_case "bare git push is detected"
assert_eq yes "$(has_push 'git push origin main')"

test_case "path-prefixed /usr/bin/git push is detected (the bypass)"
assert_eq yes "$(has_push '/usr/bin/git push origin main')"

test_case "./git push is detected"
assert_eq yes "$(has_push './git push origin main')"

test_case "git push inside a compound command is detected"
assert_eq yes "$(has_push 'echo hi && git push origin main')"

test_case "mygit push is NOT a git push (no false trigger)"
assert_eq no "$(has_push 'mygit push origin main')"

test_case "legit push is NOT a git push (preceding char is a letter)"
assert_eq no "$(has_push 'legit push origin main')"

test_case "git status is not a push"
assert_eq no "$(has_push 'git status')"

# --- push_destination_branches: the core bug ---------------------------------------
test_case "single push yields its destination branch"
assert_eq 'main' "$(dests 'git push origin main')"

test_case "compound '&&' push yields BOTH destinations (greedy-sed regression)"
assert_eq 'main,feat/x' "$(dests 'git push origin main && git push origin feat/x')"

test_case "compound ';' push without surrounding spaces yields both"
assert_eq 'main,feat/x' "$(dests 'git push origin main;git push origin feat/x')"

test_case "path-prefixed git push yields its destination (token regression)"
assert_eq 'main' "$(dests '/usr/bin/git push origin main')"

# --- push_destination_branches: refspec normalization ------------------------------
test_case "src:dst refspec yields only the destination (dst)"
assert_eq 'main' "$(dests 'git push origin HEAD:main')"

test_case "leading + (force) is stripped from the destination"
assert_eq 'main' "$(dests 'git push origin +main')"

test_case "refs/heads/ prefix is stripped from the destination"
assert_eq 'main' "$(dests 'git push origin refs/heads/main')"

test_case "src:dst with refs/heads/ and + on dst normalizes to bare branch"
assert_eq 'main' "$(dests 'git push origin +HEAD:refs/heads/main')"

# --- push_destination_branches: flags & their values must not be read as branches --
test_case "the remote (first positional) is not emitted as a branch"
assert_eq '' "$(dests 'git push origin')"

test_case "a value-taking flag's value is not read as a branch (--repo)"
assert_eq 'main' "$(dests 'git push --repo myrepo origin main')"

test_case "-o push-option value is skipped, the branch is still found"
assert_eq 'main' "$(dests 'git push -o ci.skip origin main')"

test_case "--receive-pack value is skipped"
assert_eq 'main' "$(dests 'git push --receive-pack /path/git-rp origin main')"

test_case "--flag=value inline form needs no separate skip"
assert_eq 'main' "$(dests 'git push --repo=myrepo origin main')"

test_case "plain flags (-u/--force) are skipped"
assert_eq 'main' "$(dests 'git push -u --force origin main')"

test_case "multiple refspecs each emit a destination"
assert_eq 'main,feat/x' "$(dests 'git push origin main feat/x')"

# --- git global options (2026-07-10 audit: ALL of these were live bypasses) ---------
test_case "git -C <path> push is detected (global-option bypass)"
assert_eq yes "$(has_push 'git -C /repo push origin main')"

test_case "git -c k=v push is detected"
assert_eq yes "$(has_push 'git -c core.pager=cat push origin main')"

test_case "git --git-dir=.git push is detected"
assert_eq yes "$(has_push 'git --git-dir=.git push origin main')"

test_case "git -P push is detected (flag-only global option)"
assert_eq yes "$(has_push 'git -P push origin main')"

test_case "git -C <path> push yields its destination (tokenizer armed past global opts)"
assert_eq 'main' "$(dests 'git -C /repo push origin main')"

test_case "git -c k=v --no-pager push yields its destination"
assert_eq 'main' "$(dests 'git -c k=v --no-pager push origin main')"

test_case "the value of -C is not read as remote or branch"
assert_eq 'main' "$(dests 'git -C main push origin main')"

# --- push_pushes_all_branches: --all/--mirror/--branches (destination unenumerable) --
all_push() { if push_pushes_all_branches "$1"; then echo yes; else echo no; fi; }

test_case "git push --all origin is an all-branches push"
assert_eq yes "$(all_push 'git push --all origin')"

test_case "git push --mirror origin is an all-branches push"
assert_eq yes "$(all_push 'git push --mirror origin')"

test_case "git push --branches origin is an all-branches push"
assert_eq yes "$(all_push 'git push --branches origin')"

test_case "git push --all in a compound command is caught"
assert_eq yes "$(all_push 'echo hi && git -C /repo push --all origin')"

test_case "a plain refspec push is NOT an all-branches push"
assert_eq no "$(all_push 'git push origin main')"

test_case "a push-option VALUE of --all is not an all-branches push (-o skip)"
assert_eq no "$(all_push 'git push -o --all origin main')"

test_case "--all in a NON-push command does not count"
assert_eq no "$(all_push 'git branch --all')"

test_case "an all-branches push still emits no refspec destinations (caller must ask)"
assert_eq '' "$(dests 'git push --all origin')"

# --- push_destination_branches: no false positives ---------------------------------
test_case "a no-refspec push emits nothing (implicit current branch handled by caller)"
assert_eq '' "$(dests 'git push')"

test_case "a branch echoed after '&&' is NOT read as a push destination"
assert_eq 'main' "$(dests 'git push origin main && echo feat/x')"

test_case "a non-push command yields no destinations"
assert_eq '' "$(dests 'git status')"

# --- is_protected: the moved authority ---------------------------------------------
PROT="$(mktemp)"
printf '%s\n' 'main' 'master' 'release/*' '# a comment' '' '   spaced/branch  ' > "$PROT"

test_case "an exactly-named protected branch matches"
assert_eq yes "$(protected main "$PROT")"

test_case "a glob-matched protected branch matches (release/*)"
assert_eq yes "$(protected 'release/1.2' "$PROT")"

test_case "an unprotected feature branch does not match"
assert_eq no "$(protected 'feat/x' "$PROT")"

test_case "'#' comment lines are ignored (not matched literally)"
assert_eq no "$(protected '# a comment' "$PROT")"

test_case "blank lines are ignored (empty branch never matches)"
assert_eq no "$(protected '' "$PROT")"

test_case "surrounding whitespace on a pattern line is trimmed before matching"
assert_eq yes "$(protected 'spaced/branch' "$PROT")"

rm -f "$PROT"

finish

#!/usr/bin/env bash
# Unit tests for hooks/lib/git-invocation.sh — the shared, single-authority walker for
# "does this command invoke `git <subcommand>`?" (ADR 0019).
#
# The bug class this lib kills (all reproduced LIVE in the 2026-07-10 audit): every Bash
# gate keyed on a regex that required `push`/`commit` IMMEDIATELY after the word `git`,
# so ALL of these slipped past blocking gates unseen (fail-OPEN of a blocking gate):
#   git -C /repo push origin main        (value-taking global option)
#   git -c k=v push origin main
#   git --git-dir=.git push origin main  (inline-value global option)
#   git -P push origin main              (flag-only global option)
#   /usr/bin/git commit … / ./git commit (path-prefixed git, commit-side gates)
# Instead of regex whack-a-mole, this lib tokenizes, skips git global options, and reads
# the FIRST non-option token after `git` as THE subcommand.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"
source "$(cd "$DIR/../../hooks" && pwd)/lib/git-invocation.sh"

# invokes <cmd> <sub> — yes/no wrapper for assertions.
invokes() { if cmd_invokes_git_subcommand "$1" "$2"; then echo yes; else echo no; fi; }
# arglines <cmd> <sub> — join emitted arglines with '/' so empty lines stay visible.
arglines() { git_subcommand_arglines "$1" "$2" | sed 's/^$/<empty>/' | paste -sd/ -; }

# --- detection: the audited bypasses (each was a live MISS before this lib) ---------
test_case "git -C <path> push is detected (value-taking global option)"
assert_eq yes "$(invokes 'git -C /repo push origin main' push)"

test_case "git -c k=v push is detected"
assert_eq yes "$(invokes 'git -c core.pager=cat push origin main' push)"

test_case "git --git-dir=.git push is detected (inline-value global option)"
assert_eq yes "$(invokes 'git --git-dir=.git push origin main' push)"

test_case "git --git-dir <path> push is detected (separate-value form)"
assert_eq yes "$(invokes 'git --git-dir .git push origin main' push)"

test_case "git -P push is detected (flag-only global option)"
assert_eq yes "$(invokes 'git -P push origin main' push)"

test_case "git --no-pager -c a=b commit is detected (stacked global options)"
assert_eq yes "$(invokes 'git --no-pager -c a=b commit -m x' commit)"

test_case "/usr/bin/git commit is detected (path-prefixed git)"
assert_eq yes "$(invokes '/usr/bin/git commit -m x' commit)"

test_case "./git commit is detected"
assert_eq yes "$(invokes './git commit -m x' commit)"

test_case "bare git commit is detected (no regression)"
assert_eq yes "$(invokes 'git commit -m x' commit)"

test_case "git commit inside a compound command is detected"
assert_eq yes "$(invokes 'echo hi && git -C /r commit -m x' commit)"

test_case "subshell-wrapped git push is detected (paren separator)"
assert_eq yes "$(invokes '(git push origin main)' push)"

# --- detection: no false trigger ----------------------------------------------------
test_case "mygit commit is NOT a git commit"
assert_eq no "$(invokes 'mygit commit -m x' commit)"

test_case "legit push is NOT a git push"
assert_eq no "$(invokes 'legit push origin main' push)"

test_case "git status is not a commit"
assert_eq no "$(invokes 'git status' commit)"

test_case "the value of -C is never read as the subcommand"
assert_eq no "$(invokes 'git -C commit status' commit)"

test_case "a different subcommand does not match (git push is not commit)"
assert_eq no "$(invokes 'git push origin main' commit)"

test_case "a token after a non-git head does not arm (echo push)"
assert_eq no "$(invokes 'echo push origin main' push)"

test_case "empty command matches nothing"
assert_eq no "$(invokes '' push)"

# --- arglines: per-segment argument extraction --------------------------------------
test_case "arg tokens of the matched segment are emitted"
assert_eq 'origin main' "$(arglines 'git push origin main' push)"

test_case "global options are not part of the argline"
assert_eq 'origin main' "$(arglines 'git -C /repo -c a=b push origin main' push)"

test_case "an argument-less invocation emits an EMPTY line (still one segment)"
assert_eq '<empty>' "$(arglines 'git stash' stash)"

test_case "every matching segment of a compound command emits its own line"
assert_eq 'origin main/origin feat/x' "$(arglines 'git push origin main && git push origin feat/x' push)"

test_case "a non-matching segment between matches is not merged in"
assert_eq 'a.ts/b.ts' "$(arglines 'git add a.ts && echo done && git add b.ts' add)"

test_case "tokens after a separator are not read into the previous argline"
assert_eq 'origin main' "$(arglines 'git push origin main && echo feat/x' push)"

test_case "segment boundary without spaces still splits (;)"
assert_eq '<empty>/<empty>' "$(arglines 'git stash;git stash' stash)"

test_case "no matching segment emits nothing at all"
assert_eq '' "$(arglines 'git status && npm test' push)"

# --- fork ゼロ化 (Windows 高速化) の等価性ピン ---------------------------------------
# 正規化を sed から純 bash に、存在判定を `| grep -q ''` からカウンタに変える。
# 出力契約は不変 — ここは「壊すと差が出る入力」で新旧の等価性を固定する。

test_case "&&& は && と & に割れる (sed の leftmost-longest と同じ)"
assert_eq yes "$(invokes 'git add -A&&&git commit -a' add)"

test_case "||| は || と | に割れる"
assert_eq yes "$(invokes 'true|||git push origin main' push)"

test_case "separator 密着 (a&&git commit) でも検出する"
assert_eq yes "$(invokes 'echo x&&git commit -m y' commit)"

test_case "backtick 密着でも検出する"
assert_eq yes "$(invokes 'echo `git push origin main`' push)"

test_case "制御文字 \\x01 が混ざっても検出は壊れない (sentinel fallback)"
assert_eq yes "$(invokes "echo $(printf '\001') && git push origin main" push)"

test_case "cmd_invokes_git_subcommand は stdout に何も出さない (dispatcher 1 プロセス化の前提)"
out="$(cmd_invokes_git_subcommand 'git push origin main' push)"
assert_eq '' "$out"

test_case "git を含まない command は即 no (純 builtin 事前ガード — 検出集合は不変)"
assert_eq no "$(invokes 'npm test && ls -la' push)"

finish

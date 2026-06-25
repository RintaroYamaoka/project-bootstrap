#!/usr/bin/env bash
# Tests for hooks/block-stale-write-to-protected.sh
#
# Incident class (lives only as comments in lib/repo-drift.sh until this gate): a `git push`
# to the TRUNK from a STALE checkout — a tree N commits behind the remote trunk — runs and
# either deploys old logic (2026-06-16 prod migration from a 24-behind tree) or drops a
# commit (rebase-drops-deploy from a stale main push). status clean ≠ on latest trunk.
#
# The gate is ORTHOGONAL to block-push-to-protected (which enforces PR-FLOW via opt-in
# .bootstrap-protected): this one enforces FRESHNESS of an otherwise-ALLOWED trunk push,
# keyed on the trunk that lib/repo-drift.sh's drift_main_ref resolves (origin/main -> main),
# NOT .bootstrap-protected. So it must fire on a repo with NO .bootstrap-protected (this
# plugin's own direct-trunk release flow) AND must NOT fire on a non-trunk push.
#
# Fail-mode under test: parse-impossible = fail-CLOSED (exit 2). fail-OPEN (exit 0) on:
# non-push, trunk push that is FRESH (behind 0), non-trunk push, fetch failure (offline),
# and no resolvable trunk ref. Block (exit 2) ONLY when: trunk push + fetch ok + behind>0.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"

git config --global user.email >/dev/null 2>&1 || git config --global user.email "test@example.com"
git config --global user.name  >/dev/null 2>&1 || git config --global user.name  "test"

# mkpair — a "remote" repo + a "local" clone whose origin/HEAD is set (so drift_main_ref
# resolves origin/main -> main). Echoes "<local> <remote>". No network: fetch over a path.
mkpair() {
  local rem loc
  rem="$(mktemp -d)/remote"
  git init -q -b main "$rem"
  git -C "$rem" -c user.email=t@e.x -c user.name=t commit -q --allow-empty -m c0
  loc="$(mktemp -d)/local"
  git clone -q "$rem" "$loc" 2>/dev/null
  printf '%s %s' "$loc" "$rem"
}
# advance the REMOTE main by N commits so the local clone goes stale after a fetch.
advance_remote() {
  local rem="$1" n="$2" i
  for ((i = 0; i < n; i++)); do
    git -C "$rem" -c user.email=t@e.x -c user.name=t commit -q --allow-empty -m "r$i"
  done
}
push_input() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' "$1" "$RUN_DIR"; }

# --- block: trunk push from a stale checkout -----------------------------------------
read -r LOC REM <<<"$(mkpair)"
advance_remote "$REM" 4
RUN_DIR="$LOC"
test_case "explicit push to trunk while 4 behind → blocked (exit 2)"
run_hook block-stale-write-to-protected.sh "$(push_input 'git push origin main')"
assert_exit 2
test_case "...and the message names the divergence + a fetch/rebase remedy"
assert_stderr_contains "4"
assert_stderr_contains "git fetch"

test_case "plain push (implicit current branch == trunk) while behind → blocked"
run_hook block-stale-write-to-protected.sh "$(push_input 'git push')"
assert_exit 2

test_case "HEAD:main refspec to trunk while behind → blocked"
run_hook block-stale-write-to-protected.sh "$(push_input 'git push origin HEAD:main')"
assert_exit 2

# compound command: a stale trunk push hidden after another git push must still be caught.
test_case "compound: trunk push after a feature push is still caught"
run_hook block-stale-write-to-protected.sh "$(push_input 'git push origin feat/x && git push origin main')"
assert_exit 2

# --- fail-open: FRESH trunk push (behind 0) ------------------------------------------
read -r LOC2 REM2 <<<"$(mkpair)"
RUN_DIR="$LOC2"
test_case "trunk push while up-to-date (behind 0) → fail-open exit 0"
run_hook block-stale-write-to-protected.sh "$(push_input 'git push origin main')"
assert_exit 0

# --- fail-open: non-trunk destination ------------------------------------------------
read -r LOC3 REM3 <<<"$(mkpair)"
advance_remote "$REM3" 4   # local IS stale, but the push is NOT to the trunk
RUN_DIR="$LOC3"
git -C "$LOC3" checkout -q -B feat/x
test_case "stale checkout but push targets a feature branch → fail-open exit 0"
run_hook block-stale-write-to-protected.sh "$(push_input 'git push origin feat/x')"
assert_exit 0
test_case "...plain push while on a non-trunk branch → fail-open exit 0"
run_hook block-stale-write-to-protected.sh "$(push_input 'git push')"
assert_exit 0

# --- fail-open: fetch failure (offline / no remote) ----------------------------------
read -r LOC4 REM4 <<<"$(mkpair)"
advance_remote "$REM4" 4
git -C "$LOC4" remote set-url origin "$(mktemp -d)/gone-xyz"   # fetch can never succeed
RUN_DIR="$LOC4"
test_case "trunk push but fetch fails (offline) → fail-open exit 0 (work never blocked)"
run_hook block-stale-write-to-protected.sh "$(push_input 'git push origin main')"
assert_exit 0

# --- fail-open: no resolvable trunk ref ----------------------------------------------
NOREMOTE="$(mktemp -d)/solo"
git init -q -b main "$NOREMOTE"
git -C "$NOREMOTE" -c user.email=t@e.x -c user.name=t commit -q --allow-empty -m c0
RUN_DIR="$NOREMOTE"
test_case "no remote-tracking trunk ref → fail-open exit 0"
run_hook block-stale-write-to-protected.sh "$(push_input 'git push origin main')"
assert_exit 0

# --- fail-open: not a git push -------------------------------------------------------
read -r LOC5 REM5 <<<"$(mkpair)"
advance_remote "$REM5" 4
RUN_DIR="$LOC5"
test_case "non-push git command → fail-open exit 0"
run_hook block-stale-write-to-protected.sh "$(push_input 'git status')"
assert_exit 0
test_case "non-git command → fail-open exit 0"
run_hook block-stale-write-to-protected.sh "$(push_input 'ls -la')"
assert_exit 0

# --- fail-closed: unparseable hook input ---------------------------------------------
test_case "no command key in input → fail-closed exit 2 (parse-impossible)"
run_hook block-stale-write-to-protected.sh '{"tool_name":"Bash","tool_input":{}}'
assert_exit 2

finish

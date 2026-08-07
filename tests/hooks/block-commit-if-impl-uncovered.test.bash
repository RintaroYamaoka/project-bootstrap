#!/usr/bin/env bash
# Tests for hooks/block-commit-if-impl-uncovered.sh
#
# The commit-side half of the coverage question ("is there an ordered contract that says
# this source face may exist?"). Its twin, block-impl-without-wo.sh, is registered on
# Edit|Write|MultiEdit only — so `cat > src/x.ts`, codemods, scaffolders and `cp` never
# pass it. Enumerating write methods is whack-a-mole (ADR 0017), so the second layer sits
# at the one act every write method must pass: `git commit`.
#
# The lane gate cannot stand in for this: `order` derives .bootstrap/lane FROM a WO, so
# with no WO ordered there is no lane marker at all and the lane gate fails open — exactly
# the "started implementing without ordering" state commission exists to stop.
#
# Opt-in: docs/bootstrap/commission/ must exist.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"

HOOK=block-commit-if-impl-uncovered.sh

setup_repo() {
  local tmp; tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  REPO="$(git -C "$tmp" rev-parse --show-toplevel)"
  git -C "$REPO" config user.email t@t.test
  git -C "$REPO" config user.name tester
  RUN_DIR="$REPO"
}
enable_commission() { mkdir -p "$REPO/docs/bootstrap/commission/wo"; }

# write_wo <status> <glob> — only frontmatter status and section 2 matter here;
# completeness is the other gate's question.
write_wo() {
  cat > "$REPO/docs/bootstrap/commission/wo/0007-export.md" <<EOF
---
id: WO-0007
status: ${1:-ordered}
retry_limit: 3
budget_tokens: 200000
---

# WO-0007 — export

## 2. 作業範囲

- \`${2:-src/export/**}\`

## 3. 変更禁止範囲

- 無し
EOF
}

add_file() { mkdir -p "$(dirname "$REPO/$1")"; printf 'x\n' > "$REPO/$1"; }
stage_all() { git -C "$REPO" add -A >/dev/null 2>&1; }
commit_input() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' "${1:-git commit -m x}" "$REPO"; }

# 1. Opt-in absent => never fires (a repo that did not adopt commission is untouched).
setup_repo; add_file src/export/csv.ts; stage_all
test_case "no commission dir: fail-open"
run_hook "$HOOK" "$(commit_input)"
assert_exit 0

# 2. Not a git commit => not our chokepoint.
setup_repo; enable_commission; add_file src/export/csv.ts; stage_all
test_case "non-commit command passes"
run_hook "$HOOK" "$(commit_input "git status")"
assert_exit 0

# 3. THE HOLE THIS CLOSES: a new source file written outside the Edit tool, with no WO.
setup_repo; enable_commission; add_file src/export/csv.ts; stage_all
test_case "a new source file with no ordered WO is blocked at commit"
run_hook "$HOOK" "$(commit_input)"
assert_exit 2
assert_stderr_contains "src/export/csv.ts"

# 4. Covered by an ordered WO => the contract exists, pass.
setup_repo; enable_commission; write_wo ordered 'src/export/**'
add_file src/export/csv.ts; stage_all
test_case "a new source file covered by an ordered WO passes"
run_hook "$HOOK" "$(commit_input)"
assert_exit 0

# 5. An ordered WO whose section 2 does not reach this path is not coverage.
#    Widening scope is a contract change, so it must be recorded, not assumed.
setup_repo; enable_commission; write_wo ordered 'src/report/**'
add_file src/export/csv.ts; stage_all
test_case "an ordered WO that does not cover the path is blocked"
run_hook "$HOOK" "$(commit_input)"
assert_exit 2
assert_stderr_contains "カバーしていない"

# 6. A draft WO is not an order — drafting a scope does not authorize building it.
setup_repo; enable_commission; write_wo draft 'src/export/**'
add_file src/export/csv.ts; stage_all
test_case "a draft WO does not authorize implementation"
run_hook "$HOOK" "$(commit_input)"
assert_exit 2

# 7. Modifying an existing file is not creating a face => bug fixes never trip.
setup_repo; enable_commission
add_file src/export/csv.ts; stage_all; git -C "$REPO" commit -qm base >/dev/null 2>&1
printf 'y\n' >> "$REPO/src/export/csv.ts"; stage_all
test_case "modifying an existing source file is not blocked (bug fix / refactor)"
run_hook "$HOOK" "$(commit_input)"
assert_exit 0

# 8. Non-source faces are not feature faces (shared classifier lib/source-face.sh).
setup_repo; enable_commission
add_file src/export/csv.test.ts; add_file README.md; add_file config.json; stage_all
test_case "new tests / docs / config are not feature faces"
run_hook "$HOOK" "$(commit_input)"
assert_exit 0

# 9. The subsystem's own state face is never blocked — a gate must not stop the write
#    that would clear it (here: authoring the very first WO).
setup_repo; enable_commission
add_file docs/bootstrap/commission/wo/0001-first.md; stage_all
test_case "writing the commission's own artifacts is never blocked"
run_hook "$HOOK" "$(commit_input)"
assert_exit 0

# 10. Integration in progress: a merge commit crosses contracts by definition.
setup_repo; enable_commission
add_file README.md; stage_all; git -C "$REPO" commit -qm base >/dev/null 2>&1
add_file src/export/csv.ts; stage_all
printf '%s\n' "$(git -C "$REPO" rev-parse HEAD)" > "$REPO/.git/MERGE_HEAD"
test_case "a commit during a merge is not blocked (conflict resolution crosses contracts)"
run_hook "$HOOK" "$(commit_input)"
assert_exit 0

# 11. Nothing staged => git itself refuses; no material to judge.
setup_repo; enable_commission
test_case "an empty index is fail-open"
run_hook "$HOOK" "$(commit_input)"
assert_exit 0

# 12. Unparseable hook input => fail-closed, same contract as every other Bash gate.
setup_repo; enable_commission; add_file src/export/csv.ts; stage_all
test_case "unparseable input is fail-closed"
run_hook "$HOOK" '{"tool_name":"Bash","tool_input":{}}'
assert_exit 2

# 13. git global options before the subcommand must still trip it (ADR 0019 tokenizer).
setup_repo; enable_commission; add_file src/export/csv.ts; stage_all
test_case "git global options before the subcommand still trip the gate"
run_hook "$HOOK" "$(commit_input "git -c core.hooksPath=/dev/null commit -m x")"
assert_exit 2

finish

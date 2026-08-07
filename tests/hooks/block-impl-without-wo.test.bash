#!/usr/bin/env bash
# Tests for hooks/block-impl-without-wo.sh
#
# The gate at the moment IMPLEMENTATION starts. Signal choice follows the sprint gate
# (②): the act of creating a NEW source file, not the vocabulary of the prompt.
# Difference from the sprint gate, which fires on the same signal: that one asks
# "did you judge whether this splits into parallel lanes?", this one asks "is there an
# approved work order covering this surface?". Two different judgments, so two gates —
# passing one must not imply the other.
#
# Opt-in: docs/bootstrap/commission/ must exist. Fail-open otherwise.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"

HOOK=block-impl-without-wo.sh

setup_repo() {
  local tmp; tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  REPO="$(git -C "$tmp" rev-parse --show-toplevel)"
  git -C "$REPO" config user.email t@t.test
  git -C "$REPO" config user.name tester
  RUN_DIR="$REPO"
}
enable_commission() { mkdir -p "$REPO/docs/bootstrap/commission/wo"; }

# <file> <status> <scope-glob>
write_wo() {
  local path="$REPO/docs/bootstrap/commission/wo/$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<EOF
---
id: WO-0007
status: $2
branch: feat/x
retry_limit: 3
---

## 2. 作業範囲

- \`$3\`
EOF
}

touch_file() { mkdir -p "$(dirname "$REPO/$1")"; : > "$REPO/$1"; }
write_input() { printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"x"},"cwd":"%s"}' "$REPO/$1" "$REPO"; }

# 1. Opt-in absent => fail-open.
setup_repo
test_case "no commission dir: new source file passes"
run_hook "$HOOK" "$(write_input src/export/csv.ts)"
assert_exit 0

# 2. Adopted, but no WO at all => blocked.
setup_repo; enable_commission
test_case "new source surface with no ordered WO is blocked"
run_hook "$HOOK" "$(write_input src/export/csv.ts)"
assert_exit 2
assert_stderr_contains "WO"

# 3. An ordered WO covering the path => passes.
setup_repo; enable_commission; write_wo 0007-x.md ordered 'src/export/**'
test_case "an ordered WO covering the path passes"
run_hook "$HOOK" "$(write_input src/export/csv.ts)"
assert_exit 0

# 4. A DRAFT WO covering the path does NOT pass — drafting is not ordering.
#    This is the whole point: work may not start until the contract is complete, and
#    completeness is proven at the ordering commit, not by the file merely existing.
setup_repo; enable_commission; write_wo 0007-x.md draft 'src/export/**'
test_case "a draft WO does not authorise implementation"
run_hook "$HOOK" "$(write_input src/export/csv.ts)"
assert_exit 2

# 5. An ordered WO whose scope does NOT cover the path => blocked.
setup_repo; enable_commission; write_wo 0007-x.md ordered 'src/report/**'
test_case "an ordered WO for a different surface does not authorise this one"
run_hook "$HOOK" "$(write_input src/export/csv.ts)"
assert_exit 2

# 6. Editing an EXISTING file is not "starting new feature surface" => fail-open.
#    Bug fixes and refactors must never trip this.
setup_repo; enable_commission; touch_file src/export/csv.ts
test_case "editing an existing file passes"
run_hook "$HOOK" "$(write_input src/export/csv.ts)"
assert_exit 0

# 7. Tests / docs / config are not source faces => fail-open (shared source-face.sh).
setup_repo; enable_commission
test_case "a new test file passes"
run_hook "$HOOK" "$(write_input src/export/csv.test.ts)"
assert_exit 0
test_case "a new markdown file passes"
run_hook "$HOOK" "$(write_input docs/notes.md)"
assert_exit 0

# 8. The subsystem's own state must never be blocked by its own gate — otherwise the
#    write that would clear the gate is the write the gate stops.
setup_repo; enable_commission
test_case "writing into docs/bootstrap/commission/ passes"
run_hook "$HOOK" "$(write_input docs/bootstrap/commission/wo/0008-y.md)"
assert_exit 0

# 9. Any ONE ordered WO covering the path is enough (several may be open at once).
setup_repo; enable_commission
write_wo 0007-x.md ordered 'src/report/**'
write_wo 0008-y.md ordered 'src/export/**'
test_case "one covering ordered WO among several is enough"
run_hook "$HOOK" "$(write_input src/export/csv.ts)"
assert_exit 0

# 10. An accepted WO no longer authorises new surface (its work is done).
setup_repo; enable_commission; write_wo 0007-x.md accepted 'src/export/**'
test_case "an accepted WO does not authorise new work"
run_hook "$HOOK" "$(write_input src/export/csv.ts)"
assert_exit 2

finish

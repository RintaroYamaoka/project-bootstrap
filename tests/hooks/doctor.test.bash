#!/usr/bin/env bash
# Tests for scripts/doctor.sh — project-bootstrap 採用状態の self-audit engine.
#
# Why this exists: 規律 gate は消費先 repo でその hook が現行版で走って初めて効く。sprint 発火 gate
# は build 前の分解判断ゆえ CI 後追いができず PreToolUse hook 以外に backstop が無い (ADR 0002)。
# よって「採用したのに gate が届いていない (partial)」「採用も提案もされない (unadopted)」状態が
# 無音で成立すると誰も止められない (実際に起きた: docs/incidents/2026-06-02-coverage-drift-silent)。
# doctor はその状態を 1 つの verdict (skip/unadopted/declined/partial/ok) に判定する。

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"

SCRIPTS_DIR="$(cd "$DIR/../../scripts" && pwd)"

DOCTOR_EXIT=0
DOCTOR_OUT=""
DOCTOR_STATUS=""

run_doctor() {
  local repo="$1"
  local outf; outf="$(mktemp)"
  bash "$SCRIPTS_DIR/doctor.sh" "$repo" >"$outf" 2>&1
  DOCTOR_EXIT=$?
  DOCTOR_OUT="$(cat "$outf")"
  DOCTOR_STATUS="$(printf '%s\n' "$DOCTOR_OUT" | head -1 | sed 's/^STATUS:[[:space:]]*//')"
  rm -f "$outf"
}

setup_repo() {
  local tmp; tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  REPO="$(git -C "$tmp" rev-parse --show-toplevel)"
  git -C "$REPO" config user.email t@t.test
  git -C "$REPO" config user.name tester
}
assert_doctor_status() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$DOCTOR_STATUS" = "$1" ]; then
    echo "  ok   [$CURRENT_TEST] status $1"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL [$CURRENT_TEST] expected status $1, got '$DOCTOR_STATUS'"
    printf '    out: %s\n' "$(printf '%s' "$DOCTOR_OUT" | head -3)"
  fi
}
assert_doctor_exit() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$DOCTOR_EXIT" = "$1" ]; then
    echo "  ok   [$CURRENT_TEST] exit $1"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL [$CURRENT_TEST] expected exit $1, got $DOCTOR_EXIT"
  fi
}
assert_out_contains() {
  TESTS_RUN=$((TESTS_RUN + 1))
  case "$DOCTOR_OUT" in
    *"$1"*) echo "  ok   [$CURRENT_TEST] out contains '$1'" ;;
    *) TESTS_FAILED=$((TESTS_FAILED + 1)); echo "  FAIL [$CURRENT_TEST] out missing '$1'" ;;
  esac
}

# vendor の最低 core セット (sprint なし) を .claude/hooks/ に置く。
vendor_core() {
  mkdir -p "$REPO/.claude/hooks"
  for h in require-test-companion.sh block-commit-if-tests-fail.sh block-add-all.sh \
           block-dangerous-git-ops.sh block-cross-claude-wip.sh; do
    : > "$REPO/.claude/hooks/$h"
  done
}

# 1. 非 git → skip (fail-open)。
NOGIT="$(mktemp -d)"
test_case "non-git dir is skip"
run_doctor "$NOGIT"
assert_doctor_status skip
assert_doctor_exit 0

# 2. marker 皆無 → unadopted (導入提案の余地)。
setup_repo
test_case "no markers is unadopted"
run_doctor "$REPO"
assert_doctor_status unadopted
assert_doctor_exit 0
assert_out_contains ".bootstrap-declined"

# 3. unadopted + .bootstrap-declined → declined (nag 抑止)。
setup_repo
: > "$REPO/.bootstrap-declined"
test_case "declined marker suppresses the offer"
run_doctor "$REPO"
assert_doctor_status declined
assert_doctor_exit 0

# 4. docs/sprint 採用・vendoring 無し・整合 → ok。
setup_repo
mkdir -p "$REPO/docs/sprint"
test_case "sprint adopted via plugin (no vendoring) is ok"
run_doctor "$REPO"
assert_doctor_status ok
assert_doctor_exit 0

# 5. .bootstrap-arch に layer 行あり → ok。
setup_repo
printf 'layer core = core/**\nallow core ->\n' > "$REPO/.bootstrap-arch"
test_case "arch with a layer directive is ok"
run_doctor "$REPO"
assert_doctor_status ok

# 6. .bootstrap-arch は在るが layer 行なし → partial (宣言だけで no-op)。
setup_repo
printf '# comment only, no directives\n' > "$REPO/.bootstrap-arch"
test_case "arch declared but empty is partial"
run_doctor "$REPO"
assert_doctor_status partial
assert_doctor_exit 2

# 7. .bootstrap-protected がコメントのみ → partial (push 保護が no-op)。
setup_repo
printf '# only comments\n#main\n' > "$REPO/.bootstrap-protected"
test_case "protected with only comments is partial"
run_doctor "$REPO"
assert_doctor_status partial

# 8. vendored-coverage gap (本 incident の中核): sprint 採用 + .claude/hooks に core だけ
#    (sprint gate が欠落) → partial。propagate-ai 型の silent 穴。
setup_repo
mkdir -p "$REPO/docs/sprint"
vendor_core
test_case "vendored hooks missing the sprint gate is partial"
run_doctor "$REPO"
assert_doctor_status partial
assert_doctor_exit 2
assert_out_contains "block-unplanned-feature-build.sh"

# 8b. sprint 採用 + 旧 sprint hook 2 本は在るが review gate (block-unreviewed-merge) が
#     欠落 → partial。レビュー precondition も sprint flow の採用機能 (= 配備漏れは silent)。
setup_repo
mkdir -p "$REPO/docs/sprint"
vendor_core
: > "$REPO/.claude/hooks/block-unplanned-feature-build.sh"
: > "$REPO/.claude/hooks/block-out-of-lane-edit.sh"
test_case "vendoring missing the review gate is partial"
run_doctor "$REPO"
assert_doctor_status partial
assert_out_contains "block-unreviewed-merge.sh"

# 9. vendored だが sprint 採用に必要な hook も揃っている → ok。
setup_repo
mkdir -p "$REPO/docs/sprint"
vendor_core
: > "$REPO/.claude/hooks/block-unplanned-feature-build.sh"
: > "$REPO/.claude/hooks/block-out-of-lane-edit.sh"
: > "$REPO/.claude/hooks/block-uniso-main-edit.sh"
: > "$REPO/.claude/hooks/block-unreviewed-merge.sh"
: > "$REPO/.claude/hooks/block-over-wip-parallel.sh"
test_case "complete vendoring for adopted features is ok"
run_doctor "$REPO"
assert_doctor_status ok
assert_doctor_exit 0

# 10. docs/decisions だけでも採用とみなす (external memory marker)。
setup_repo
mkdir -p "$REPO/docs/decisions"
test_case "docs/decisions alone counts as adopted"
run_doctor "$REPO"
assert_doctor_status ok

# 11. .bootstrap-wip が在るのに整数が読めない → partial (宣言したのに無音で無視される class)。
#     hook 側 (resolve-wip-limit.sh) は表示なので fail-open に既定へ落ちるが、その「落ちた」事実
#     は宣言者に届かない — doctor がここで可視化する。
setup_repo
mkdir -p "$REPO/docs/sprint"
printf 'four lanes\n' > "$REPO/.bootstrap-wip"
test_case "unparseable .bootstrap-wip is partial"
run_doctor "$REPO"
assert_doctor_status partial
assert_doctor_exit 2
assert_out_contains ".bootstrap-wip"

# 12. .bootstrap-wip が整数で読める → ok (警告なし)。
setup_repo
mkdir -p "$REPO/docs/sprint"
printf '4\n' > "$REPO/.bootstrap-wip"
test_case "valid .bootstrap-wip stays ok"
run_doctor "$REPO"
assert_doctor_status ok
assert_doctor_exit 0

# 13. New consolidated layout: an adopted marker under .bootstrap/ is detected, and
#     the same no-op audit fires (here: an empty .bootstrap/arch).
setup_repo
mkdir -p "$REPO/.bootstrap"
printf '# comment only, no directives\n' > "$REPO/.bootstrap/arch"
test_case ".bootstrap/arch (new layout) declared but empty is partial"
run_doctor "$REPO"
assert_doctor_status partial
assert_out_contains ".bootstrap/arch"

# 14. New layout adoption alone (a valid marker) is recognized as adopted → ok.
setup_repo
mkdir -p "$REPO/.bootstrap"
printf 'layer core = core/**\nallow core ->\n' > "$REPO/.bootstrap/arch"
test_case ".bootstrap/arch with a layer directive is ok (new layout adopted)"
run_doctor "$REPO"
assert_doctor_status ok

finish

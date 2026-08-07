#!/usr/bin/env bash
# Tests for hooks/block-commit-if-wo-incomplete.sh
#
# The gate at the moment of ORDERING. Committing a WO whose frontmatter says
# `status: ordered` IS the act of handing work to an autonomous agent, so that commit
# is where the contract's completeness has to be proven.
#
# Why commit-time and not edit-time (same reasoning as ADR 0021 / ADR 0018): at
# PreToolUse the gate cannot see the resulting file — an Edit carries only a fragment,
# and the status flip may arrive in a different edit from the section it invalidates.
# The commit is the first point where the whole artifact exists and is the thing that
# actually publishes it. It also catches writes made through sed/scripts (ADR 0017).
#
# Opt-in: docs/bootstrap/commission/ must exist, mirroring docs/bootstrap/sprint/.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/helper.bash"

HOOK=block-commit-if-wo-incomplete.sh

setup_repo() {
  local tmp; tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  REPO="$(git -C "$tmp" rev-parse --show-toplevel)"
  git -C "$REPO" config user.email t@t.test
  git -C "$REPO" config user.name tester
  RUN_DIR="$REPO"
}
enable_commission() { mkdir -p "$REPO/docs/bootstrap/commission/wo"; }

# A complete, orderable WO. Callers mutate it to build the negative cases.
write_wo() {
  local path="$REPO/docs/bootstrap/commission/wo/${1:-0007-add-export.md}" status="${2:-ordered}"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<EOF
---
id: WO-0007
slug: add-export
status: $status
branch: feat/add-export
retry_limit: 3
budget_tokens: 200000
opened: 2026-08-01
ordered: 2026-08-02
accepted:
escalations: 0
rejections: 0
---

# WO-0007 — CSV エクスポートを足す

## 1. 目的

取り出す口が無い。

## 2. 作業範囲

- \`src/export/**\`

## 3. 変更禁止範囲

- \`src/core/contract.ts\` — 外部契約

## 4. 守るべき既存条件

- charter.md の「制約」

## 5. 優先順位

後方互換 > 速度

## 6. 例外時の判断方法

握り潰さず失敗させる。

## 7. 継ぎ目

- \`Repository.load(id)\` — \`src/infra/repository.ts:42\`

## 8. 完了条件 (DoD)

- [ ] D1: CSV が落ちてくる

## 9. 検証方法

- D1: \`tests/export.test.ts\`

## 10. 停止条件

- **再試行上限**: frontmatter に従う
- **予算上限**: frontmatter に従う
- **エスカレーション条件**: 契約を変えないと DoD を満たせないとき

## 11. 決めてよいこと / 決めてはいけないこと

**決めてよいこと**: 列の並び

**決めてはいけないこと**: 契約の形

## 12. 事前レビュー

| # | 観点 | 指摘 | 状態 |
|---|---|---|---|
| 1 | 曖昧さ | 範囲が二通り読める | closed |
EOF
  WO_PATH="$path"
}

write_charter() {
  cat > "$REPO/docs/bootstrap/commission/charter.md" <<EOF
## 未決台帳

| ID | 論点 | 状態 |
|---|---|---|
| U1 | 決まっていないこと | OPEN |
| U2 | 決まったこと | CLOSED |
EOF
}

stage_all() { git -C "$REPO" add -A >/dev/null 2>&1; }
commit_input() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' "${1:-git commit -m x}" "$REPO"; }

# 1. Opt-in absent => never fires.
setup_repo
write_wo; sed -i 's/^status: ordered/status: draft/' "$WO_PATH"
stage_all
test_case "no commission dir: fail-open"
run_hook "$HOOK" "$(commit_input)"
assert_exit 0

# 2. Not a git commit => not our chokepoint.
setup_repo; enable_commission; write_wo; stage_all
test_case "non-commit command passes"
run_hook "$HOOK" "$(commit_input "git status")"
assert_exit 0

# 3. A complete ordered WO commits fine.
setup_repo; enable_commission; write_wo; stage_all
test_case "complete ordered WO passes"
run_hook "$HOOK" "$(commit_input)"
assert_exit 0

# 4. A draft WO is not being ordered => the gate must not block authoring.
#    Drafting is where the thinking happens; blocking it would push authors to fill
#    sections with noise just to save a checkpoint.
setup_repo; enable_commission; write_wo 0007-add-export.md draft
sed -i 's/^後方互換 > 速度$/<優先順位>/' "$WO_PATH"
stage_all
test_case "incomplete DRAFT WO passes (only ordering is gated)"
run_hook "$HOOK" "$(commit_input)"
assert_exit 0

# 5. Ordered WO with an unfilled section => blocked, and the section is named.
setup_repo; enable_commission; write_wo
sed -i 's/^後方互換 > 速度$/<優先順位>/' "$WO_PATH"
stage_all
test_case "ordered WO with an unfilled section is blocked"
run_hook "$HOOK" "$(commit_input)"
assert_exit 2
assert_stderr_contains "5"

# 6. DoD without an oracle => blocked (the 検算 identity).
setup_repo; enable_commission; write_wo
sed -i 's/^- D1: .*$//' "$WO_PATH"
stage_all
test_case "a DoD row with no verification oracle is blocked"
run_hook "$HOOK" "$(commit_input)"
assert_exit 2
assert_stderr_contains "D1"

# 7. Pre-review row still open => blocked.
setup_repo; enable_commission; write_wo
sed -i 's/| closed |/| open |/' "$WO_PATH"
stage_all
test_case "an unresolved pre-review finding is blocked"
run_hook "$HOOK" "$(commit_input)"
assert_exit 2
assert_stderr_contains "事前レビュー"

# 8. Pre-review table with zero rows => blocked (never reviewed is not the same as clean).
setup_repo; enable_commission; write_wo
sed -i '/^| 1 | 曖昧さ/d' "$WO_PATH"
stage_all
test_case "an empty pre-review table is blocked (un-reviewed != clean)"
run_hook "$HOOK" "$(commit_input)"
assert_exit 2

# 9. Depends on an OPEN unknown => blocked. This is the one invariant inherited
#    unchanged from both predecessors: an unresolved question must never be filled in
#    silently, and ordering work that rests on one does exactly that.
setup_repo; enable_commission; write_wo; write_charter
sed -i 's|^- charter.md の「制約」$|- charter.md の「制約」・未決 U1 に依存|' "$WO_PATH"
stage_all
test_case "ordering on an OPEN unknown is blocked"
run_hook "$HOOK" "$(commit_input)"
assert_exit 2
assert_stderr_contains "U1"

# 10. Depends on a CLOSED unknown => fine.
setup_repo; enable_commission; write_wo; write_charter
sed -i 's|^- charter.md の「制約」$|- charter.md の「制約」・未決 U2 で決着|' "$WO_PATH"
stage_all
test_case "a resolved unknown does not block"
run_hook "$HOOK" "$(commit_input)"
assert_exit 0

# 11. retry_limit must be a positive integer — the stop condition's numeric half.
setup_repo; enable_commission; write_wo
sed -i 's/^retry_limit: 3/retry_limit: /' "$WO_PATH"
stage_all
test_case "missing retry_limit is blocked"
run_hook "$HOOK" "$(commit_input)"
assert_exit 2
assert_stderr_contains "retry_limit"

# 12. A WO not carried by this commit is not this commit's problem (ADR 0018:
#     the signal is what this commit carries, not the state of the tree).
setup_repo; enable_commission; write_wo
sed -i 's/^後方互換 > 速度$/<優先順位>/' "$WO_PATH"
printf 'x\n' > "$REPO/other.txt"
git -C "$REPO" add other.txt >/dev/null 2>&1
test_case "an unstaged incomplete WO does not block an unrelated commit"
run_hook "$HOOK" "$(commit_input)"
assert_exit 0

# 13. The content judged must be the version THIS COMMIT CARRIES, not the working tree.
#     Staging a broken WO and then fixing it on disk without re-staging used to pass:
#     the file list came from the index while the content came from disk.
setup_repo; enable_commission; write_wo
sed -i 's/^後方互換 > 速度$/<優先順位>/' "$WO_PATH"   # broken…
stage_all                                            # …and that broken version is staged
sed -i 's/^<優先順位>$/後方互換 > 速度/' "$WO_PATH"   # fixed on disk only
test_case "the STAGED version is judged, not the working tree (partial-stage fail-open)"
run_hook "$HOOK" "$(commit_input)"
assert_exit 2
assert_stderr_contains "5"

# 14. …and the mirror case: `-a` sweeps the working tree, so there the working tree IS
#     what gets committed.
setup_repo; enable_commission; write_wo
stage_all; git -C "$REPO" commit -qm base >/dev/null 2>&1
sed -i 's/^後方互換 > 速度$/<優先順位>/' "$WO_PATH"   # broken on disk, unstaged
test_case "commit -a judges the working tree (that is what -a stages)"
run_hook "$HOOK" "$(commit_input "git commit -am x")"
assert_exit 2

# 15. `deferred:<id>` must name a gap that actually exists in the ledger. Judging only the
#     SHAPE of the cell let `deferred:U99` pass — an unnamed deferral wearing a name.
setup_repo; enable_commission; write_wo; write_charter
sed -i 's/| 1 | 曖昧さ | 範囲が二通り読める | closed |/| 1 | 曖昧さ | 範囲が二通り読める | deferred:U99 |/' "$WO_PATH"
stage_all
test_case "deferring to an unknown id that is not in the ledger is blocked"
run_hook "$HOOK" "$(commit_input)"
assert_exit 2
assert_stderr_contains "U99"

# 16. Deferring to a real (still OPEN) ledger entry is the designed path — it must pass.
#     `deferred` is how a WO ships WITH a named gap; only section 4 dependence on an OPEN
#     unknown is fatal.
setup_repo; enable_commission; write_wo; write_charter
sed -i 's/| 1 | 曖昧さ | 範囲が二通り読める | closed |/| 1 | 曖昧さ | 範囲が二通り読める | deferred:U1 |/' "$WO_PATH"
stage_all
test_case "deferring to a real OPEN ledger entry passes (that is the designed exit)"
run_hook "$HOOK" "$(commit_input)"
assert_exit 0

# 17. A section-4 reference to an id nobody wrote down is also a phantom.
setup_repo; enable_commission; write_wo; write_charter
sed -i 's|^- charter.md の「制約」$|- charter.md の「制約」・未決 U42 に依存|' "$WO_PATH"
stage_all
test_case "depending on an unknown id absent from the ledger is blocked"
run_hook "$HOOK" "$(commit_input)"
assert_exit 2
assert_stderr_contains "U42"

# 18. No charter at all + a WO that cites unknown ids => the ledger check has no material.
#     Silently skipping it would leave the gate looking armed while the invariant it exists
#     for (未決を無音で埋めない) is unenforced.
setup_repo; enable_commission; write_wo
sed -i 's|^- charter.md の「制約」$|- 未決 U1 に依存|' "$WO_PATH"
stage_all
test_case "citing an unknown with no charter.md present is blocked (not silently skipped)"
run_hook "$HOOK" "$(commit_input)"
assert_exit 2
assert_stderr_contains "charter.md"

# 19. A WO that cites no unknown ids does not need a charter at all.
setup_repo; enable_commission; write_wo; stage_all
test_case "a WO citing no unknowns needs no charter"
run_hook "$HOOK" "$(commit_input)"
assert_exit 0

# 20. `git -C <path> commit` must be detected (ADR 0019 tokenizer, not a regex).
setup_repo; enable_commission; write_wo
sed -i 's/^後方互換 > 速度$/<優先順位>/' "$WO_PATH"
stage_all
test_case "git global options before the subcommand still trip the gate"
run_hook "$HOOK" "$(commit_input "git -c core.hooksPath=/dev/null commit -m x")"
assert_exit 2

finish

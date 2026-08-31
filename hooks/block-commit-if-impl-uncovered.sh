#!/usr/bin/env bash
# Hook — PreToolUse on Bash for `git commit`
# 被覆 (= 発注済みの契約に覆われた作業か) の **commit 側の関所**。
#
# なぜ要るか (ADR 0017 と同型の理由): 対になる編集時 gate `block-impl-without-wo.sh` は
# `Edit|Write|MultiEdit` にしか登録されていない。つまり被覆の判定は「Claude が Edit ツールで
# 書いたとき」しか効かず、**Bash 経由の書き込みは関所を一度も通らない**:
#   `cat > src/x.ts` / `>` redirect / codemod / scaffolder (`npx create-*`) / `cp` / `sed` …
# 書き込み方式を列挙して塞ぐのは whack-a-mole なので、**全ての書き込み方式が必ず通る行為 =
# commit** に二層目を置く。lane 強制が Hook G / Hook T の二層になっているのと同じ構成。
#
# lane gate では代替できない: `order` skill は WO の 2 節から `.bootstrap/lane` を作るので、
# **WO を 1 枚も発注していない状態では lane marker 自体が無く**、lane 関所は fail-open する。
# 「発注しないまま実装を始めた」という、まさに commission が止めたい状態が素通りしていた。
#
# 問いの分担 (1 つの記録が 2 つの判断の証拠を兼ねてはいけない):
#   block-commit-if-wo-incomplete.sh  「発注しようとしている契約は完全か」 (完全性)
#   この gate                          「この新規 source 面を作ってよい契約は在るか」 (被覆)
#
# fail-mode:
#   - 根拠不在 = fail-open。非 git / 非 commit / docs/bootstrap/commission 未採用 / index が空 /
#     統合操作中 (merge/rebase/cherry-pick/revert — 定義上 lane も契約も跨ぐ) /
#     既存 file の変更・削除 / test・config・doc / 非 source 拡張子 → 素通し。
#     **bug fix / refactor は一切 trip しない** (見るのは追加 (A) された file だけ)。
#   - 解析不能 = fail-closed (parse_command 失敗時)。
#
# opt-in: docs/bootstrap/commission/ が在るときだけ発火。jq 非依存。

set -u

# shellcheck source=lib/parse-command.sh
. "${BASH_SOURCE[0]%/*}/lib/parse-command.sh"
# shellcheck source=lib/git-invocation.sh
. "${BASH_SOURCE[0]%/*}/lib/git-invocation.sh"
# shellcheck source=lib/resolve-docs.sh
. "${BASH_SOURCE[0]%/*}/lib/resolve-docs.sh"
# shellcheck source=lib/commit-files.sh
. "${BASH_SOURCE[0]%/*}/lib/commit-files.sh"
# 「source 面とは何か」は共有エンジン (編集時 gate・sprint gate・guard 2 と単一権威)。
# shellcheck source=lib/source-face.sh
. "${BASH_SOURCE[0]%/*}/lib/source-face.sh"
# shellcheck source=lib/wo.sh
. "${BASH_SOURCE[0]%/*}/lib/wo.sh"
# shellcheck source=lib/repo-top.sh
. "${BASH_SOURCE[0]%/*}/lib/repo-top.sh"

# gate 本体 — 契約は lib/standalone.sh ヘッダ参照 (global CMD を読む / return 0=pass, 2=block)。
gate_block_commit_if_impl_uncovered() {
  local TOP CDIR CREL ADDED ORDERED_WOS wo UNCOVERED rel covered REASON

# git commit でなければ素通し (検出は単一権威 lib/git-invocation.sh、ADR 0019)。
cmd_invokes_git_subcommand "$CMD" commit || return 0

repo_top_var
TOP="$REPO_TOP"
[ -z "$TOP" ] && return 0

CDIR="$(resolve_docs_dir "$TOP" commission)"
CREL="$(resolve_docs_label "$TOP" commission)"
[ -d "$CDIR" ] || return 0   # 未採用 → 無音で素通し

# 統合操作中は通す (lane の commit 関所と同じ扱い。merge commit は定義上 1 枚の契約を跨ぐ)。
if git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 \
   || git rev-parse -q --verify CHERRY_PICK_HEAD >/dev/null 2>&1 \
   || git rev-parse -q --verify REVERT_HEAD >/dev/null 2>&1 \
   || [ -d "$(git rev-parse --git-path rebase-merge 2>/dev/null)" ] \
   || [ -d "$(git rev-parse --git-path rebase-apply 2>/dev/null)" ]; then
  return 0
fi

ADDED=$(commit_added_files)
[ -z "$ADDED" ] && return 0   # 新規 file が無い commit → 判断材料が無い、fail-open

# 発注済み WO を集める。**判定に使うのは worktree に在る WO** — 完全性 (= その WO が発注に
# 値するか) は発注 commit の関所が既に証明済みで、ここが問うのは「契約が在るか」だけ。
ORDERED_WOS=()
for wo in "$CDIR"/wo/*.md; do
  [ -f "$wo" ] || continue
  case "$wo" in */TEMPLATE.md) continue ;; esac
  [ "$(wo_frontmatter "$wo" status)" = "ordered" ] || continue
  ORDERED_WOS+=("$wo")
done

UNCOVERED=""
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  docs_state_face "$rel" commission && continue   # 自分の state 面は決して止めない
  is_source_path "$rel" || continue
  covered=0
  for wo in ${ORDERED_WOS+"${ORDERED_WOS[@]}"}; do
    if wo_covers_path "$wo" "$rel"; then covered=1; break; fi
  done
  [ "$covered" = 1 ] || UNCOVERED="${UNCOVERED}  - ${rel}"$'\n'
done <<EOF
$ADDED
EOF

[ -z "$UNCOVERED" ] && return 0

if [ "${#ORDERED_WOS[@]}" = 0 ]; then
  REASON="発注済み (status: ordered) の WO が 1 つも無い。"
else
  REASON="発注済みの WO は ${#ORDERED_WOS[@]} 件あるが、どれも 2 節 (作業範囲) でこれらの path をカバーしていない。"
fi

cat >&2 <<EOF
project-bootstrap: blocking commit — 発注された作業指示書に覆われていない新規 source file が
commit に載っている。

$REASON

契約の外の新規 source 面:
$UNCOVERED
これらは Edit ツールを通らずに作られた可能性が高い (= redirect / codemod / scaffolder /
cp は編集時 gate を素通りする)。編集時 gate block-impl-without-wo.sh との二層構成の、
取りこぼしの網がここ。

対処:
  - 発注していない作業なら: order skill で $CREL/wo/<id>-<slug>.md を起こし、
    2 節にこの path を含む glob を書いて発注し直す (pre-review → status: ordered)
  - 既に発注済みなのに 2 節の glob が狭いだけなら: WO の 2 節を直して発注し直す
    (範囲の拡大は契約の変更なので、黙って広げず記録に残す)
  - そもそも取り込むべきでない file なら: git restore --staged -- <file>
EOF
return 2
}

# 単体起動 (tests / vendoring 消費者) — dispatcher からは source されるので走らない。
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  # shellcheck source=lib/standalone.sh
  . "${BASH_SOURCE[0]%/*}/lib/standalone.sh"
  bootstrap_standalone_bash_gate gate_block_commit_if_impl_uncovered
fi

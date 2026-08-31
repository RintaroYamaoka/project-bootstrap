#!/usr/bin/env bash
# Hook — PreToolUse on Bash for `git commit`
# lane 強制の **commit 側の関所**。
#
# なぜ要るか (marketing-app 2026-07-09 incident M5):
#   block-out-of-lane-edit.sh は `Edit|Write|MultiEdit` にしか登録されていない。つまり lane 強制は
#   「Claude が Edit ツールで書いたとき」しか効かず、**Bash 経由の書き込みは関所を一度も通らない**:
#     biome format --write / prettier --write / sed -i / codemod / python / `>` redirect / patch …
#   実際 L2 は `biome format --write` で lane 外の file を書き換え、どの hook も鳴らなかった。
#
# 特定の書き込み方式 (--write, -i, リダイレクト …) を列挙して塞ぐのは whack-a-mole で、新しい
# 方式が出るたびに穴が空く。**全ての書き込み方式が必ず通る行為 = commit** に関所を置く
# (= 「関所は特定方式の痕跡でなく、全方式が必ず通る行為に置く」)。編集時 hook は速い feedback の
# ため残し、本 hook を取りこぼしの網とする二層構成。
#
# 判定: lane worktree で commit するとき、**index に載る file が全て lane glob の中**であること。
# lane 宣言が無ければ fail-open (= sprint 非適用の通常作業は一切妨げない)。
# 統合操作中 (merge/rebase/cherry-pick/revert) は lead の conflict 解決なので通す。

set -u

# git commit 検出は単一権威 lib/git-invocation.sh (path-prefixed git /
# git グローバルオプション形も捕まえる — 旧 regex はどちらも素通りさせた。ADR 0019)。
# shellcheck source=lib/parse-command.sh
. "${BASH_SOURCE[0]%/*}/lib/parse-command.sh"
# shellcheck source=lib/git-invocation.sh
. "${BASH_SOURCE[0]%/*}/lib/git-invocation.sh"
# shellcheck source=lib/resolve-marker.sh
. "${BASH_SOURCE[0]%/*}/lib/resolve-marker.sh"
# shellcheck source=lib/commit-files.sh
. "${BASH_SOURCE[0]%/*}/lib/commit-files.sh"
# shellcheck source=lib/lane-match.sh
. "${BASH_SOURCE[0]%/*}/lib/lane-match.sh"
# shellcheck source=lib/repo-top.sh
. "${BASH_SOURCE[0]%/*}/lib/repo-top.sh"

# gate 本体 — 契約は lib/standalone.sh ヘッダ参照 (global CMD を読む / return 0=pass, 2=block)。
gate_block_out_of_lane_commit() {
  local TOP LANE STAGED OFFENDERS rel LANES

cmd_invokes_git_subcommand "$CMD" commit || return 0

repo_top_var
TOP="$REPO_TOP"
[ -z "$TOP" ] && return 0

# lane 宣言が無ければ sprint 非適用 → 素通し
LANE="$(resolve_marker "$TOP" lane)"
[ -f "$LANE" ] || return 0

# 統合操作中 (lead が conflict を解決している) なら通す。merge commit は定義上 lane を跨ぐ。
if git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 \
   || git rev-parse -q --verify CHERRY_PICK_HEAD >/dev/null 2>&1 \
   || git rev-parse -q --verify REVERT_HEAD >/dev/null 2>&1 \
   || [ -d "$(git rev-parse --git-path rebase-merge 2>/dev/null)" ] \
   || [ -d "$(git rev-parse --git-path rebase-apply 2>/dev/null)" ]; then
  return 0
fi

# commit に載る file を集める (lint 関所と単一権威。`-a` の扱いが drift しないように)。
STAGED=$(commit_files_from_cmd "$CMD")

# 空 (= stage 済みが無い) なら git 自身が拒否する → 判断材料が無い、fail-open。
[ -z "$STAGED" ] && return 0

OFFENDERS=""
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  lane_allows "$rel" "$LANE" || OFFENDERS="${OFFENDERS}  - ${rel}"$'\n'
done <<EOF
$STAGED
EOF

[ -z "$OFFENDERS" ] && return 0

LANES=$(grep -vE '^[[:space:]]*(#|$)' "$LANE" | sed 's/^/  - /')
cat >&2 <<EOF
project-bootstrap: blocking commit — lane の外の file が commit に載っている。

このワーカーが所有する lane (= $LANE):
$LANES

lane 外の file:
$OFFENDERS
これらは Edit ツールを通らずに書き換えられた可能性が高い (= formatter の --write / sed -i /
codemod / redirect は編集時 hook を素通りする)。考えられる原因:
  1. formatter や codemod を lane 外まで走らせた (= 対象を lane glob に絞って再実行する)
  2. 別 task の scope を侵している (= 別ワーカーの担当 file。git restore --staged で戻す)
  3. task 分解時の scope 漏れ (= 本 task の責務なら lane に glob を追記し board.json の scope も同期)

対処:
  - 意図しない変更なら: git restore --staged --worktree -- <file>
  - 正当な scope なら: lane に 1 行追記してから commit し直す
EOF
return 2
}

# 単体起動 (tests / vendoring 消費者) — dispatcher からは source されるので走らない。
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  # shellcheck source=lib/standalone.sh
  . "${BASH_SOURCE[0]%/*}/lib/standalone.sh"
  bootstrap_standalone_bash_gate gate_block_out_of_lane_commit
fi

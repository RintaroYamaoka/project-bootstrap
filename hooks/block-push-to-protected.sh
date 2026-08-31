#!/usr/bin/env bash
# Hook F — PreToolUse on Bash for `git push`
# project が `.bootstrap-protected` で宣言した branch への直接 push を block する。
# feature branch + PR (= integrate skill) 経由に矯正することで、(1) 並走 session が作った
# 混入 commit が共有 branch に lock-in する事故 (実事故: 別 Terminal の staged file 混入
# commit が origin/main へ push された) を defense-in-depth で塞ぎ、(2) sprint flow の
# 「task = feature branch → 統合は integrate skill」を default 化する。
#
# opt-in: `.bootstrap-protected` が無ければ fail-open (= solo / 個人 repo は一切妨げない)。
#   他の並列 hook (.bootstrap-lane / .bootstrap-arch) と同じく project-local 宣言で発火する。
#   ファイルには保護したい branch の glob を 1 行ずつ書く (例: main / master / release/*)。
#
# 検出: push の refspec destination が宣言 branch に一致、または refspec 無し push で
#       現在 branch が宣言 branch に一致するとき exit 2。それ以外は素通し。
#
# bypass: 例外的に直接 push したい場合は /permissions で本 hook を一時 deny。

set -u

# shellcheck source=lib/parse-command.sh
. "${BASH_SOURCE[0]%/*}/lib/parse-command.sh"
# shellcheck source=lib/protected-branch.sh
# Single authority for `git push` detection, refspec-destination enumeration, and the
# protected-branch glob match — shared so the gate cannot drift from the lib (and the lib
# fixes the two LIVE bugs: path-prefixed git was invisible, and a greedy sed inspected
# only the LAST push of a compound command). See lib/protected-branch.sh.
. "${BASH_SOURCE[0]%/*}/lib/protected-branch.sh"
# shellcheck source=lib/resolve-marker.sh
. "${BASH_SOURCE[0]%/*}/lib/resolve-marker.sh"
# shellcheck source=lib/repo-top.sh
. "${BASH_SOURCE[0]%/*}/lib/repo-top.sh"

# gate 本体 — 契約は lib/standalone.sh ヘッダ参照 (global CMD を読む / return 0=pass, 2=block)。
gate_block_push_to_protected() {
  local TOP PROTECTED_FILE HAS_REFSPEC dst b CUR REASON=""

# git push でなければ素通し (path-prefixed git も検出する: cmd_has_git_push)
cmd_has_git_push "$CMD" || return 0

# protected marker を解決 (`.bootstrap/protected` 新 / `.bootstrap-protected` 旧)。
# 無ければ opt-out として fail-open。
repo_top_var
TOP="$REPO_TOP"
[ -z "$TOP" ] && return 0
PROTECTED_FILE="$(resolve_marker "$TOP" protected)"
[ -f "$PROTECTED_FILE" ] || return 0
# protected 判定 (is_protected) は lib/protected-branch.sh の single authority に委譲する。

# `git push` の refspec destination を全 segment 分 列挙する (push_destination_branches)。
# greedy sed の旧実装と違い compound command の各 push を漏れなく見るので、
# `git push origin main && git push origin feat/x` の保護 branch main も block される。
# 1 つでも protected な destination があればそこで block (first protected hit)。
HAS_REFSPEC=0
while IFS= read -r dst; do
  [ -z "$dst" ] && continue
  HAS_REFSPEC=1
  if is_protected "$dst" "$PROTECTED_FILE"; then
    REASON="refspec destination → protected branch '$dst'"
    break
  fi
done <<EOF
$(push_destination_branches "$CMD")
EOF

# --all / --branches / --mirror は refspec を列挙しない (= destination は「全 local branch」)。
# 旧実装はこれを current-branch 判定に落とし、feature branch 上からの `git push --all origin`
# が保護 main を素通りさせた (2026-07-10 監査で実測)。破壊 scope が列挙不能な push は列挙を
# caller 側で展開して fail-closed に判定する (ADR 0019): 全 local branch を destination として
# 1 つでも protected があれば block。
if [ -z "${REASON:-}" ] && push_pushes_all_branches "$CMD"; then
  while IFS= read -r b; do
    [ -z "$b" ] && continue
    if is_protected "$b" "$PROTECTED_FILE"; then
      REASON="--all/--branches/--mirror push は全 local branch を destination にする — protected branch '$b' を含む"
      break
    fi
  done <<EOF
$(git for-each-ref refs/heads/ --format='%(refname:short)' 2>/dev/null)
EOF
fi

# refspec が無い push は現在 branch を見る (repo であることは TOP 解決済みで確定)
if [ -z "${REASON:-}" ] && [ "$HAS_REFSPEC" -eq 0 ]; then
  CUR=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  if is_protected "$CUR" "$PROTECTED_FILE"; then
    REASON="現在 branch '$CUR' への暗黙 push"
  fi
fi

[ -z "${REASON:-}" ] && return 0

cat >&2 <<EOF
project-bootstrap: blocking direct push to a protected branch — $REASON

.bootstrap-protected で宣言された branch への直接 push を禁止する。理由:
  - 並走 session が作った混入 commit が共有 branch に lock-in する事故を防ぐ
  - sprint flow は「task = feature branch → 統合は integrate skill (PR / merge)」が default

対処:
  1. feature branch を切る:        git switch -c feat/<topic>
  2. その branch に push:           git push -u origin feat/<topic>
  3. 統合は integrate skill / PR 経由でレビューと統合 verify を通す

solo で意図的に main へ直接 push する必要があるなら、/permissions で本 hook を一時 deny にする。
EOF
return 2
}

# 単体起動 (tests / vendoring 消費者) — dispatcher からは source されるので走らない。
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  # shellcheck source=lib/standalone.sh
  . "${BASH_SOURCE[0]%/*}/lib/standalone.sh"
  bootstrap_standalone_bash_gate gate_block_push_to_protected
fi

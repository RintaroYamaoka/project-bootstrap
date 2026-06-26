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

INPUT=$(cat)
# shellcheck source=lib/parse-command.sh
. "$(dirname "$0")/lib/parse-command.sh"
# shellcheck source=lib/protected-branch.sh
# Single authority for `git push` detection, refspec-destination enumeration, and the
# protected-branch glob match — shared so the gate cannot drift from the lib (and the lib
# fixes the two LIVE bugs: path-prefixed git was invisible, and a greedy sed inspected
# only the LAST push of a compound command). See lib/protected-branch.sh.
. "$(dirname "$0")/lib/protected-branch.sh"
if ! CMD="$(printf '%s' "$INPUT" | parse_command)"; then
  echo "project-bootstrap: could not parse the tool command from hook input — blocking to fail safe (fail-closed). If this is a false positive, disable this hook via /permissions." >&2
  exit 2
fi

[ -z "$CMD" ] && exit 0

# git push でなければ素通し (path-prefixed git も検出する: cmd_has_git_push)
cmd_has_git_push "$CMD" || exit 0

# protected marker を解決 (`.bootstrap/protected` 新 / `.bootstrap-protected` 旧)。
# 無ければ opt-out として fail-open。
command -v git >/dev/null 2>&1 || exit 0
TOP=$(git rev-parse --show-toplevel 2>/dev/null | tr '\\\\' '/' | tr -s '/')
[ -z "$TOP" ] && exit 0
# shellcheck source=lib/resolve-marker.sh
. "$(dirname "$0")/lib/resolve-marker.sh"
PROTECTED_FILE="$(resolve_marker "$TOP" protected)"
[ -f "$PROTECTED_FILE" ] || exit 0
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

# refspec が無い push は現在 branch を見る
if [ -z "${REASON:-}" ] && [ "$HAS_REFSPEC" -eq 0 ]; then
  if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    CUR=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    if is_protected "$CUR" "$PROTECTED_FILE"; then
      REASON="現在 branch '$CUR' への暗黙 push"
    fi
  fi
fi

[ -z "${REASON:-}" ] && exit 0

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
exit 2

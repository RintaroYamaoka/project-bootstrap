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
if ! CMD="$(printf '%s' "$INPUT" | parse_command)"; then
  echo "project-bootstrap: could not parse the tool command from hook input — blocking to fail safe (fail-closed). If this is a false positive, disable this hook via /permissions." >&2
  exit 2
fi

[ -z "$CMD" ] && exit 0

# git push でなければ素通し
echo "$CMD" | grep -qE '(^|[[:space:]&|;()`]+)git[[:space:]]+push([[:space:]]|$)' || exit 0

# `.bootstrap-protected` を解決。無ければ opt-out として fail-open。
command -v git >/dev/null 2>&1 || exit 0
TOP=$(git rev-parse --show-toplevel 2>/dev/null | tr '\\\\' '/' | tr -s '/')
[ -z "$TOP" ] && exit 0
PROTECTED_FILE="$TOP/.bootstrap-protected"
[ -f "$PROTECTED_FILE" ] || exit 0

# protected 判定: 宣言 glob のいずれかに一致するか (空行 / # コメントは無視)
is_protected() {
  local b="$1" pat
  while IFS= read -r pat || [ -n "$pat" ]; do
    pat="${pat#"${pat%%[![:space:]]*}"}"; pat="${pat%"${pat##*[![:space:]]}"}"
    [ -z "$pat" ] && continue
    case "$pat" in \#*) continue ;; esac
    # shellcheck disable=SC2053
    [[ "$b" == $pat ]] && return 0
  done < "$PROTECTED_FILE"
  return 1
}

# `git push` 以降の引数を取り出して word 分割
ARGS=$(printf '%s' "$CMD" | sed -E 's/^.*git[[:space:]]+push//')

# 引数を走査: flag をスキップ、positional の 1 個目を remote、以降を refspec とみなす。
# refspec の destination (src:dst の dst、無ければ token 自体) が protected なら block。
POSITIONAL=0
HAS_REFSPEC=0
# shellcheck disable=SC2086
set -- $ARGS
while [ $# -gt 0 ]; do
  tok="$1"; shift
  case "$tok" in
    -*) continue ;;   # flag (-u / --force / --set-upstream 等) はスキップ
  esac
  POSITIONAL=$((POSITIONAL + 1))
  if [ "$POSITIONAL" -eq 1 ]; then
    continue          # 1 個目の positional = remote (origin 等)
  fi
  HAS_REFSPEC=1
  # refspec の destination 部分を取り出す (src:dst なら dst)
  case "$tok" in
    *:*) dst="${tok##*:}" ;;
    *)   dst="$tok" ;;
  esac
  if is_protected "$dst"; then
    REASON="refspec '$tok' → protected branch '$dst'"
    break
  fi
done

# refspec が無い push は現在 branch を見る
if [ -z "${REASON:-}" ] && [ "$HAS_REFSPEC" -eq 0 ]; then
  if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    CUR=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    if is_protected "$CUR"; then
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

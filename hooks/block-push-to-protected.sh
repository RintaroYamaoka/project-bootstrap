#!/usr/bin/env bash
# Hook F — PreToolUse on Bash for `git push`
# main / master への直接 push を block する。feature branch + PR (= integrate skill) 経由に
# 矯正することで、(1) 並走 session が作った混入 commit が共有 main に lock-in する事故
# (実事故: 別 Terminal の staged file 混入 commit が origin/main へ push された) を defense-in-depth
# で塞ぎ、(2) sprint flow の「task = feature branch → 統合は integrate skill」を default 化する。
#
# 検出: push の refspec destination が main/master のとき、または refspec 無し push で
#       現在 branch が main/master のとき exit 2。feature branch への push は素通し。
#
# bypass: solo dev が意図的に main へ直接 push したい場合は /permissions で本 hook を一時 deny。

set -u

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | grep -oE '"command"[^,}]*' | head -1 | sed 's/.*"command"[[:space:]]*:[[:space:]]*"//; s/"[[:space:]]*$//')

[ -z "$CMD" ] && exit 0

# git push でなければ素通し
echo "$CMD" | grep -qE '(^|[[:space:]&|;()`]+)git[[:space:]]+push([[:space:]]|$)' || exit 0

# protected 判定
is_protected() {
  case "$1" in
    main|master) return 0 ;;
    *) return 1 ;;
  esac
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

main / master への直接 push を禁止する。理由:
  - 並走 session が作った混入 commit が共有 main に lock-in する事故を防ぐ
  - sprint flow は「task = feature branch → 統合は integrate skill (PR / merge)」が default

対処:
  1. feature branch を切る:        git switch -c feat/<topic>
  2. その branch に push:           git push -u origin feat/<topic>
  3. 統合は integrate skill / PR 経由でレビューと統合 verify を通す

solo で意図的に main へ直接 push する必要があるなら、/permissions で本 hook を一時 deny にする。
EOF
exit 2

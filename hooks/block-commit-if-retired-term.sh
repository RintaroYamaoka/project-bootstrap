#!/usr/bin/env bash
# Hook M — PreToolUse on Bash for `git commit`
# この commit が **新しく足した行** に、project が「引退した名前」として登記した語が
# 混入していたら exit 2 で blocking する。
#
# 背景 (実例): ai-reception で `Intent.typeNo` (number) → `typeId` (string) に改名した #88 の
# **1 時間 12 分後**にマージされた別 PR (#99) が、改名を知らずに `i.typeNo` を参照したまま実装
# されていた。`Intent` に `typeNo` は無いので常に `undefined`、`undefined === null` は false、
# エラーも出ない — テスト UI が「#undefined」を 3 日以上表示し続けた。改名は**改名した PR の
# 自己申告では原理的に漏れる** (改名の "後に" 書く人は、grep すべき語が在ることを知らない)。
# だから旧称は一度 registry に登記し、独立した常時稼働の機構が検査する。
#
# 信号 = 「この commit が新しく足した行」。理由と、edit 時 gate を作らない理由、docs を除外する
# 理由は単一権威 lib/retired-terms.sh の header が権威 (ここに複製しない)。
#
# fail-mode (memory feedback_gate_signal_and_failmode に準拠):
#   - 解析不能 (command が読めない) = fail-closed (block gate なので payload で黙らせない)
#   - 根拠不在 (git commit でない / repo 外 / marker 不在 / 有効行 0) = fail-open で素通し
#   - block 時の助言は構成的に: 置換先の名前を出す (「隠せ」と言わない)。
#
# opt-in: `.bootstrap/retired` (新) / `.bootstrap-retired` (旧 flat) が在るときだけ発火。
# jq 非依存。

set -u

INPUT=$(cat)

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/parse-command.sh
. "$DIR/lib/parse-command.sh"
if ! CMD="$(printf '%s' "$INPUT" | parse_command)"; then
  echo "project-bootstrap: could not parse the tool command from hook input — blocking to fail safe (fail-closed). If this is a false positive, disable this hook via /permissions." >&2
  exit 2
fi

# git commit でなければ素通し (検出は単一権威 lib/git-invocation.sh、ADR 0019)。
# shellcheck source=lib/git-invocation.sh
. "$DIR/lib/git-invocation.sh"
cmd_invokes_git_subcommand "$CMD" commit || exit 0

command -v git >/dev/null 2>&1 || exit 0
TOP=$(git rev-parse --show-toplevel 2>/dev/null)
[ -z "$TOP" ] && exit 0   # repo 外 = 根拠不在 → fail-open

# shellcheck source=lib/resolve-marker.sh
. "$DIR/lib/resolve-marker.sh"
MARKER="$(resolve_marker "$TOP" retired)"
[ -f "$MARKER" ] || exit 0   # 未採用 → 無音で素通し

# shellcheck source=lib/commit-files.sh
. "$DIR/lib/commit-files.sh"
# shellcheck source=lib/retired-terms.sh
. "$DIR/lib/retired-terms.sh"

# 有効行 0 の marker は「宣言だけの no-op」→ ここでは素通し。その事実は scripts/doctor.sh が
# partial として可視化する (= 効いていない強制を無音にしない、③ の適用)。
retired_load "$MARKER" || exit 0

VIOLATIONS="$(retired_added_lines_cmd "$CMD" | retired_scan_stream)" || exit 0
[ -n "$VIOLATIONS" ] || exit 0

{
  echo "project-bootstrap: blocking commit — this commit ADDS lines that use a RETIRED name."
  echo
  # `<rel>|<term>|<replacement>|<note>|<line>` を人が読める形に畳む。置換先が空なら
  # 「登記のみ (置換先未記入)」と正直に出す (存在しない新名を捏造しない)。
  printf '%s\n' "$VIOLATIONS" | while IFS='|' read -r rel term repl note line; do
    if [ -n "$repl" ]; then
      printf '  - %s: "%s" は引退済み → "%s" を使う\n' "$rel" "$term" "$repl"
    else
      printf '  - %s: "%s" は引退済み (置換先は %s に未記入)\n' "$rel" "$term" "${MARKER#"$TOP"/}"
    fi
    [ -n "$note" ] && printf '      note: %s\n' "$note"
    printf '      + %s\n' "$line"
  done
  cat <<EOF

登記は ${MARKER#"$TOP"/} (引退した名前の正本)。検査対象は **この commit が新しく足した行だけ**
なので、既存行に残っている同じ語は対象外 — それを直しに自分の lane を出る必要は無い
(残存件数は SessionStart の doctor が別途可視化する)。

対処 (上から順に検討する):
  - 追加行の名前を新しい名前に直す (**ふつうはこれ**)
  - その語が引退していない / 射程が広すぎるなら、${MARKER#"$TOP"/} の該当行を意図的に直す
    (3 列目に scope glob を書いて射程を絞れる)
  - その行が旧称 **について** 書いている場合だけ (改名を説明するコメント / 旧称を綴らねば
    ならない fixture / 旧 column を読む migration)、その行に \`${RETIRED_OK_TOKEN}\` を
    書いて 1 行だけ除外する。**diff に残るので レビューで見える** — marker を消すより狭い
  - 例外的に一度だけ通すなら /permissions で本 hook を一時 deny
EOF
} >&2
exit 2

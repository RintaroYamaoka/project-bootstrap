#!/usr/bin/env bash
# Hook L — SessionStart
# session を開いた瞬間に project-bootstrap の採用状態を audit し、可視化する net。
#
# 背景: 規律 gate は消費先 repo でその hook が現行版で走っていて初めて効く。だが「採用したのに
# gate が届いていない (= partial)」や「そもそも採用も提案もされない (= unadopted)」状態は無音で
# 成立し、誰も気づけなかった (= 唯一の sprint gate には CI net が無いので致命的)。本 hook は
# scripts/doctor.sh の verdict を session 起動時に context へ注入して、その無音を破る。
#
# できること / できないこと:
#   - これは強制ではない (advisory)。採用は consent 必須なので hook で強制できない。enforcement の
#     本体は per-action gate (PreToolUse) が担う。本 hook は「状態を可視化する」だけ。
#   - plugin が在る session でしか発火しない (= plugin 不在で vendored hook だけの repo は救えない)。
#     その穴は CI template (templates/ci/bootstrap-doctor.yml) が plugin 非依存で塞ぐ。
#   - 注入するのは actionable な状態だけ: 採用 audit は unadopted = 導入を聞く / partial = 穴を警告、
#     repo drift audit は stale-vs-main / merge 済み worktree 残骸が在るときだけ、verification drift
#     audit は逐次 trunk 変更に動作テストの要否判断が無いときだけ。3 軸とも無ければ無音 (= advisory
#     bloat を増やさない)。
#   - 3 軸は独立 — 採用が ok でも drift は出す (= 別軸の可視化。stale checkout・lane 撤去漏れ・未判断の
#     trunk 変更は採用状態と無関係に session を蝕む)。判定エンジンは lib/repo-drift.sh と
#     lib/verification-drift.sh (後者は merge gate が捕まえない逐次経路を ADR 0007 の委任どおり可視化)。

set -u

INPUT=$(cat)

DIR="$(cd "$(dirname "$0")" && pwd)"

# SessionStart input JSON から cwd を取り出す (単一権威 decoder。旧 grep 抽出は path 中の
# `,` `}` / escape で途中切りした — 2026-07-10 監査。ここは advisory なので劣化は可視化の
# 精度だけだが、単一権威に寄せる)。
# shellcheck source=lib/parse-command.sh
. "$DIR/lib/parse-command.sh"
CWD=$(printf '%s' "$INPUT" | parse_json_string_field cwd)
[ -z "$CWD" ] && CWD="$PWD"

# (1) 採用 audit — doctor.sh の verdict。actionable (unadopted/partial) のときだけ本文化。
REPORT=$(bash "$DIR/../scripts/doctor.sh" "$CWD" 2>/dev/null)
STATUS=$(printf '%s\n' "$REPORT" | head -1 | sed 's/^STATUS:[[:space:]]*//')
ADOPT=""
case "$STATUS" in
  unadopted|partial) ADOPT="$REPORT" ;;
esac

# (2) repo drift audit — stale-vs-main + merge 済み worktree 残骸。drift が無ければ空 (無音)。
# shellcheck source=lib/repo-drift.sh
. "$DIR/lib/repo-drift.sh"
DRIFT=$(drift_report "$CWD" 2>/dev/null)

# (3) verification drift audit — 逐次 trunk 変更に動作テストの要否判断が記録されていない無音状態を
#     可視化。merge gate (block-merge-if-verification-unclosed) は lane branch の merge しか信号に
#     しないので branch を切らない逐次作業はその射程外 (ADR 0007 が doctor に委ねた半分)。採用
#     (docs/verification/) していなければ空 (無音)。判定エンジンは lib/verification-drift.sh。
# shellcheck source=lib/verification-drift.sh
. "$DIR/lib/verification-drift.sh"
VDRIFT=$(verification_drift_report "$CWD" 2>/dev/null)

# 3 軸とも無ければ無音で終わる。
[ -z "$ADOPT" ] && [ -z "$DRIFT" ] && [ -z "$VDRIFT" ] && exit 0

# 本文を組む (在る軸を空行で繋ぐ — 軸どうしは独立なので順に append)。
BODY=""
for part in "$ADOPT" "$DRIFT" "$VDRIFT"; do
  [ -n "$part" ] || continue
  if [ -n "$BODY" ]; then
    BODY="$BODY
$part"
  else
    BODY="$part"
  fi
done

# 本文を JSON 文字列に pure-bash で escape (jq 非依存): \ → \\、" → \"、改行 → \n。
ESC="$BODY"
ESC="${ESC//\\/\\\\}"
ESC="${ESC//\"/\\\"}"
ESC="${ESC//$'\n'/\\n}"

PREFIX='[project-bootstrap] SessionStart audit (advisory — 強制ではない。enforcement は per-action gate):\n'
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s%s"}}\n' "$PREFIX" "$ESC"
exit 0

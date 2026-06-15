#!/usr/bin/env bash
# Hook H — PreToolUse on Edit|Write|MultiEdit
# sprint 自動分解の発火判定を fail-closed で強制する gate。
#
# 背景: sprint 発火はかつて sprint-trigger-reminder.sh (UserPromptSubmit) の **advisory**
# だけで担保されていた。だが「判定して分解する」のはモデル任せで、長い会話で忘れられると
# 一度も発火しない (= 実事故あり: docs/incidents/2026-05-31-sprint-advisory-silent)。これは
# プラグインが他所で否定している「advisory は忘れられる」失敗モードそのもの。さらにその信号は
# prompt の語彙 (= proxy) で、自然言語は無限だから構造的に穴があり「全統合せよ」「やれ」で素通った。
#
# 本 hook は TDD/lane/arch hook と同型: hook は sprint を **起動しない** (worktree 起動=人間 /
# disjoint 判定=モデルで、ADR 0001 の既約な残余)。強制するのは「gate 判定を済ませた」という
# **precondition** だけ。信号は語彙ではなく **新規 source file を作る行為そのもの** (= これから
# feature 面を作る、という判定対象それ自身) に置く。判定の記録 (docs/sprint/.gate) か進行中 sprint
# (docs/sprint/board.json) が無いまま新規 source 面を作ろうとしたら exit 2 で blocking。
#
# fail-mode (memory feedback_gate_signal_and_failmode に準拠):
#   - 根拠不在 = fail-open。file_path 不在 / 非 git / docs/sprint 未採用 / 既存 file 編集 /
#     test・config・doc / 非 source 拡張子 は「feature 面を作る根拠が無い」→ 素通し。
#     bug fix / refactor / 既存 file 編集は一切 trip しない。
#   - block 時の助言は構成的に (= 記録して続行へ誘導。削除/隠蔽を促さない)。
#
# opt-in: docs/sprint/ ディレクトリが在るときだけ発火 (= .bootstrap-arch/protected/lane と同じ
# project-local 採用宣言)。無ければ fail-open。jq 非依存。

set -u

INPUT=$(cat)

FILE=$(printf '%s' "$INPUT" | grep -oE '"file_path"[^,}]*' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//; s/"[[:space:]]*$//')
if [ -z "$FILE" ]; then
  FILE=$(printf '%s' "$INPUT" | grep -oE '"path"[^,}]*' | head -1 | sed 's/.*"path"[[:space:]]*:[[:space:]]*"//; s/"[[:space:]]*$//')
fi
[ -z "$FILE" ] && exit 0   # 根拠不在 → fail-open

# git repo root を解決。repo 外 / git 不在なら fail-open (scope を論じる基盤が無い)。
command -v git >/dev/null 2>&1 || exit 0
TOP=$(git rev-parse --show-toplevel 2>/dev/null | tr '\\\\' '/' | tr -s '/')
[ -z "$TOP" ] && exit 0

# opt-in: sprint flow を採用した project (= docs/sprint/ が在る) でのみ発火。
[ -d "$TOP/docs/sprint" ] || exit 0

# 編集対象を repo 相対 path に正規化 (block-out-of-lane-edit と同方式)。
FILE_NORM=$(printf '%s' "$FILE" | tr '\\\\' '/' | tr -s '/')
case "$FILE_NORM" in
  "$TOP"/*) REL="${FILE_NORM#"$TOP"/}" ;;
  /*|[A-Za-z]:/*) exit 0 ;;   # worktree 外の絶対 path は判断不能 → fail-open
  *) REL="$FILE_NORM" ;;       # 既に相対ならそのまま
esac

# sprint runtime state 自身 (board.json / .gate) の書き込みは決して止めない。
case "$REL" in
  docs/sprint/*|*/docs/sprint/*) exit 0 ;;
esac

# 既存 file の編集/上書きは「新規 feature 面の作成」ではない → fail-open。
# PreToolUse は書き込み前に走るので、新規作成のときだけ対象 path が未存在になる。
[ -e "$TOP/$REL" ] && exit 0

# test ファイル / config / docs / 非 source 拡張子は feature 面ではない → 素通し
# (require-test-companion と同慣行)。判定は共有エンジン (= guard 2 の block-uniso-main-edit.sh
# と「source 面とは何か」を単一権威に保ち drift を防ぐ。ADR 0005)。
# shellcheck source=lib/source-face.sh
. "$(dirname "$0")/lib/source-face.sh"
is_source_path "$REL" || exit 0

# 進行中の sprint なら lane hook が scope を握る → 素通し。「進行中」は board の**存在**では
# なく**活性** (= 未完了 task の有無) で判定する。全 task done / task 無し / status 不在の board
# は sprint 終了後の残置 (stale) でありうるため素通しの根拠にしない — 存在を信号にすると state
# の lifecycle 終端で gate が無音で fail-open する (実事故: docs/incidents/2026-06-07-stale-board-gate-bypass)。
# 判定エンジンは block-unreviewed-merge.sh と共有 (= 信号の drift 防止)。
# shellcheck source=lib/board-liveness.sh
. "$(dirname "$0")/lib/board-liveness.sh"
board_has_active_tasks "$TOP/docs/sprint/board.json" && exit 0

# .gate に記録された判定のうち「生きている」entry に REL が一致すれば、判定済みの feature 面
# → 素通し。形式: 各行 `<scope-glob>  <YYYY-MM-DD>  <free-text rationale>`。# / 空行は無視。
# entry は時間 (日付列が TTL 内) と空間 (feature-scoped な glob) の両方で bound する —
# .gate は feature 単位の ephemeral 判定であり、無期限・無界に信じると 1 行で gate が恒久
# fail-open する (実事故: 消費先 repo の `src/**` 1 行が source tree 全域の gate を以後ずっと
# 無音で殺した。docs/incidents/2026-06-11-gate-broad-glob-permanent-fail-open)。
# 日付なし (旧形式) / 失効 / 全域 glob は「判定の活性を証明できない」→ 不採用 (= 解析不能を
# 素通し側に倒さない)。不採用 entry は block message に列挙する (= 正データを隠させない)。
# 判定エンジンは lib/gate-entry.sh (= 信号の drift 防止。board-liveness と同慣行)。
# shellcheck source=lib/gate-entry.sh
. "$(dirname "$0")/lib/gate-entry.sh"
GATE="$TOP/docs/sprint/.gate"
IGNORED=""
if [ -f "$GATE" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"   # ltrim
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    IFS=' ' read -r pat dt _rest <<< "$line"   # 1 列目 = glob / 2 列目 = 日付 (read は glob 展開しない)
    [ -z "$pat" ] && continue
    if ! gate_date_fresh "${dt:-}"; then
      IGNORED="$IGNORED
  - $pat  (日付なし旧形式 / 失効 >${GATE_TTL_DAYS}日 / 日付不正 — 判定の活性を証明できない)"
      continue
    fi
    if ! gate_scope_ok "$pat"; then
      IGNORED="$IGNORED
  - $pat  (全域 glob — feature 面の scope になっていない)"
      continue
    fi
    # shellcheck disable=SC2053
    if [[ "$REL" == $pat ]]; then
      exit 0
    fi
  done < "$GATE"
fi

# wip_limit の表示値: project が .bootstrap-wip で宣言していればその値、なければ「既定 2-3」。
# shellcheck source=lib/resolve-wip-limit.sh
. "$(dirname "$0")/lib/resolve-wip-limit.sh"
WIP_DISPLAY=$(resolve_wip_limit)

cat >&2 <<EOF
project-bootstrap: blocking creation of new source file "$REL" — sprint gate not run.

新規の feature 面を作ろうとしている (docs/sprint/ が在る = sprint flow 採用 project)。
コードに触れる前に sprint 自動分解の発火判定を行うこと:
  ① feature (新規/拡張) か? — bug fix / refactor / 単一 file / 自明な小変更なら逐次
  ② scope 非重複の leaf が 2 個以上に割れるか? (各 task の owned file glob が重ならない)
  ③ 同時 lane ≤ wip_limit [$WIP_DISPLAY] か?

3 つ全部満たすなら sprint-plan skill をロードして board.json + 各 lane の worker 起動文を提示する
(= 分解後は board.json の存在でこの gate は通る)。

1 つでも欠けたら逐次。その判定を docs/sprint/.gate に 1 行記録してから続行する
(1 列目 = この作業がカバーする scope glob、2 列目 = 今日の日付、以降は理由):

  printf '%s\n' "src/<area>/<feature>/**  \$(date +%F)  sequential: <理由>" >> docs/sprint/.gate

scope glob は feature 面に絞る — exact path か、wildcard の前に 2 階層以上のディレクトリ
prefix を持つ glob のみ有効 (src/** のような全域 glob は entry として無効 = 1 行で gate が
恒久 fail-open した実事故あり)。記録は ${GATE_TTL_DAYS} 日で失効する — 同じ feature 面の継続が
長引いたら同じ行を日付だけ更新して再記録する (= その再記録が「まだ同一 feature 面か」の再判定)。
記録 scope 内の新規 source は以後素通しする (= 同 feature 面の継続)。
記録 scope 外の新規 source を作ると再び停止する (= 新しい disjoint 面 → 再判定)。
共有 interface/型は直列 spine (depends_on) に切り出してから下流 leaf を並列化する。${IGNORED:+

なお .gate に entry はあるが、以下は判定の証拠として無効だった (行の削除は不要 — 失効は正常な終端):$IGNORED}
EOF
exit 2

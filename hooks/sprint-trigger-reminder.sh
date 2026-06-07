#!/usr/bin/env bash
# Hook — UserPromptSubmit
# sprint 自動分解 (= feature を複数 Claude で並列開発) は SKILL.md の **advisory** で、
# 「Claude が探索結果から自分で判定して sprint-plan をロードする」設計。だが context から
# SKILL が抜ける / 長い会話で忘れられると、判定そのものが走らず「全然起動しない」になる。
# これはプラグイン自身が他所で否定している「advisory は忘れられる」失敗モードそのもの。
#
# 本 hook はその穴を deterministic に塞ぐ: feature 実装っぽい user prompt のときだけ、
# sprint 発火判定の 3 条件 checklist を **毎ターン context に注入**して「判定し忘れ」を防ぐ。
#
# できること / できないこと:
#   - sprint を hook で起動することは**できない** (worktree 起動は人間、最終判定は Claude)。
#   - できるのは「判定を毎ターン思い出させる」ことだけ。3 条件の判断は Claude が下す。
#   - 非該当 prompt では何も出さない (= 無音。ノイズを増やさない)。
#   - over-trigger (= feature でない prompt で発火) しても reminder 1 つで安く、3 条件 gate が
#     bugfix / 単一 file を弾くので害にならない。設計上 false negative より false positive を許す。

set -u
INPUT=$(cat)

# feature 実装の意図を示すシグナル。広めに拾う (= 取りこぼしより誤検知を許す)。
# 明示の並列要求 (スクラム / 並列で / 複数ターミナル) も拾う。
FEATURE_RE='実装|機能|feature|追加してほしい|追加して|作って|作りたい|新規|構築|implement|build a|スクラム|並列で|複数ターミナル'

# prompt は INPUT 中の唯一の自由記述フィールド。他フィールド (cwd / *_path / session_id) は
# パスや ID なので上記キーワードに当たらない。raw INPUT を grep すれば十分 (完全な JSON 解析不要)。
printf '%s' "$INPUT" | grep -qiE "$FEATURE_RE" || exit 0

# wip_limit の表示値: project が .bootstrap-wip で宣言していればその値、なければ「既定 2-3」。
# 出力は数字 + 固定文字列のみ (= " や \ を含まない) なので、そのまま JSON に埋められる。
# shellcheck source=lib/resolve-wip-limit.sh
. "$(dirname "$0")/lib/resolve-wip-limit.sh"
WIP_DISPLAY=$(resolve_wip_limit)

# additionalContext に載せる reminder。content には " や \ を含めず、改行は JSON の \n
# (= backslash + n) で表現する。これで pure-bash のまま valid JSON を組める (jq 非依存)。
CONTEXT='[project-bootstrap] feature 実装の可能性。コードに触れる前に sprint 自動分解の発火判定を必ず行うこと:\n  ① feature (新規/拡張) か? — bug fix / refactor / 単一 file / 自明な小変更なら逐次 (/plan -> TDD)\n  ② read-only 探索の結果、scope 非重複の leaf が 2 個以上に割れるか? (各 task の owned file glob が重ならない)\n  ③ 同時 lane <= wip_limit ['"$WIP_DISPLAY"'] か?\n3 つ全部満たすなら、言われる前に sprint-plan skill をロードして board.json + 各 lane の worker 起動文を提示する。1 つでも欠けたら逐次。共有 interface/型/契約は直列 spine (depends_on) に切り出してから下流 leaf を並列化する。'

printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$CONTEXT"
exit 0

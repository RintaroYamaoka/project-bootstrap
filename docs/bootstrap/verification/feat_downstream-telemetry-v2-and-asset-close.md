# verification plan — feat/downstream-telemetry-v2-and-asset-close (v0.34.0)
# 意図: (1) 停止条件が「守られたか」と人間時間を検収テレメトリに足す (metrics schema v2、ADR 0024 追記)
#   (2) HUMAN/manual 行の資産化質問を close/archive の責務に足し、人間の確認を使い捨てにしない
#   (3) handoff の「長い session」trigger を harness の自動要約継続に譲って縮退する (ADR 0008 #5)
# 跨いだ境界:
#   (a) metrics.tsv の列契約 — accept SKILL / ADR 0024 / wo-metrics.sh の 3 か所が同じ列名・列順を
#       指していないと、記録側と集計側が無音でズレる (cross-file 契約の面)
#   (b) 既存 v1 行 (10 列) との共存 — 集計が v1 行で落ちる/誤読すると過去実績が無音で壊れる
#   (c) skill 文言の mirror 面 — verification⇔integrate の資産化質問、handoff⇔ADR 0008 #5 (ADR→SKILL、ADR 0003)
#   (d) ADR 0008 #5 の外部前提 — 「harness が自動要約継続を持つ」は harness 側の事実で repo の外
# 落とした範囲: 下記 DROP 3 行
# STATUS | kind | behaviour | oracle | by | evidence/note
PASS | unit     | wo-metrics.sh v2 集計: retries>retry_limit を超過に数える / 予算超過と並記 / 人間時間 3 列の平均と件数 / `-` 欠測を 0 と混同せず除外 | fixture (v2 実績 2 行) に対する実出力の期待値 | ai | scratchpad fixture 実走: 再試行上限超過 1 件 (5>3) / 人間時間 発注まで avg 38 分 (2件)・実装中 avg 10 分 (1件、欠測 1 行除外)・検収 avg 18 分 (2件)
PASS | unit     | v1 行 (10 列) 共存: 11 列目以降を未記録として読み、件数・合計・リードタイムは全行で集計される | 同 fixture に v1 行 1 行を混在させた実出力 | ai | 検収済み 3 件 / 超過カウントに v1 行が混入しない / crash なし
PASS | contract | 列契約の 3 点一致: accept SKILL の schema 行・ADR 0024 追記・wo-metrics.sh ヘッダが同じ 4 列名 (retry_limit / human_order_min / human_run_min / human_accept_min) を持つ | grep によるリテラル突合 | ai | 3 ファイルとも 4 列名を含むことを確認 (accept は連結 1 行、wo-metrics は awk 参照 $11-$14 と対応)
PASS | contract | mirror 面の一貫性: 資産化質問が verification Step 5 (本体)・lifecycle・integrate Step 5 の 3 か所で同じ質問と同じ「2 度目 = 自動化必須」規則を指す / handoff SKILL が ADR 0008 #5 を参照し、ADR 側に §5 が実在する | grep + 読み合わせ | ai | verification 2 箇所 + integrate 1 箇所 / handoff→"ADR 0008 #5" 参照 1 件、ADR 0008 に "### 5." 実在
PASS | unit     | 回帰面: hook は 1 本も変えていないので既存挙動が一切変わらない | 既存 self-CI 全 suite が無改変で緑 | ai | tests/hooks 53/53 suites pass
PASS | contract | 構文と形式: wo-metrics.sh の bash 構文 / plugin.json の JSON 妥当性 | bash -n + python3 -m json.tool | ai | 両方 OK
PASS | e2e      | ADR 0008 #5 の外部前提「harness が長い会話を自動要約して同一 session を継続する」が実在する | harness 自身の契約文 (repo の外のオラクル) | ai | 本 session の harness system prompt に context 要約継続の契約が明記されていることを確認 (2026-08-07)。ADR に「harness がこの挙動を変えたら再検証」を明記済み
DROP | unit     | wo-metrics.sh の永続テスト suite 化 | n/a | ai | tests/ は hooks (gate) 専用の self-CI で、集計 script (velocity.sh も同様) は suite を持たない慣行。集計は blocking しない読み物なので誤りの blast radius が gate と違う。fixture 実走で担保し、suite 化は集計に依存する自動判断が生まれたときに再検討
DROP | e2e      | 資産化質問が実際の close/archive で発火し HUMAN 行が昇格される | n/a | ai | skill 文言 (advisory) の実効性は実運用でしか観測できない。次の実 sprint の integrate 終端が初観測点 — 発火しなかったら incident に記録して構造 (gate 化の要否) を再検討する、が昇格条件
DROP | unit     | metrics.tsv 新規作成時の schema コメント行の機械強制 | n/a | ai | 「記録したか」を hook で強制しない方針 (ADR 0024 本文: 検出できる信号が無く、作れば proxy になる) と同じ理路。wo-metrics.sh は v1/v2 をコメント無しでも正しく読むので、コメントは人間向けの自己文書化に留まる

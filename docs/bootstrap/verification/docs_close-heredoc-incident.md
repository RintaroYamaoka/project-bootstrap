# verification plan — docs/close-heredoc-incident
# 意図: v0.35.0 の verification plan が理由つき DROP にした「リリース後に発見元で実査する」
#   という約束を実行し、その結果を incident 記録に残して閉じる (doc のみ、コード変更なし)。
# 跨いだ境界: 記録の正確さ — 実査していない事を実査したと書けば、記録が偽の安心を配る
#   (「実物を見ずの完了」seam の doc 版)。
# 落とした範囲: 下記 DROP 1 行
# STATUS | kind | behaviour | oracle | by | evidence/note
PASS | manual   | 追記した実査結果が、実際に行った検証と一致する (配備確認 → 誤検知消失 → 検出維持の 3 点) | この session で実行したコマンドの実出力 | ai | 配備 v0.35.0 + strip_heredoc_bodies 実在を確認 / ai-reception で最小再現が pass / 使い捨て repo で commit -F - の heredoc が commit 成立 / 配備版 hook に 6 ケース (誤検知 2 = pass、実行形 4 = block) 全一致
PASS | unit     | doc のみの変更で、hook / lib / test に差分が無い (回帰面ゼロ) | git diff --name-only | ai | 変更は incidents/README.md と本 plan の 2 file のみ
DROP | unit     | 追記文言の機械検査 | n/a | ai | 記録と実測の一致は人間/AI の読み合わせでしか判定できない (機械化すると「文字列が在る」の proxy になる)。上の manual 行がオラクル

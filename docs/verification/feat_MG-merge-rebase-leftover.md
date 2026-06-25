# verification plan — feat/MG-merge-rebase-leftover
#
# 意図: D6 = stale base の lane 統合を block して「merge 済み修正の無音 revert」(2026-06-25 incident)
# を防ぐ / 根拠不在は fail-open。D5 = 残置 worktree を surface するが決して block しない (cry-wolf 回避)。
# 継ぎ目: git topology (ancestor 関係) を offline 計算する継ぎ目。危険は false-block (正当な merge を
# 止める) と false-negative (stale lane を見逃す)、加えて既存 gate の非破壊。オラクルは AI の判断でなく
# **temp git repo を実際に組んで live gate を走らせた exit code / stderr** に置く。
# kill-question (各 PASS): false-block 行と fail-open 行で両方向を塞ぎ、advisory 行で「止めない」を担保。
#
# STATUS | kind | behaviour | oracle | by | evidence/note

PASS  | stale-block   | merge 先 (HEAD) を含まない lane は rebase まで block + merge-base 基準の乖離数を表示 | live gate over temp git repo (main を 2-3 commit 先行) → exit 2 | ai | drift test stale case / trace 'rev-list --left-right --count' 出力
PASS  | precedence    | レビュー記録なしの stale lane は「未レビュー」でなく「stale base」理由で先に block | live gate | ai | drift test 順序ケース (D6 が review path より前)
PASS  | no-false-block| merge 先が ancestor の up-to-date lane は D6 を通過 | live gate exit 0 | ai | drift test fresh case
PASS  | fail-open     | 非 lane / 解決不能 ref / 非 work-tree の merge は block しない | live gate exit 0 | ai | drift test c1,c2 (非 lane behind / feat/ghost)
PASS  | advisory-only | D5 が残置 worktree advisory を stderr に出すが exit code を変えない / 無いとき無音 | live gate | ai | drift test d + silence case
PASS  | preserve      | 既存 block-unreviewed-merge の 28 挙動を全維持 + 全 suite green | regression suite | ai | 原 test 28/0 / run.sh 30 suites 0 failed / bash -n clean
DROP  | scope         | 非 trunk の integration-branch から merge する稀ケースの DEST_REF を締める (origin/main にフォールバック) | n/a | ai | 文書化済みの under-block (false-block ではない)。minor finding・将来の tightening。spec 通りの意図的フォールバック

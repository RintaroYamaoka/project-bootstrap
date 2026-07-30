# verification plan — サーバ側強制を恒久層に (ADR 0012)
# 意図: ローカル merge hook が捕まえられないマージ経路 (GitHub Merge ボタン / API) と admin 素通り・
#       stale lane 統合破壊を、判定を変えずにサーバ側 (required check + branch protection + merge queue)
#       へ二層化して塞ぐ。判定ロジックは verification-plan.sh の単一権威のまま。
# 落とした範囲 (無音カット禁止): branch protection の実 API 適用は --check 監査までで止め、本適用は
#       workflow が main に乗ってから人間 (admin) が実行する (運用変更・要 orchestrator 承認)。
# STATUS | kind | behaviour | oracle | by | evidence/note

PASS | unit     | verification-ci-check が opt-in 不採用/plan不在/branch不解決で neutral pass、空/OPEN/HUMAN/理由なきDROPで block、全閉で pass | 期待値 (既知) | ai | tests/hooks/verification-ci-check.test.bash 14 assertions 緑
PASS | unit     | branch 解決順 arg > GITHUB_HEAD_REF > current | 期待値 | ai | 同 test #8 (env fallback)
PASS | drift-guard | CI twin と local hook が同一 lib (verification-plan.sh) を呼び判定が drift しない | 共有 lib のテスト | ai | verification-plan.test.bash 30 緑 + 全 35 suite 緑 (回帰なし)
PASS | unit     | setup-server-enforcement --check が保護なし repo を「gate OPEN」と報告する | 実コマンド出力 | ai | 本 repo で実行 → "NO branch protection ... server-side gate is OPEN" を確認
PASS | e2e     | verification-gate workflow が実走し required check として OPEN plan を実際に block する | GitHub Actions の run 結果 (赤) = AI の外の観測可能オラクル | ai | PR#7 run 28162844039: OPEN HUMAN 行で "verification-ci-check: BLOCK ... not closed" → exit 1 で required check fail を実測。block それ自体が動作確認 (HUMAN でなく観測で閉じる行だった)
DROP | e2e     | setup-server-enforcement.sh の本適用後、enforce_admins=true で admin (自分) が Merge ボタンを素通りできない | n/a | ai | 別メカニズム (GitHub branch protection) で本 CI run では未触。適用は本 PR マージ後なので pre-merge では原理的に観測不能 → マージ後に GitHub UI で Merge ブロックを目視確認する (検証放棄でなく実施時点を後ろにずらす明示)
DROP | unit    | gh api PUT branch-protection の HTTP 応答そのものの単体テスト | n/a | ai | 外部 API・冪等 PUT。--check の監査出力で状態を確認する方が実オラクルに近い (mock より実挙動)
DROP | contract | merge queue の GraphQL/REST 細部 | n/a | ai | ruleset.json テンプレに委譲・GitHub 機能依存。consumer 側で検証不能、配備時に UI で確認

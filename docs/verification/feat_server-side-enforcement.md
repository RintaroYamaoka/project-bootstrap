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
HUMAN | e2e     | この branch を PR にして verification-gate workflow が実走し required check として OPEN plan を実際に block する | GitHub Actions の run 結果 (緑/赤) + Merge ボタンが落ちる | human | workflow は本 PR で初発火。orchestrator が PR 上で目視確認 (single-orchestrator frontier)
HUMAN | e2e     | setup-server-enforcement.sh の本適用後、enforce_admins=true で admin (自分) が Merge ボタンを素通りできない | GitHub UI で Merge がブロックされる実挙動 | human | 本適用は workflow が main に乗った後。穴 2 の最終確認は実 UI でしか取れない
DROP | unit    | gh api PUT branch-protection の HTTP 応答そのものの単体テスト | n/a | ai | 外部 API・冪等 PUT。--check の監査出力で状態を確認する方が実オラクルに近い (mock より実挙動)
DROP | contract | merge queue の GraphQL/REST 細部 | n/a | ai | ruleset.json テンプレに委譲・GitHub 機能依存。consumer 側で検証不能、配備時に UI で確認

# verification plan — main (project-bootstrap dogfood)
#
# 意図: 逐次 trunk 変更で「動作テストの要否判断」を無音で省かせない。merge gate が捕まえない
# 逐次経路を SessionStart doctor が可視化する (ADR 0007 Amendment / verification-drift.sh)。
# 各行は実装からでなく「意図 + 跨いだ継ぎ目」から導く。kill-question を各 PASS に一度問う:
# 「このテストが緑のままユーザーが困る状態はありうるか?」— Yes ならオラクルが間違い。
#
# STATUS | kind | behaviour | oracle | by | evidence/note

PASS  | signal     | 採用済み repo の未コミット source 変更 + plan 不在で advisory が出る   | engine 単体テスト + 実 hook の JSON 出力 | ai | verification-drift.test.bash #1 / 実 hook smoke (api.ts で nudge JSON)
PASS  | signal     | main ref より先行する committed source でも出る (working tree clean) | engine 単体テスト                       | ai | verification-drift.test.bash #7
PASS  | false-pos  | doc のみ / clean tree / 未採用 では無音 (advisory bloat ゼロ)        | 単体テスト + 実 repo で silent          | ai | verification-drift.test.bash #2,4,6 / 本 repo は採用前 silent を実測
PASS  | integration| doctor が nudge を SessionStart additionalContext に注入する          | 統合テスト + 実 hook の valid JSON      | ai | bootstrap-session-doctor.test.bash #10,11 / smoke で hookSpecificOutput 確認
PASS  | drift-guard| gate と doctor が同一の branch→plan パスを使う (信号の drift なし)     | 共有ヘルパのテスト + gate 回帰          | ai | verification-plan.test.bash (vplan_path_for_branch) / merge gate 19 ケース緑
PASS  | suppress   | branch に非空 plan があれば doctor は無音 (判断が進行中とみなす)       | 統合テスト                              | ai | bootstrap-session-doctor.test.bash #11
HUMAN | seam-live  | live product (bootstrap 製) repo で実 session を開くと nudge が実際に出て actionable に読める | 実 Claude Code session を開いて目視 | human | 機構は既存の採用/drift audit と同一・smoke で JSON 確認済み。最終確認は orchestrator 本人 (single-orchestrator frontier)
DROP  | scope      | session 開始後に同一 session 内で作った変更の即時通知                | n/a                                     | ai | 意図的スコープ外: SessionStart は state-at-open net (repo-drift と同性質)。即時通知は同 engine 再利用の follow-up
DROP  | scope      | remote 無し local-only repo で committed-ahead source を検出          | n/a                                     | ai | fail-open by design (offline/no-fetch)。未コミット集合は出る。lib header に明記
DROP  | scope      | trunk 上で OPEN 放置された plan の closure を fail-closed に強制       | n/a                                     | ai | merge gate の領分 / 将来の push-time universal 拡張 (ADR 0007)。本変更は要否判断の不在のみ対象

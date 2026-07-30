# verification plan — feat/D3D4-verification-contract-async
#
# 意図: D3 = cross-repo 契約面に触れた lane の統合を、その契約 id の closed plan 行 +
# consumer テスト実行で gate / 自由文 PASS で閉じさせない / 根拠不在は fail-open。
# D4 = 非同期/silent-skip を verification の継ぎ目として doctrine 化 + controlled-vocab doctor。
# 継ぎ目: lane branch の delta 計算 (cwd/HEAD でなく) + 契約 id 照合の string-proxy 罠 + offline。
# オラクル = temp git repo に lane worktree を組んで実 gate を走らせた exit code。
#
# STATUS | kind | behaviour | oracle | by | evidence/note

PASS  | branch-delta  | gate が LANE delta (merge-base base..lane) を読む (cwd/HEAD でなく)・触れた契約面に closed [contract:id] 行が無ければ block | 実 gate (temp repo, HEAD=main) | ai | cross-repo-contract test + reviewer e2e (空振りしない)
PASS  | anchored-close| **[contract:<id>] アンカー tag のみ** close・substring/superstring/prose は close しない (booking≠booking-payload, prose-survey は block) | 実 gate e2e | ai | 修正後 re-review: 穴は exit 2・tag は exit 0 / 17+8 敵対プローブ
PASS  | run-suite     | 触れた契約を ack した merge で consumer suite を実行 → red なら block (exit 2) | 実 gate (package.json test exit!=0) | ai | NEEDS_CONTRACT_SUITE fixture (新規)
PASS  | fail-open     | 非merge / contracts なし / 触れた契約面なし / 非lane / sibling 読めない → exit 0 | 実 gate | ai | reviewer trace・consumer 側のみ (sibling を diff しない)
PASS  | async-doctor  | kind=async 行ありで real monitor 行なし → advisory・monitor ありで無音・**kind 欄キーで prose 非走査** (DROP 内 'drop' で誤発火しない)・docs-only branch 無音・exit 2 しない | verification-drift test 16 | ai | reviewer
PASS  | async-vocab   | verification-plan.sh に kind=async 語彙 + vplan_has_kind (exact match, substring でない) | verification-plan test 30 | ai | reviewer
PASS  | preserve      | 既存挙動を全維持 + 全 suite green | 全 suite 32/0 (block-merge-if-verification-unclosed 29) | ai | reviewer
DROP  | scope         | 触れた契約を理由つき DROP 行で閉じる escape valve を更に厳しくする | n/a | ai | verification DROP semantics 準拠の意図的・記録される escape (ADR 0011 risk #2)

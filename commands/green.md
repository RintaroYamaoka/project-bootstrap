---
description: TDD Green フェーズを実行する。implementer サブエージェントに failing テストを通す最小の実装を依頼する
argument-hint: <ターゲットテストファイル または 失敗中のテストの説明>
---

# /green — TDD Green phase entry

ターゲット: $ARGUMENTS

このコマンドは TDD の Green フェーズを実行する。

**`implementer` サブエージェントを起動して**、failing テストを通す最小の実装を書いてもらう。

## サブエージェントに渡す情報

- failing テストのファイルパスまたは説明 (上記)
- 触ってよい / 触ってはいけないモジュールの範囲 (`/plan` 出力に基づく)
- テスト実行コマンド

## エージェント実行後の確認事項

- ターゲットテストが pass する
- 広めのテストスイートに regression がない
- 「動かすため」のフォールバックや try/except が追加されていない (Fail-fast 違反)
- スコープ外の実装が混じっていない (YAGNI 違反)

## 次のステップ

改善対象がある場合: `/refactor <観点>` で Refactor フェーズに移行。
ない場合: タスクをクローズ (`project-bootstrap` skill の Step 9 参照)。

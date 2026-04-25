---
description: TDD Refactor フェーズを実行する。refactorer サブエージェントにテストを保ったまま構造改善を依頼する
argument-hint: <改善対象の領域 / 観点 (例 "user_service の重複", "validation の名前")>
---

# /refactor — TDD Refactor phase entry

対象 / 観点: $ARGUMENTS

このコマンドは TDD の Refactor フェーズを実行する。

**`refactorer` サブエージェントを起動して**、テストが pass し続ける範囲で構造改善をしてもらう。

## 前提

このコマンドを呼ぶ前にテストが pass していること (Green が完了していること)。
pass していない場合は先に `/green` を実行する。

## サブエージェントに渡す情報

- リファクタ対象のコード
- 関連するテストの場所
- テスト実行コマンド
- 改善観点 (上記の引数、または現在の context から特定)

## エージェント実行後の確認事項

- 適用された各リファクタでテストが pass し続けた
- テスト自体は変更されていない
- 戻された変更があれば、その理由が明確
- スコープ外の改善が混じっていない (依頼の対象 / 観点に絞られているか)

## 次のステップ

タスク完了の場合: 変更をクローズ (`project-bootstrap` skill の Step 9 参照)。
別の観点で続けてリファクタする場合: 再度 `/refactor <別の観点>`。

# 2026-05-25-propagate-ai-adoption: 寝ている間の自走結果

## 1 行で言うと

project-bootstrap を v0.8.2 まで進め (lint opt-in 化 + arch staged-only 化)、propagate-ai へ適用する **PR #17 を作成** (未マージ)。本番ツリーは一切触れていない。

## ⚠️ 起きたら最初にやること (URGENT)

**ローカル plugin を v0.8.2 に更新する**:
```
/plugin marketplace update rintaro-yamaoka
/reload-plugins
```
理由: v0.8.1 の lint gate は **always-on** で、propagate-ai の `next lint` (ESLint 未設定 → 対話プロンプト → exit 1) を回して **commit を壊す**。v0.8.2 で lint gate を `.bootstrap-lint` opt-in 化したので、更新すれば直る。更新するまで propagate-ai の commit が lint gate でブロックされる可能性がある。

## 残課題

| 識別子 | 状況 | 対応案 |
|---|---|---|
| plugin 更新 | v0.8.1 が稼働中 (lint gate が live リポを壊す) | 上記 2 コマンドで v0.8.2 へ |
| propagate-ai PR #17 | 作成済み・未マージ | triage 確認後マージ。下記違反を先に処理 |
| core→infra/lib 6件 | 明確な debt (port が実装 import = DI 逆転含む) | 別 PR で依存反転 / 純 util は core 内へ |
| lib→app 1件 | `lib/cron/authAndGate`→app | app へ移すか引数渡し |
| infra→lib 8件 | 要判断 (`withDeadline` 等 util) | `allow infra -> lib` 追加 or lib 分割 |
| arch go/rust/ruby extractor | 未対応 (v1 は ts/js/py) | 次回 |

## バックグラウンドプロセス

なし (全て完了・停止済み)。dry-run scan の一時ファイルは破棄済み。

## 触ったファイル

**project-bootstrap (main に push 済み, v0.8.2 = `3571c34`, tag v0.8.0/0.8.1/0.8.2)**:
- 0.8.0: lint gate (`block-commit-if-lint-fails.sh`)
- 0.8.1: duplicate hooks 修正 (plugin.json の hooks 行削除)
- 0.8.2: lint opt-in (`.bootstrap-lint`) + arch staged-only。`templates/.bootstrap-lint` 追加
- `tests/hooks/` 11 suite green

**propagate-ai (本番ツリー未変更。PR #17 のブランチ `feat/bootstrap-adoption` にのみ commit)**:
- `.bootstrap-arch` (依存方向契約) / `.bootstrap-protected` (main/master 保護)
- worktree で作業 → 撤去済み。main は触れていない (uncommitted 46 件そのまま)

## 重要な memory / docs references

- `feedback_bootstrap_is_canonical` — project 固有事情は `.bootstrap-*` で受ける
- `reference_plugin_verification_layers` — always-on gate は既存リポを壊す。実 target で検証必須
- propagate-ai PR: https://github.com/propagate-infra/propagate-ai/pull/17

## 検証手順

```
cd project-bootstrap && bash tests/hooks/run.sh   # SUITES: 11 run, 0 failed
git -C <propagate-ai> status                       # main, uncommitted 46 (未変更)
gh pr view 17 -R propagate-infra/propagate-ai      # OPEN, 未マージ
```

## 次セッションへの起動文

```
docs/handoffs/2026-05-25-propagate-ai-adoption.md を読んで、まず plugin を v0.8.2 に更新。
その後 propagate-ai PR #17 の triage (core→infra の DI 逆転 6件) を一緒に処理するか判断したい。
```

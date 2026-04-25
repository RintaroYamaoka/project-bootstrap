# Changelog

このリポジトリのすべての注目すべき変更はこのファイルに記録する。

形式は [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) に基づく。
バージョニングは [Semantic Versioning](https://semver.org/lang/ja/) に従う。

## [Unreleased]

### Added

- `skills/plan/SKILL.md` — `/plan` skill (探索 → 計画 → 提示)。自明でないタスクの開始時に呼び出し、`Read` / `Grep` / `Glob` のみで探索し、構造化された計画書を出力する。`Edit` / `Write` は禁止。ユーザー承認後に TDD フロー (Red → Green → Refactor) へ移行する。
- `agents/test-writer.md` — TDD Red フェーズを担うサブエージェント。failing テストだけを書く。実装ファイルは触らない。テストを実行して fail を確認するまでが責務。
- `agents/implementer.md` — TDD Green フェーズを担うサブエージェント。failing テストを通す最小の実装だけを書く。テストファイルは編集しない。広めのテストスイートで regression がないことまで確認する。
- `agents/refactorer.md` — TDD Refactor フェーズを担うサブエージェント。テストが pass し続ける範囲で構造改善する。テストは変更しない。
- `commands/red.md`, `commands/green.md`, `commands/refactor.md` — `/red` / `/green` / `/refactor` slash command。それぞれ対応するサブエージェントを起動する thin wrapper。
- `.claude-plugin/marketplace.json` — このリポジトリを自己ホスティング marketplace 化する catalog。`rintaro-bootstrap` marketplace として `project-bootstrap` プラグインを listing する (github source は自リポジトリを指す)。
- `LICENSE` — MIT License。
- `plugin.json` に `homepage` / `repository` / `license` フィールドを追加。

- `hooks/README.md` — hook テンプレート集の運用ガイド。なぜテンプレート止まりか、どこで有効化するかの 3 通り、各テンプレートの意図とカスタマイズ箇所を解説。
- `hooks/hooks.example.json` — 3 つの hook 例 (git commit 前テスト / 実装 edit 後テスト companion 確認 / SessionStart reminder)。`plugin.json` の `hooks` フィールドには登録しないため、デフォルトでは発火しない。
- `examples/README.md` — TDD セッションログを蓄積する場所の運用ガイド。命名規則 / 追加方法 / 注意点を記述。
- `examples/TEMPLATE.md` — セッションログのフォーマット雛形 (タスク → /plan → Red → Green → Refactor → Close → 振り返り)。実プロジェクトで稼働した実例を後日蓄積する。
- `MAINTENANCE.md` — 運用ドキュメント。SemVer 方針 / リリース手順 / 定期レビューの観点 / 新プリミティブ追加の判断基準 / 廃止フロー を記述。プラグインを長く使えるものに育てるための保守規律。

### Changed

- README の install 手順を更新: `claude --plugin-dir` だけでなく `/plugin marketplace add` 経由の install を案内。
- README のライセンス節を「未定」から「MIT」に確定。

## [0.1.0] - 2026-04-25

### Added

- Claude Code プラグインとしての構造を確立
  - `.claude-plugin/plugin.json` — プラグインマニフェスト (name / version / description / author / keywords)
  - `skills/project-bootstrap/SKILL.md` — AI 駆動開発の憲法 (旧 root の SKILL.md を `git mv` で移動)
- `templates/CLAUDE.md` — 新規プロジェクトに配置する CLAUDE.md の雛形
  - プロジェクト概要 / 技術スタック / 開発コマンド / ディレクトリマップ / アーキテクチャ概略 / プロジェクト固有の規約 / 既知の地雷 / AI 作業時の特記事項のスロットを含む
- `README.md` — リポジトリの目的・哲学・使い方・ロードマップ
- `CHANGELOG.md` — このファイル

### Changed

- `SKILL.md` を三層構成 (憲法 / TDD ワークフロー / AI 協働ルール) に再編
  - 憲法層: SOLID / KISS / YAGNI / DRY (Rule of Three) / Fail-fast / Root-cause / Composition over Inheritance / Law of Demeter / アーキテクチャ指針
  - 開発フロー層: Red → Green → Refactor を軸とする TDD 中心のフロー (旧フローを TDD ループに統合)
  - AI 協働ルール層: AI の既定の癖の言語化 / Subagent によるフェーズ分離 / Plan-Execute 二段構え / AI 指示テンプレート / やってよいこと/やってはいけないことの整理

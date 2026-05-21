# Changelog

このリポジトリのすべての注目すべき変更はこのファイルに記録する。

形式は [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) に基づく。
バージョニングは [Semantic Versioning](https://semver.org/lang/ja/) に従う。

## [Unreleased]

## [0.4.1] - 2026-05-21

### Fixed

- **`hooks/require-test-companion.sh` の Windows path 正規化が壊れて全 skip 経路が機能不全だった bug を修正**。Claude Code は Windows 環境で `\` 区切りの絶対 path を JSON-escape 済 (= literal `\\`) で渡してくるが、旧実装は path 正規化を持たず `case` パターン (`*/tests/*` 等の skip ルール) が一切 match しなかった。`tr '\\\\' '/' | tr -s '/'` で確実に正規化する経路に置換 (= `sed -e 's|\\|/|g'` は Git Bash の GNU sed で「unterminated `s' command」を吐いて空文字列を返す)。Windows ユーザーが Edit/Write を呼ぶたびに「テスト書け」blocking が出続けていた重度の hook 誤動作。
- **`scripts/_*` skip ルールを追加**。`scripts/_foo.mjs` のような prefix `_` 付きスクリプトは慣行として ephemeral debug / one-shot recovery 用途 (= test companion を要求するのは過剰)、case パターンで素通しに。
- **`tests/` 配下の深い階層を recursive `find` で拾う fallback を追加**。既存 CANDIDATES は `tests/${NAME}.test.${EXT}` 直下のみだったため、`tests/unit/<layer>/foo.test.ts` のような層別構造で red test 済みでも hook が誤検知していた。

## [0.4.0] - 2026-05-13

### Changed (BREAKING)

- **`skills/project-bootstrap/SKILL.md` を 430 行 → 96 行に prune**。Anthropic 公式 best practice ([code.claude.com/docs/en/best-practices](https://code.claude.com/docs/en/best-practices)) の include/exclude 表に従い、exclude 該当節 (SOLID / KISS / YAGNI / DRY / Fail-fast / Root-cause / Composition over Inheritance / Law of Demeter / SOLID 5 原則詳細 / アーキテクチャ指針 / コード品質節) を全削除。これらは Anthropic の言う「Standard language conventions Claude already knows」「Self-evident practices like 'write clean code'」に該当し、bloated CLAUDE.md / SKILL.md は AI に instructions を無視させる ("Bloated CLAUDE.md files cause Claude to ignore your actual instructions")
- 新節「ルールとは」を追加: **ルール = AI が常にそう振る舞うこと**。slash command / 明示呼び出しは advisory にすぎず規律ではない、と明示
- 新節「最高レバレッジ — verification を必ず与える」を追加。Production-affecting な変更は return / commit 前に read-back / assert で実体検証することを要求 (= Anthropic の "single highest-leverage thing")
- AI の癖リストに 6 つ目「**抽象用語に逃げる**」を追加: 「構造」「パターン」「集約」「再設計」「反転」「Bottom-up」のような語を使うときは具体物 (ファイル + 行 + 引用) を必ず添える
- 「**同類のバグが 2 回以上出たら構造の症状を疑う**」を明示 (= Anthropic の "If you've corrected more than twice, A clean session with a better prompt outperforms a long session" のプロジェクトレベル翻訳)

### Removed (BREAKING)

- **`commands/red.md` / `green.md` / `refactor.md` を削除**。slash command は advisory (= ユーザーが叩かないと発動しない) なので規律として機能しない。TDD は hook で deterministic に強制する設計に変更。subagent (`agents/test-writer.md` / `implementer.md` / `refactorer.md`) は残し、SKILL.md から AI が default 経路として呼ぶ
- **`examples/` ディレクトリを削除** (README + TEMPLATE のみで収録 0 件、YAGNI 違反)。必要になった時点で再作成する
- **`hooks/hooks.example.json` を削除**。本番 `hooks/hooks.json` で代替

### Added

- **`hooks/hooks.json` + `.claude-plugin/plugin.json` の `hooks` フィールド登録**: プラグインインストール時にデフォルト発火する hook を 2 つ提供:
  - **Hook A** (`hooks/require-test-companion.sh`): `PreToolUse on Edit|Write|MultiEdit`。実装ファイルを編集する瞬間、対応する test ファイルが慣例パターン (`*.test.*` / `*.spec.*` / `*_test.*` / `test_*.py` / `_test.go` / `spec/*_spec.rb` / `tests/` / `__tests__/`) で見つからなければ `exit 2` で **blocking**。「テスト書かずに実装」を構造的に不可能にする (= Red phase 強制)
  - **Hook B** (`hooks/block-commit-if-tests-fail.sh`): `PreToolUse on Bash` for `git commit`。プロジェクトマーカー (`package.json` / `pyproject.toml` / `go.mod` / `Cargo.toml` / `Gemfile`) から test command を自動検出して実行、fail なら `exit 2` で **blocking**

### Pruned (non-breaking)

- `templates/CLAUDE.md` を 100 行 → 55 行に削減。ガイドライン要点 5 個 (Code is Truth / TDD / SOLID-KISS-YAGNI / 環境隔離 / AI 協働ルール) を削除 (= 詳細は SKILL.md にあり、CLAUDE.md には書き写さない)
- `README.md` を 147 行 → 60 行に削減。Phase 1-7 完了表、旧ディレクトリ構成図、ロードマップを削除
- `MAINTENANCE.md` を 126 行 → 28 行に削減。リリース手順のみ残し、定期レビュー観点 / 新プリミティブ判定基準 / 廃止フロー節を削除 (= YAGNI、必要になったら再導入)
- `hooks/README.md` を 80 行 → 46 行に削減。「なぜテンプレ止まりか」「3 通りの有効化方法」節を削除 (= hooks.json デフォルト発火化により不要)

## [0.3.0] - 2026-04-26

### Added

- `skills/project-bootstrap/SKILL.md` の Part 1 (憲法) に「**環境隔離 — プロジェクト単位で依存を閉じ込める**」原則を追加。グローバルにライブラリをインストールしないこと、CLI ツールは `uv tool install` / `pipx` / `cargo install` 等の isolated tool installer 経由で入れること、`.venv` / `node_modules` 等は必ず `.gitignore` で除外することを規定。Python / Node / Rust / Go / Ruby の言語別具体策を表で添付。
- `templates/CLAUDE.md` のガイドライン要点リストに環境隔離原則の bullet を 1 行追加。

## [0.2.0] - 2026-04-26

### Added

- `skills/plan/SKILL.md` — `/plan` skill (探索 → 計画 → 提示)。自明でないタスクの開始時に呼び出し、`Read` / `Grep` / `Glob` のみで探索し、構造化された計画書を出力する。`Edit` / `Write` は禁止。ユーザー承認後に TDD フロー (Red → Green → Refactor) へ移行する。
- `agents/test-writer.md` — TDD Red フェーズを担うサブエージェント。failing テストだけを書く。実装ファイルは触らない。テストを実行して fail を確認するまでが責務。
- `agents/implementer.md` — TDD Green フェーズを担うサブエージェント。failing テストを通す最小の実装だけを書く。テストファイルは編集しない。広めのテストスイートで regression がないことまで確認する。
- `agents/refactorer.md` — TDD Refactor フェーズを担うサブエージェント。テストが pass し続ける範囲で構造改善する。テストは変更しない。
- `commands/red.md`, `commands/green.md`, `commands/refactor.md` — `/red` / `/green` / `/refactor` slash command。それぞれ対応するサブエージェントを起動する thin wrapper。
- `.claude-plugin/marketplace.json` — このリポジトリを自己ホスティング marketplace 化する catalog。`rintaro-yamaoka` marketplace として `project-bootstrap` プラグインを listing する (github source は自リポジトリを指す)。
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

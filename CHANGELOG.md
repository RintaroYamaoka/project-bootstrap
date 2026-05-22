# Changelog

このリポジトリのすべての注目すべき変更はこのファイルに記録する。

形式は [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) に基づく。
バージョニングは [Semantic Versioning](https://semver.org/lang/ja/) に従う。

## [Unreleased]

## [0.6.0] - 2026-05-23

### Added

- **`skills/handoff/SKILL.md` を新規追加** (= session の cold restore を default 挙動化)。session 終了前 / `/clear` 前 / 並走 Claude に context を渡す前に AI が default で呼ぶ。`docs/handoffs/<YYYY-MM-DD>-<topic>.md` を 7 節 (1 行サマリ / 残課題表 / バックグラウンドプロセス / 触ったファイル分類 / memory references / 検証手順 / コピペ起動文) で生成する規律。slash command `/handoff` でも明示呼び出し可能。AI が「次の Claude が cold restore できるか」を 1 回ごとに考える経路を default 化する。

- **`skills/incident/SKILL.md` を新規追加** (= 事故記録 + memory 昇格を default 挙動化)。fix / revert / hotfix commit / user 叱責 / 「やり直し」言及 / 同問題 2 回以上発生 の後に AI が default で呼ぶ。`docs/incidents/<YYYY-MM-DD>-<topic>/README.md` を 4 節 (ミス一覧 / 真因 / 構造的再発防止 / 関連 memory・docs) で生成。**書きっぱなしを禁止**し、memory `feedback_*.md` / `reference_*.md` への昇格まで責務に含める (= incident は session 開始時に load されないが memory は load される、これを欠くと再発抑止しない)。slash command `/incident` でも明示呼び出し可能。

- **`templates/docs/` 雛形を追加**。AI 駆動開発で本当にレバレッジが出る 3 ディレクトリのみ提供:
  - `templates/docs/README.md` — 採用 3 dir の歩き方、真実の所在表、失敗兆候 4 種 (権威分散 / handoff 重複化 / ADR 未定着 / business 固有名混入)、不採用 5 dir (current / exploring / reference / ops / archive) の理由
  - `templates/docs/handoffs/TEMPLATE.md` — 7 節 cold restore 骨格 (= 1 行サマリ / 残課題 / バックグラウンドプロセス / 触ったファイル / memory references / 検証手順 / コピペ起動文)
  - `templates/docs/decisions/TEMPLATE.md` — ADR template (Status / Date / Deciders / References / Context / Decision / Consequences)
  - `templates/docs/incidents/TEMPLATE.md` — incident template (ミス一覧 / 真因 / 構造的再発防止チェックリスト / 関連 memory)

- **`skills/project-bootstrap/SKILL.md` に新節「external memory として docs/ を整備」を追加**。採用 3 dir / 真実の所在表 / 失敗兆候 4 種 / 関連 skill リンクを規律として記述。CLAUDE.md / コード / memory との二重化を禁じる。

- **「迷ったとき」チェックリストを 8 → 11 項目に拡張**: handoff 書き残し / incident + memory 転記 / ADR 記述 を追加。

### Changed

- **`.claude-plugin/plugin.json` / `marketplace.json` の `description` を更新**: skills 4 個構成 (project-bootstrap / plan / handoff / incident) と「external memory として docs/ 整備」を明示。
- **`README.md` の「提供物」表を更新**: `skills/handoff/` / `skills/incident/` / `templates/docs/` の 3 行を追加、skill 一覧と install 手順を 4 skill 構成に書き直し。
- **`README.md` の「使い方」step 2 を更新**: `templates/docs/` のコピー手順を追記、3 dir 採用と 5 dir 不採用の方針を明示。

### Rationale

propagate-ai リポジトリの docs/ 8 ディレクトリ構造 (= current/ exploring/ decisions/ reference/ ops/ handoffs/ incidents/ archive/) を AI 駆動レバレッジ基準で精査した結果、`handoffs/` (= cold restore) と `decisions/` (= ADR) と `incidents/` (= 事故記録 + memory 昇格) の 3 dir が本当に効くと判定。残り 5 dir は CLAUDE.md / コード / memory で代替できるか graveyard 化する典型兆候 (= `archive/` 参照 2 hit / `decisions/` 1 件 / `exploring/` 肥大化 / `current/` と CLAUDE.md 重複) が出ており、雛形に含めないことで失敗を構造的に防ぐ。

handoff / incident は **slash command で起動する advisory 形式ではなく AI default 挙動として書く** ことが本旨 (= ルール = default + hook 強制原則)。skill description で「いつロードするか」を明示し、AI 自身が session 終了前 / 事故後に呼ぶ経路を作る。

## [0.5.0] - 2026-05-23

### Added

- **並列 Claude 安全運用の hook 3 個をデフォルト発火に追加** (= `plugin.json` の `hooks` フィールド経由)。AI 駆動開発で複数ターミナル / 別 session の Claude を並走させる場合に、互いの作業を消す / 巻き込む経路を default で blocking する規律。SKILL.md advisory ではなく hook で deterministic に強制する (= Anthropic 公式「Hooks are deterministic, CLAUDE.md is advisory」整合):
  - **Hook C** (`hooks/block-dangerous-git-ops.sh`): `PreToolUse on Bash`。destructive git op を `exit 2` で blocking。検出: `git reset --hard` (uncommitted 全消去) / `git push -f` / `--force` (remote の他人 commit 消去、ただし `--force-with-lease` は競合検出付きで素通し) / `git checkout -- .` / `<path>` (unstaged 消去) / `git restore .` / `--staged .` (全 restore) / `git clean -f` / `-fd` / `-fx` (untracked 消去) / `git branch -D` (未 merge branch 強制削除)
  - **Hook D** (`hooks/block-add-all.sh`): `PreToolUse on Bash`。bulk-staging を `exit 2` で blocking。検出: `git add -A` / `--all` / `.` / `-u` / `--update` (cwd 配下全 stage) / `git commit -a` / `-am` / `--all` (全 tracked auto-stage) / `git stash -u` / `--include-untracked` / `git stash` (path 指定なし、全 modified 退避)。**自分が編集した file を個別 path 指定で add する**規律を強制。`git add path/to/file` は素通し
  - **Hook E** (`hooks/block-cross-claude-wip.sh`): `PreToolUse on Bash` for `git commit`。当 session で編集していない file が staged にあれば `exit 2` で blocking。仕組み: hook input の `transcript_path` から JSONL を読み、`Edit` / `Write` / `MultiEdit` / `NotebookEdit` の `file_path` / `notebook_path` を抽出して self-edited set を build、`git diff --cached --name-only` の各 file が含まれているか check。`--amend` は対象外。transcript path 取得不能環境では fail-open (= 素通し + warning) で AI 有用性を優先

- **`skills/project-bootstrap/SKILL.md` の verification 章を 4 罠に具体化**。「実体を read-back で検証」だけでは AI が default で踏む 4 つの落とし穴を明示:
  - **罠 1 — silent failure を「正常」と読む**: ORM/SDK が missing field / drop 済 column を throw せず空返却する設計に依存して 0 件返却を success と読む。`count == expected` を必ず assert、200 OK だけでなく content-type / body 構造まで assert
  - **罠 2 — 既存リソースの actual capability を表記で推測する**: 資格情報 / token / API key / feature flag / 設定値の現在能力を、コメント / 変数名 / 定数で代用しない。新 code 追加判断の前に actual state を 1 query で確認
  - **罠 3 — escape 多段を脳内計算する**: shell → JSON → 言語 string → 外部 storage の多段 escape は書込後に必ず read-back し、stored 文字列と入力文字列の完全一致を assert
  - **罠 4 — pattern を広げる fix の cohort 副作用を測らない**: regex / filter / 集計範囲を拡張する fix は対象 cohort の前後数を取り、想定外の cohort 増加が無いか assert

- **AI の癖を 6 → 9 個に拡張**:
  - **7. 「ない / 不可能 / 該当なし」を grep の不一致で断定する** — app code grep が hit しない ≠ 機能不在 (= 設定 / 資格情報 / 外部リソース経由で可能なケースが残る)。外部 API の error code を即「権限不足」と一般化しない。不在主張の前に対象リソース自身への diagnostic を最低 1 回叩く
  - **8. ルール / memory / fix を射程外まで過剰一般化する** — 「X は NG」を文字通り全 X に適用、本来 OK だった subset まで潰す。ルール記述時は「射程: ~ のみ。~ は除外」を必ず添える
  - **9. 共有環境を独占資源として扱う** — `git add -A` で他 session の WIP を巻き込む、destructive git op で他人の commit / untracked を消す。commit は個別 path 指定 / destructive op は user 明示承認 / 並走は `git worktree add` で物理隔離

- **新節「並列 Claude 安全運用」を SKILL.md に追加**。同一 working tree 共有 vs `git worktree add` 物理隔離の選択表、hook で強制される事項のリスト、hook で強制しきれない手順 (= `git status --porcelain` 確認 / lock file diff 確認 / destructive op 前の user 確認)

- **新節「完遂責任 — bug fix と同 PR で cohort audit」を SKILL.md に追加**。問い合わせ件数は氷山の一角で同根 silent dropout が桁違いに居る前提、fix commit と同 PR に同根 cohort の SQL / grep / log scan 結果を含めることを規定

- **「迷ったとき」チェックリストを 6 → 8 項目に拡張** (= cohort audit / 巻き込み確認を追加)

### Changed

- **`hooks/hooks.json` の `PreToolUse on Bash` matcher 配下に新 hook 3 個を追加**。発火順は `block-add-all.sh` → `block-dangerous-git-ops.sh` → `block-cross-claude-wip.sh` → 既存 `block-commit-if-tests-fail.sh` (= 巻き込み block を test 実行より前に置く)
- **`.claude-plugin/plugin.json` / `marketplace.json` の `description` を更新**: 並列 Claude 安全運用 / verification 4 罠 / AI 癖 9 個 / cohort audit を明示
- **`hooks/README.md` を 50 行 → 100 行に拡張**: 新 hook 3 個の検出 pattern 表、発火順、bypass 手順を追記
- **`README.md` の「何を強制するか」を 4 項目 → 6 項目に拡張**: 並列 Claude 安全運用節、AI 癖 9 個への変更、bug fix 完遂責任を反映

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

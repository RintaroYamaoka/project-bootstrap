---
name: project-bootstrap
description: AI 駆動開発の規律。ルール = AI の default 挙動 + hook 強制。Anthropic 公式 best practice (verification 最高レバレッジ / hooks deterministic / CLAUDE.md advisory) に整合する。新機能・バグ修正・リファクタ・調査など、あらゆるコーディング作業で常にロードする。
---

# AI 駆動開発の規律

## ルールとは

**ルール = AI が常にそう振る舞うこと**。

ユーザーが明示的にコマンドを叩いて初めて発動する形式 (slash command / 明示 subagent 呼び出し) は advisory にすぎず、忘れられる。本プラグインのルールは hook で deterministic に強制される。違反は blocking される。

> Anthropic 公式 (https://code.claude.com/docs/en/best-practices):
> "Hooks are deterministic and guarantee the action happens. Unlike CLAUDE.md instructions which are advisory."

## 最高レバレッジ — verification を必ず与える

Production-affecting な変更 (= 外部 API write / DB write / repo push / 設定書込 / 公開サイトへの影響) を含む実装は、return / commit の前に **実体を read-back で検証** してから完了とする。これを欠くと「return value が success だが live は反映されていない」事故が起きる。

実装パターン:

- 書込 → 同じデータを read endpoint で取り直す → 一致を assert
- 一致しなければ throw / exit non-zero
- `success` / `ok` を return 値**だけ**で判断しない

> Anthropic 公式:
> "Give Claude a way to verify its work. This is the single highest-leverage thing you can do. If you can't verify it, don't ship it."

## AI の癖 — これらは default で起きる

AI コーディングエージェントは放っておくと以下をやる。本プラグインの hook と TDD ループはこれらを default で抑えるためにある。

1. **実装を先に書く** — テストは後付け。→ hook A が「対応 test なき実装ファイル編集」を blocking
2. **ハルシネーション** — 存在しない API / フィールドを使う。→ 書く前に対象コードを `Read` で確認
3. **スコープ拡大** — 依頼にない「ついでの改善」を加える。→ 1 PR = 1 責務
4. **症状を隠す** — fallback / try-except / retry でバグを覆う。→ Fail-fast / 根本修正
5. **既存パターン無視** — 新パターンを持ち込みたがる。→ 既存コードを先に読む
6. **抽象用語に逃げる** — 「構造」「パターン」「集約」「再設計」「反転」「Bottom-up」のような語で実体不在の発言をする。→ **抽象用語を使ったら同時に具体物 (ファイル + 行番号 + 引用) を 1 つ以上添える。添えられないなら「読んでいないので発言できない」と返す**

## TDD は default 挙動

Red → Green → Refactor を作業の軸とする。

- **Red**: 振る舞いを failing test として書く。pass してしまうテストは「まだその時期ではない」。`agents/test-writer.md` の subagent が担う
- **Green**: failing test を通す最小実装だけ書く。要求されていない機能を加えない。`agents/implementer.md` の subagent が担う
- **Refactor**: テストが pass している状態で構造を改善する。テストは変更しない。`agents/refactorer.md` の subagent が担う

hook A (`hooks/hooks.json`) が「対応 test 不在の実装ファイル編集」を default で blocking する。slash command で起動する形式は採用しない (= 規律ではなく option になるため)。

書くテストの順序:

1. 正常系の最小ケース
2. 境界条件 (空 / null / 最小 / 最大 / 上限)
3. 失敗パス (不正入力でどう fail するか)
4. **Verification observation** — production-affecting なら read-back / live assert を含むテスト

## バグは根本を修正する

1. **Red**: バグを再現する failing test を書く (= 回帰テスト)
2. **Green**: 原因の層 / 責務を特定し、根本を修正する
3. **Refactor**: 同類のバグが入りにくい構造に整える

症状対応の兆候 (検出したら止まる):

- 壊れた状態を隠すための sort / filter / retry / fallback の追加
- エラーを握り潰す catch
- 共通コードを触らないための処理の複製

**同類のバグが 2 回以上出たら構造の症状**を疑う。局所修正をやめて、port から destructive 経路を物理削除する / 判定境界を純関数に集約する / 不変条件を型として表現する、などの構造変更を検討する。

> Anthropic 公式:
> "If you've corrected Claude more than twice on the same issue, the context is cluttered with failed approaches. A clean session with a better prompt almost always outperforms a long session with accumulated corrections."

## 環境隔離

プロジェクトが import するライブラリは project-local に閉じる。グローバルにインストールしない。

| 言語 | ライブラリ依存 | CLI ツール |
|---|---|---|
| Python | `.venv` + `pyproject.toml` | `uv tool install` / `pipx` |
| Node | `package.json` + `node_modules` | `npm i -g` (CLI のみ) |
| Rust | `Cargo.toml` | `cargo install` |
| Go | `go.mod` | `go install` |
| Ruby | `Gemfile` + bundler | `gem install` (CLI のみ) |

隔離環境ディレクトリ (`.venv/`, `node_modules/`, `target/`, `vendor/` 等) は `.gitignore` で除外する。新規環境で宣言された手順 (`uv venv && uv pip install -r requirements.txt` 等) のみで再現できることを完了条件とする。

## 迷ったとき

1. タスクを 1 文で述べられるか
2. 責務は 1 つに絞れるか
3. failing test を書けるか
4. 結果を **verification (read-back / assert)** で確認できるか
5. これは根本修正か (= 症状対応の兆候はないか)
6. 既存パターンに合わせているか

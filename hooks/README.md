# hooks/

このディレクトリは、`project-bootstrap` の原則を **機械的に強制するための hook テンプレート集**。

## なぜテンプレート止まりか

hooks は **プロジェクト固有の値** (テスト実行コマンド、対象ディレクトリ、対象ファイル拡張子など) に強く依存する。1 つの汎用 hook を全プロジェクトに自動適用すると誤発火する。

そのため、このディレクトリは:

- **テンプレート** として提供される (`hooks.example.json`)
- プラグインがインストールされても **自動発火しない** (`plugin.json` の `hooks` フィールドは未設定)
- 各プロジェクトで適応・有効化する

## 有効化の方法

3 通りある。

### 方法 A: プロジェクトの `.claude/settings.json` に組み込む (推奨)

各プロジェクトの実情に合わせて `hooks.example.json` の内容を `.claude/settings.json` の `hooks` キーに移植し、test command などを書き換える。プロジェクト固有値が含まれるので、ここで管理するのが自然。

### 方法 B: このプラグインを fork して `plugin.json` で参照

```json
// .claude-plugin/plugin.json
{
  ...
  "hooks": "./hooks/hooks.json"
}
```

fork したプラグインの `hooks/hooks.json` を編集する。チームで共有する場合に向く。

### 方法 C: `userConfig` 経由で設定値を埋める

プラグインの `plugin.json` に `userConfig` を追加し、test command などを install 時にユーザーから受け取る。hook 内で `${user_config.test_command}` として参照する。汎用配布向きだが、細かい挙動の差異を吸収しきれないので Phase 5 では採用しない。

詳細は [Claude Code Hooks ドキュメント](https://code.claude.com/docs/en/hooks) と [Plugin reference - Hooks](https://code.claude.com/docs/en/plugins-reference#hooks) を参照。

## 用意されているテンプレート

`hooks.example.json` には以下の hook 例が含まれる。各セクションは独立しているので、必要なものだけ抜き出して使う。

### 1. `PreToolUse` on `Bash` — git commit 前にテストを走らせる

`Bash` ツール経由で `git commit` が呼ばれたとき、コミット前にテストを実行し、fail なら exit 2 で **コミットを中断** する。

**カスタマイズが必要な箇所:**
- テスト実行コマンド (`npm test` / `pytest` / `cargo test` など)

**意図する効果:**
- failing テストがある状態でのコミットを禁止
- TDD の Red 状態を残したまま push してしまう事故を防ぐ

### 2. `PostToolUse` on `Write|Edit` — 実装ファイル編集後にテストの companion を確認

実装ファイル (例: `src/`) が編集されたとき、対応するテストファイル (例: `tests/`) が同じセッションで触られているかをチェックし、なければ警告。

**カスタマイズが必要な箇所:**
- 実装ファイルのパスパターン
- テストファイルの命名 / 配置規則

**意図する効果:**
- 「実装だけ書いてテストを書かない」状態を可視化
- TDD の Red を飛ばして Green に入る習慣を抑制

### 3. `SessionStart` — プラグインがロードされたことを表示

セッション開始時に project-bootstrap の reminder を表示。

**意図する効果:**
- 開発開始時に原則を意識させる
- noisy になりがちなので、必要なら無効化

## 注意

- hooks は **AI に対する強制機構** であって、人間の作業フローを縛るものではない。AI が想定外の動きをしないためのガードレールとして使う。
- 過度に厳しい hooks は AI を行き詰まらせる。**最小限から始めて、実際に困った場面に対応する形で増やす**。
- hook script の標準入力には Claude Code から JSON が渡される。詳しくは公式ドキュメントを参照。

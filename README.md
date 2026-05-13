# project-bootstrap

AI 駆動開発の規律を **hook で deterministic に強制する** Claude Code プラグイン。

ルール = AI の default 挙動 + hook 強制。slash command や明示呼び出しで発動する advisory 形式は採用しない (= 忘れられるため)。Anthropic 公式 best practice ([code.claude.com/docs/en/best-practices](https://code.claude.com/docs/en/best-practices)) の整合: verification 最高レバレッジ / hooks deterministic / CLAUDE.md は prune して短く保つ。

## 何を強制するか

- **テスト先行**: 実装ファイルを編集する瞬間、対応する test ファイルが無ければ blocking (Red phase 強制)
- **failing test での commit 禁止**: `git commit` 前に test 実行、fail なら blocking
- **verification 最高レバレッジ**: production-affecting な変更は read-back / live assert で実体確認してから完了とする (`SKILL.md` に規定)
- **AI の癖を抑止**: 実装先行 / ハルシネーション / スコープ拡大 / 症状隠蔽 / 既存パターン無視 / 抽象用語に逃げる の 6 癖を `SKILL.md` で明示

## 提供物

| 提供物 | 内容 |
|---|---|
| `skills/project-bootstrap/SKILL.md` | 規律本体 (ルール = default 挙動 / verification / TDD / AI 癖 / バグ根本修正 / 環境隔離) |
| `skills/plan/SKILL.md` | `/plan` — 探索 → 計画 → 提示。実装前に計画書を出力 |
| `agents/test-writer.md` `implementer.md` `refactorer.md` | TDD Red / Green / Refactor を担う subagent |
| `hooks/hooks.json` | 上記 2 hook を `plugin.json` 経由でデフォルト発火 |
| `templates/CLAUDE.md` | 新規プロジェクト用 CLAUDE.md 雛形 (Anthropic exclude 表で prune 済) |

## 使い方

### 1. プラグイン install

```bash
/plugin marketplace add RintaroYamaoka/project-bootstrap
/plugin install project-bootstrap@rintaro-yamaoka
```

検証用に都度ロード:

```bash
claude --plugin-dir /path/to/project-bootstrap
```

### 2. 新規プロジェクトに CLAUDE.md を置く

`templates/CLAUDE.md` をプロジェクト root にコピーして、各スロットを埋める。規律は本プラグインが提供するので CLAUDE.md には書き写さない。

```bash
cp /path/to/project-bootstrap/templates/CLAUDE.md /path/to/your-project/CLAUDE.md
```

### 3. Claude Code でそのプロジェクトを開く

- `CLAUDE.md` が自動ロード
- 実装ファイルを編集しようとすると hook A が対応 test を要求 (= Red phase 強制)
- commit 前に hook B が test 実行
- `project-bootstrap` skill が必要に応じて参照される

## バージョン / 保守

[CHANGELOG.md](./CHANGELOG.md) / [MAINTENANCE.md](./MAINTENANCE.md) を参照。SemVer に従う。

## ライセンス

MIT License — [LICENSE](./LICENSE) を参照。

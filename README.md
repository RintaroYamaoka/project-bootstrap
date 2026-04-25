# project-bootstrap

AI 駆動開発の **憲法 (不変の原則)**、**TDD 中心の作業フロー**、**AI 協働ルール** を束ねた Claude Code プラグイン。

新規プロジェクトの立ち上げ時に導入することで、AI を多用しながらも SOLID / レイヤー分離・TDD などの原則を維持して開発を進められる。

## 何のためのリポジトリか

AI 駆動開発は速いが、放っておくとコードベースが散らかる。Anthropic や Cursor の開発者は、**規律を仕組みで強制する** ハーネス (subagent / slash command / hooks) を整えることで、AI の癖 (実装先行・ハルシネーション・スコープ拡大・症状隠蔽) を抑え込んで開発している。

このリポジトリは、その仕組みを **複数のプロジェクトに渡って再利用できる形** で整える試み。各プロジェクトに毎回コピペするのではなく、プラグインとして配布する。

## 哲学

- **Code is Truth** — 振る舞い仕様はテストで表現し、中間ドキュメント仕様を持たない。コードと別形式の仕様は最終的に必ず乖離する。
- **AI 駆動開発 × クリーンアーキテクチャ** — AI で量を出しつつ、SOLID / レイヤー分離で構造を保つ。
- **規律を仕組みで強制する** — markdown に「TDD でやれ」と書くだけでは AI は従わない。subagent / hooks / slash command で機械的に強制する。

## 提供物

| 提供物 | 内容 | 状態 |
|---|---|---|
| `project-bootstrap` skill | 不変の原則 (SKILL.md) — SOLID / KISS / YAGNI / TDD ワークフロー / AI 協働ルール | 完了 |
| `templates/CLAUDE.md` | 新規プロジェクト用 CLAUDE.md 雛形 | 完了 |
| `/plan` skill | 探索 → 計画 → 提示の流れを skill 形式で提供。`Edit` / `Write` 禁止で計画書を出力 | 完了 |
| `test-writer` / `implementer` / `refactorer` subagent | TDD の Red / Green / Refactor を分離して担う | 完了 |
| `/red` `/green` `/refactor` slash command | TDD ループの primitive | 完了 |
| Hooks テンプレート | 規律を機械的に強制する hook テンプレート集 (各プロジェクトで適応) | 完了 |
| プラグイン marketplace 配布 | 各プロジェクトから `/plugin install` で導入できる形 | 完了 |

## ディレクトリ構成

```
project-bootstrap/
├── .claude-plugin/
│   └── plugin.json          # プラグインマニフェスト
├── skills/
│   └── project-bootstrap/
│       └── SKILL.md         # 憲法 (原則と作業フロー)
├── templates/
│   └── CLAUDE.md            # 新規プロジェクト用 CLAUDE.md 雛形
├── README.md
└── CHANGELOG.md
```

```
project-bootstrap/
├── .claude-plugin/
│   └── plugin.json
├── skills/
│   ├── project-bootstrap/SKILL.md   # 憲法
│   └── plan/SKILL.md                # /plan skill
├── agents/
│   ├── test-writer.md               # TDD Red phase
│   ├── implementer.md               # TDD Green phase
│   └── refactorer.md                # TDD Refactor phase
├── commands/
│   ├── red.md                       # /red command
│   ├── green.md                     # /green command
│   └── refactor.md                  # /refactor command
├── hooks/
│   ├── README.md                    # hook テンプレートの運用ガイド
│   └── hooks.example.json           # コピー & 適応用テンプレート
├── templates/
│   └── CLAUDE.md
├── README.md
├── CHANGELOG.md
└── LICENSE
```

Phase が進むと `examples/` が追加される。

## 使い方

### 新規プロジェクトに導入する

#### 1. プラグインを Claude Code に認識させる

このリポジトリは Claude Code の **marketplace** として機能する (`.claude-plugin/marketplace.json` を持つ)。

```bash
# marketplace を追加
/plugin marketplace add RintaroYamaoka/project-bootstrap

# プラグインを install (rintaro-bootstrap = marketplace 名)
/plugin install project-bootstrap@rintaro-bootstrap
```

検証用に都度ロードするだけなら:

```bash
claude --plugin-dir /path/to/project-bootstrap
```

詳細は [Claude Code 公式ドキュメント](https://code.claude.com/docs/en/plugin-marketplaces) を参照。

#### 2. 新規プロジェクトに CLAUDE.md を置く

`templates/CLAUDE.md` を新規プロジェクトの root にコピーし、各セクションを埋める。

```bash
cp /path/to/project-bootstrap/templates/CLAUDE.md /path/to/your-new-project/CLAUDE.md
```

埋めるスロット:

- プロジェクト概要
- 技術スタック
- 開発コマンド (test / build / lint / run)
- ディレクトリマップ
- アーキテクチャ概略
- プロジェクト固有の規約
- 既知の地雷
- AI 作業時の特記事項

**不変の原則はこのファイルに書き写さない**。プラグインの skill が提供する。

#### 3. Claude Code でそのプロジェクトを開く

`CLAUDE.md` が自動で context にロードされ、必要に応じて `project-bootstrap` skill が呼び出される。
原則違反 (実装先行・ハルシネーション等) があれば skill の内容に基づいて Claude が自己修正する。

## ロードマップ

このプラグインは段階的に組み上げる。各 Phase で実利用による価値を確認してから次に進む。

| Phase | 内容 | 状態 |
|---|---|---|
| 1 | プラグイン構造 / SKILL.md / CLAUDE.md 雛形 / README / CHANGELOG | 完了 |
| 2 | `/plan` skill (MVP) | 完了 |
| 3 | TDD subagent 群 + slash command 群 (`test-writer` / `implementer` / `refactorer` / `/red` / `/green` / `/refactor`) | 完了 |
| 4 | プラグイン marketplace 配布 | 完了 |
| 5 | Hooks による規律の機械的強制 (テンプレート提供) | 完了 |
| 6 | TDD セッションログのサンプル (`examples/`) | 次 |
| 7 | 進化機構 (定期レビューと更新の運用) | 計画中 |

## バージョン

セマンティックバージョニング ([SemVer](https://semver.org/)) に従う。
変更履歴は [CHANGELOG.md](./CHANGELOG.md) を参照。

## ライセンス

MIT License — 詳細は [LICENSE](./LICENSE) を参照。

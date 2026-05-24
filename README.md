# project-bootstrap

AI 駆動開発の規律を **hook で deterministic に強制する** Claude Code プラグイン。

ルール = AI の default 挙動 + hook 強制。slash command や明示呼び出しで発動する advisory 形式は採用しない (= 忘れられるため)。Anthropic 公式 best practice ([code.claude.com/docs/en/best-practices](https://code.claude.com/docs/en/best-practices)) の整合: verification 最高レバレッジ / hooks deterministic / CLAUDE.md は prune して短く保つ。

## 何を強制するか

- **テスト先行**: 実装ファイルを編集する瞬間、対応する test ファイルが無ければ blocking (Red phase 強制)
- **failing test での commit 禁止**: `git commit` 前に test 実行、fail なら blocking
- **依存方向の強制 (architecture)**: project-local の `.bootstrap-arch` で宣言した layer 依存方向に反する import を blocking。edit 時に早期 block (`block-cross-layer-import.sh`)、commit 時に全 file を権威検証 (`block-arch-violations.sh`)。cross-layer は default-deny。SOLID を散文で recite するのではなく、依存辺を deterministic に強制する
- **並列 Claude 安全運用 + 並列開発フロー (sprint)**: 防御 (= 作業を消す/巻き込む経路の blocking) に加え、1 feature を複数 Claude で分業して組み戻す generative フロー
    - `git add -A` / `git commit -a` / `git stash` (path 指定なし) 等の bulk-staging を blocking
    - `git reset --hard` / `git push -f` / `git restore .` / `git clean -fd` / `git branch -D` を blocking (※ `--force-with-lease` は除外)
    - `git commit` 直前に当 session で編集していない file が staged にあれば blocking (`--amend` 含む)
    - `.bootstrap-protected` で宣言した branch への直接 push を blocking (opt-in、feature branch + PR / integrate skill 経由に矯正)
    - `sprint-plan` で scope 非重複 task に分解 → worktree の `.bootstrap-lane` 範囲外編集を blocking → `integrate` で依存順 merge + 統合 verify
- **verification 最高レバレッジ**: production-affecting な変更は read-back / live assert で実体確認してから完了とする。silent failure / 既存リソース表記推測 / escape 多段 / pattern 拡張 cohort 副作用の 4 罠を `SKILL.md` で明示
- **AI の癖を抑止**: 実装先行 / ハルシネーション / スコープ拡大 / 症状隠蔽 / 既存パターン無視 / 抽象用語に逃げる / 不在を grep 断定 / ルール過剰一般化 / 共有環境独占 の 9 癖を `SKILL.md` で明示
- **bug fix 完遂責任**: user-facing bug の fix は同 PR で同根 cohort audit を要求 (= 報告 N 件の裏で silent dropout が桁違いに居る前提)
- **external memory として docs/ 整備**: `docs/handoffs/` (cold restore) / `docs/decisions/` (ADR) / `docs/incidents/` (事故記録 + memory 昇格) の 3 dir に絞る。`current/` `exploring/` `reference/` `ops/` `archive/` は採用しない (= CLAUDE.md / コード / memory で代替できるか graveyard 化する)。`skills/handoff/` `skills/incident/` が AI の default 経路で書く

## 提供物

| 提供物 | 内容 |
|---|---|
| `skills/project-bootstrap/SKILL.md` | 規律本体 (ルール = default 挙動 / verification 4 罠 / TDD / AI 癖 9 個 / バグ根本修正 / 依存方向の強制 / 並列開発フロー / 環境隔離 / docs 整備 / cohort audit) |
| `skills/plan/SKILL.md` | `/plan` — 探索 → 計画 → 提示。実装前に計画書を出力 |
| `skills/handoff/SKILL.md` | `/handoff` — session の cold restore に必要な状態を `docs/handoffs/` に書き残す |
| `skills/incident/SKILL.md` | `/incident` — 事故を `docs/incidents/` に記録し、memory `feedback_*` / `reference_*` に昇格させる |
| `skills/sprint-plan/SKILL.md` | `/sprint-plan` — feature を scope 非重複 task に分解し worktree + lane を用意 (並列開発の計画) |
| `skills/integrate/SKILL.md` | `/integrate` — 並列 branch を依存順 merge + 統合 verify + claim close |
| `agents/test-writer.md` `implementer.md` `refactorer.md` | TDD Red / Green / Refactor を担う subagent |
| `hooks/hooks.json` | 9 hook を `plugin.json` 経由でデフォルト発火 (test 先行 / commit 前 test / destructive git op / bulk-stage / cross-session WIP / 直 push / lane 外編集 / 依存方向 edit+commit) |
| `hooks/lib/arch-check.sh` | 依存方向強制エンジン (`.bootstrap-arch` parse / layer 判定 / import 解決)。jq 非依存 |
| `tests/hooks/` | 全 hook の bash テスト (jq 非依存ハーネス、TDD で自己検証) |
| `templates/CLAUDE.md` | 新規プロジェクト用 CLAUDE.md 雛形 (Anthropic exclude 表で prune 済) |
| `templates/.bootstrap-arch` | 依存方向契約の雛形 (layer / alias / allow 辺) |
| `templates/docs/` | 採用 dir (handoffs / decisions / incidents / sprint) の README + TEMPLATE 一式 |

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

### 2. 新規プロジェクトに CLAUDE.md と docs/ を置く

`templates/CLAUDE.md` をプロジェクト root にコピーして、各スロットを埋める。規律は本プラグインが提供するので CLAUDE.md には書き写さない。

```bash
cp /path/to/project-bootstrap/templates/CLAUDE.md /path/to/your-project/CLAUDE.md
cp -r /path/to/project-bootstrap/templates/docs /path/to/your-project/docs
```

`docs/` は 3 dir 構成 (handoffs / decisions / incidents)。`current/` `exploring/` `reference/` `ops/` `archive/` 等は **採用しない** (= CLAUDE.md / コード / memory で代替できるか graveyard 化する)。必要になったら個別に作る。

### 3. Claude Code でそのプロジェクトを開く

- `CLAUDE.md` が自動ロード
- 実装ファイルを編集しようとすると hook A が対応 test を要求 (= Red phase 強制)
- commit 前に hook B が test 実行
- bulk-stage / destructive git op / cross-session WIP 混入を hook C-E が blocking
- `project-bootstrap` / `plan` / `handoff` / `incident` skill が必要に応じて参照される
- session 終了前 / `/clear` 前は `handoff` skill が `docs/handoffs/` に状態を残す
- 事故 / fix / revert / user 叱責の後は `incident` skill が `docs/incidents/` + memory に教訓を残す

## バージョン / 保守

[CHANGELOG.md](./CHANGELOG.md) / [MAINTENANCE.md](./MAINTENANCE.md) を参照。SemVer に従う。

## ライセンス

MIT License — [LICENSE](./LICENSE) を参照。

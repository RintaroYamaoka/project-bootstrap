# 0020 — bootstrap の docs 成果物を `docs/bootstrap/` フォルダ 1 つに集約する

- **Status**: Accepted
- **Date**: 2026-07-30
- **Deciders**: Rintaro Yamaoka
- **References**: [0015](./0015-consolidate-root-markers-into-bootstrap-dir.md) (root マーカーの同型集約) / [0007](./0007-verification-plan-as-merge-precondition.md) (verification plan) / [0004](./0004-parallel-mode-integration-gate.md) (sprint/review gate) / memory `feedback_gate_distribution_coverage` (無音破綻の回避) / `feedback_gate_signal_and_failmode` (fail-mode の選択)

---

## Context (背景)

ADR 0015 は repo root に flat に散らばっていた 6 個の opt-in マーカーを `.bootstrap/` 1 フォルダへ集約した。**同じ散らかりが `docs/` 側に残っていた**。

このプラグインの成果物は `docs/` 直下に 4 ディレクトリを flat に置く: `sprint/` (board.json / .gate / reviews)・`verification/` (branch 別 plan + contracts)・`handoffs/`・`incidents/`。採用 repo の `docs/` にはプロジェクト自身の doc も同居するので、両者が兄弟として混ざる。実例 (dogfood の marketing-app) では `docs/` 直下が以下のようになっていた:

```
docs/
├─ requirements.md        ← kanban-flow (決定ログ・制約)
├─ glossary.md            ← kanban-flow (用語)
├─ はじめに.md            ← kanban-flow
├─ design/               ← kanban-flow (段階設計)
├─ backlog/              ← kanban-flow
├─ decisions/            ← ADR (両者が書く共有面)
├─ sprint/               ← project-bootstrap
├─ verification/         ← project-bootstrap
├─ handoffs/             ← project-bootstrap
└─ incidents/            ← project-bootstrap
```

「どれがプラグインの作業面で、どれが自分たちの doc か」が名前から読めない。`docs/` を一度リセットしたい、といった素朴な操作のたびに人が仕分けを迫られる (実際にそこで判断を要求された)。

検討した案は 2 つ:

1. **フォルダ集約** — 4 つを `docs/bootstrap/<name>` にまとめる。
2. **現状維持** — flat のまま、README で説明する。

案 2 は「説明で補う」= advisory であり、このプラグインが他所で否定している失敗モード (忘れられる・読まれない) そのもの。所在は構造で示すべきで、散文で示すべきではない。

なお **kanban-flow は逆方向の判断をしている** — v0.12 で `docs/kanban-flow/` 接頭辞を「このプラグインの発明」として廃止し `docs/` 直下フラットへ揃えた。両者は矛盾しない: kanban-flow の成果物 (requirements / glossary / roadmap / ADR) は **プロジェクトが読む正本**であってプラグインの作業面ではないので、プラグイン名で囲うのは誤り。対して bootstrap の 4 つは **gate の作業面** (board.json は sprint 終了で腐る ephemeral state、plan は branch 別の一時記録) で、プロジェクトの正本ではない。**囲うべきは道具の作業面であって、成果物の正本ではない。**

## Decision (決定)

**bootstrap 固有の docs 成果物を `docs/bootstrap/<name>` に集約する。設計思想は不変** — ディレクトリの存在 = 有効 (opt-in)、各 gate は自分のディレクトリだけを読む、共有パーサを持たないので SPOF を作らない。

### 対象は 4 つ。`docs/decisions/` は**動かさない**

| ディレクトリ | 移動 | 理由 |
|---|---|---|
| `sprint/` | → `docs/bootstrap/sprint/` | gate の作業面 (ephemeral state) |
| `verification/` | → `docs/bootstrap/verification/` | gate の作業面 (branch 別 plan) |
| `handoffs/` | → `docs/bootstrap/handoffs/` | このプラグインの skill が書く記録 |
| `incidents/` | → `docs/bootstrap/incidents/` | 同上 |
| `decisions/` | **据え置き** | ADR は一般的な工学慣習であって bootstrap の成果物ではない。kanban-flow も同じ場所に書く共有面で、行き先を分けると 1 つの repo の決定記録が 2 系統に割れる |

### 後方互換 (flag day を避ける)

ここは ADR 0015 より**危険度が高い**。マーカーの不在は「その gate が opt-in されていない」だが、**docs ディレクトリの不在も同じく opt-in されていない**と読まれる — つまり flag day で移すと、採用済み repo は plugin 更新の瞬間に sprint gate・review gate・verification gate・wip gate・未隔離編集 gate が**一斉に無音で fail-open** する。これはこのプラグインが最も嫌う破綻の仕方 (memory `feedback_gate_distribution_coverage`)。

よって解決は ADR 0015 と同型の**新優先で旧も読む**:

- 単一権威 `hooks/lib/resolve-docs.sh` の `resolve_docs_dir <top> <name>` が `docs/bootstrap/<name>` (新) を優先し `docs/<name>` (旧) に fallback する。両方在れば新が勝つ。どちらも無ければ新 canonical path を返す (`[ -d ]` の不在判定が従来どおり動く)。
- 全 gate / `hooks/lib/*` / `scripts/doctor.sh` はこの単一 resolver を経由する (各所での直書きパスを廃止 = 信号 drift を防ぐ)。
- **block message も解決結果に従う** (`resolve_docs_label`)。旧レイアウトの repo に `docs/bootstrap/sprint/.gate` へ記録しろと案内すると、人は空ディレクトリへ送られ、そこに書いた記録は gate に読まれない (案内と強制の不一致 = 別種の無音破綻)。
- gate の**自己状態の書き込み例外** (`docs_state_face`) だけは resolver を通さず**両レイアウトを無条件にマッチ**する。この判定はまだ存在しない path を分類する (PreToolUse は書き込み前に走る) ので、新レイアウトを作る最初の board.json を書く瞬間には `docs/bootstrap/sprint/` はまだ無く、resolver は旧側へ倒れて**その file 自身を block してしまう**。この述語は自分が所有する path の fail-open 例外を広げるだけなので、両マッチが厳密に安全側。

### 旧 flat path 撤去の条件 (bound)

旧 path 読みは**移行補助であって恒久仕様ではない**。ADR 0015 と同じく撤去条件を明記して bound する:

> **全 dogfood repo (bootstrap 製の live product 群 — marketing-app / propagate-ai) が `docs/bootstrap/` レイアウトへ移行完了したことを確認したら、旧 `docs/<name>` 読みを `resolve-docs.sh` から削除する。** 削除時は doctor が「旧レイアウト残存」を可視化できると望ましい。

### 歴史的記録は書き換えない

CHANGELOG・ADR 0001〜0019・`docs/bootstrap/incidents/**` / `handoffs/**` の本文は、**書かれた当時のレイアウトを記述した日付つきの記録**なので path 表記を遡って書き換えない。移動後の実体は git が追跡しており、掘るなら git 履歴が正。書き換えるのは live な面 (README / hooks / skills / templates / scripts) だけ。

## Consequences (帰結)

**得るもの**

- 採用 repo の `docs/` 直下から、道具の作業面が 4 つ消える。プロジェクト自身の doc とプラグインの作業面が名前で分かれる。
- 「bootstrap の生成物を全部消す/移す/無視する」が 1 パスで書けるようになる (`.gitignore` / `docs/bootstrap/**` の一括指定)。
- root の `.bootstrap/` と docs の `docs/bootstrap/` が同じ語で対応し、覚える語が 1 つで済む。

**代償 (正直に)**

- **2 系統読む複雑さ**が resolver 1 ファイルに入る。ADR 0015 と同じ負債で、同じ撤去条件で bound する。
- **半移行状態が定義上ありうる** — 例えば board.json は新、review 記録は旧、という repo。新が勝つので旧の記録は**読まれない** (= gate は「レビュー無し」と判断して block する)。fail-closed 側に倒れるので無音バイパスにはならないが、移行時に「なぜ approve が効かないのか」で人が詰まりうる。テストで半移行 4 ケースを固定してある。
- **採用 repo の移行作業は手動** — このプラグインは採用 repo のファイルを勝手に動かさない (ADR 0003 と同じく、採用は人の判断)。doctor が旧レイアウトを可視化するところまでが責務。

# 0015 — root の opt-in マーカーを `.bootstrap/` フォルダ 1 つに集約する

- **Status**: Accepted
- **Date**: 2026-06-26
- **Deciders**: Rintaro Yamaoka
- **References**: [0006](./0006-parallel-default-by-execution-form.md) (wip marker) / [0010](./0010-inject-memory-at-repeat-prone-action.md) (actions marker) / memory `feedback_gate_signal_and_failmode` (fail-mode の選択) / `feedback_gate_distribution_coverage` (配備カバレッジ・無音破綻回避)

---

## Context (背景)

新規プロジェクトに bootstrap を採用すると、opt-in マーカーが repo root **直下に最大 6 個** flat に散らばっていた:
`.bootstrap-arch` / `.bootstrap-protected` / `.bootstrap-lint` / `.bootstrap-wip` / `.bootstrap-actions`、加えて worktree-local な `.bootstrap-lane`。採用 repo の root が散らかる、という体感的な摩擦があった (user 指摘)。

検討した集約案は 2 つ:

1. **フォルダ集約** — 6 個を `.bootstrap/` ディレクトリ配下のマーカー (`.bootstrap/arch` 等) にまとめる。
2. **単一設定ファイル** — `.bootstrap.toml` 一枚に全部のキーを入れる。

案 2 は一見きれいだが **fail-mode 設計と衝突する** (memory `feedback_gate_signal_and_failmode`)。現状は「ファイルの**存在 = 有効**」という安いスイッチで、各 hook が**自分のマーカーだけ**を読む (shell の `test -f` のみ、パーサ不要)。単一ファイル化は (a) shell hook に TOML/YAML パーサを背負わせ、(b) **解析不能時に全 gate が一斉に落ちる単一障害点 (SPOF)** を生む。今は 1 ファイルが壊れても他の関所は生きている。よって**フォルダ集約 (tidy) は得、ファイル集約 (parse 統合) は損**。

## Decision (決定)

**opt-in マーカーを repo root の `.bootstrap/` フォルダ配下に集約する (`.bootstrap/<name>`)。設計思想は不変** — 存在 = 有効、各 hook は自分のマーカーだけを読む、SPOF を作らない。

### 後方互換 (flag day を避ける)

既存採用 repo (dogfood の propagate-ai 等) が plugin upgrade の瞬間に**無音で gate を失う**ことは許容できない (memory `feedback_gate_distribution_coverage`)。よって解決は**新優先で旧も読む**:

- 単一権威 `hooks/lib/resolve-marker.sh` の `resolve_marker <top> <name>` が、`.bootstrap/<name>` (新) を優先し `.bootstrap-<name>` (旧) に fallback する。両方在れば新が勝つ。どちらも無ければ新 canonical path を返す (`[ -f ]` 不在判定が従来どおり動く)。
- 全 hook / `scripts/arch-check.sh` / `scripts/doctor.sh` / `lib/resolve-wip-limit.sh` / `lib/action-gate.sh` はこの単一 resolver を経由する (各所での直書きパスを廃止 = 信号 drift を防ぐ)。

### 旧 flat path 撤去の条件 (bound)

旧 path 読みは**移行補助であって恒久仕様ではない**。2 系統読む複雑さを固定化させないため、撤去条件を明記して bound する:

> **全 dogfood repo (bootstrap 製の live product 群) が `.bootstrap/` レイアウトへ移行完了したことを確認したら、旧 `.bootstrap-<name>` 読みを resolve-marker.sh から削除する。** 削除時は doctor が「旧 path 残存」を可視化できると望ましい。

## Consequences (帰結)

- 採用 repo の root が散らからない。`cp -r templates/.bootstrap your-project/.bootstrap` でフォルダごと配布できる。
- マーカー解決が単一権威に集約され、新旧の差異が 1 ファイルに局在する (撤去も 1 箇所)。
- CI に arch-check を vendor する repo は `resolve-marker.sh` も vendor する必要がある (無いと `.bootstrap/arch` を読めず旧 path のみに退避)。`templates/ci/` の手順に追記済み。
- worktree-local な lane は `.bootstrap/lane` になり、sprint-plan が worktree 内に `.bootstrap/` を作って書き出す。`.gitignore` は `.bootstrap/` を無視する。
- `docs/sprint/.gate` は sprint state であってマーカーではないため、本決定の対象外 (移動しない)。

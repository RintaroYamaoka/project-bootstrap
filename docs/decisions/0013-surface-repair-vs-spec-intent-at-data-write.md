# 0013 — データ修復 (backfill/UPDATE) の瞬間に「修復か仕様か」の意図確認を表面化する

- **Status**: Accepted
- **Date**: 2026-06-25
- **Deciders**: Rintaro Yamaoka
- **References**: [0010](./0010-inject-memory-at-repeat-prone-action.md) (inject-at-action の親 ADR — 再発しやすい行為の瞬間に記録を可視化) / [0001](./0001-subagent-hooks-not-enforced.md) (理解は強制不能 → ack/block でなく可視化) / [0007](./0007-verification-plan-as-merge-precondition.md) (オラクルは AI の外・意図は人間に残る) / appo-followup `docs/incidents/2026-06-25-demo-proposal-lane-cv-notify-misfire` / memory `feedback_verification_design_seams_and_oracle`

---

## Context (背景)

dogfood (appo-followup) で、AI が **「値が欠けている = バグ」と推測し、ドメインオーナーに確認する前に多段修正 (純関数 + route + stamp + 51 件 backfill) を設計・着手**した。真の患部は別の一点だった。決定的だったのは、調査で **「demo_proposals 92 件すべてが service 空 (100% 系統的)」** という強い系統性を観測していたのに、それを「全部バグ → backfill」と読んだこと。100% 系統的は**バグの証拠ではなく、その経路が仕様としてその値を扱わない**ことの強い証拠だった (service は kintone 商談が正本。demo 枠は日時のみ)。

この失敗は 2 つの一般的な構造に分解できる:

1. **オラクルの取り違え (mood / ADR 0007 と同根)**: 「この値はあるべきか?」は**意図の問い**で、オラクルはドメインオーナー。AI は実装/データをオラクルにし、自分が読んだパターンを「異常」と断定した (著者=採点者の円環)。
2. **同じ値の文脈依存な妥当性**: `service = NULL` は triage 経路では異常・demo 提案経路では仕様 — **同じ値でもレーンで正解が真逆**。妥当性が型にもスキーマにも書かれていないので、AI は推測で埋め、間違えた。

AI は「ストップ」と言われるまで止まれなかった (自分で確認の関所を置けない)。これは bootstrap の中心命題 — **強制は自己規律でなく構造で** — の対象そのもの。だが「これは欠陥か仕様か」は **AI が答えられない既約な人間判断**なので、fail-closed な block にはできない (block すれば全ての正当な migration で誤発火する)。ADR 0010 / 0001 の方針に従い、**可視化 (inject)** で防ぐ。

## Decision (決定)

**`inject-action-memory` (ADR 0010) の CLOSED action-key enum に `data-backfill` を足し、既存データを書き換える行為 (backfill スクリプト / 生 SQL の UPDATE・DELETE / data migration) の瞬間に、「修復か仕様か」を確認させる plugin 所有の doctrine を additionalContext で表面化する。** 新しい強制軸ではなく ADR 0010 の enum 拡張。

### plugin 所有のデフォルト doctrine (普遍則 → 常時発火)

ADR 0010 のメモは per-repo registry (`.bootstrap-actions`) からのみ来る opt-in だった。`data-backfill` の教訓は **project 非依存の普遍的安全則**なので、`action_default_memo <key>` で **plugin 同梱の一文を、repo が registry で arm していなくても出す**。文面:

> 既存データを書き換えようとしている。その値が「欠けている/間違っている」と判断した根拠は? **欠け方が ~100% 系統的なら、それは defect でなく spec の徴候** (その経路はそもそもその値を扱わない)。意図のオラクルは **data でなく domain owner**。直す前に確認せよ。同じ値でもレーンで妥当性が真逆になりうる。

registry が同じキーを arm していれば、project 固有メモを default の後に**追記**する (両建て = 普遍則の floor + project 知見)。

### 検出 (closed・決定論的・広め)

マッチャ arm (plugin 所有コード。consumer 側 regex は持たない = ADR 0010 の設計):
- セグメント head の basename が `*backfill*` / `*data-migrate*` (例 `tsx scripts/backfill-x.ts`, `npm run backfill`)
- `prisma db execute` (生 SQL 適用)
- `psql` / `mysql` の inline `UPDATE` / `DELETE` トークン
- 汎用 data-migration 実行 (`knex`/`sequelize`/`typeorm` の `migrate`/`migration run`, `alembic upgrade`)

### Fail-mode

- **完全 advisory**: 決して exit 2 しない (ADR 0010 / 0001。意図確認は AI が自己発行できる ack で偽装されるので強制しない)。
- **fail-OPEN / silent**: 非 Bash / parse 不能 / 非マッチ。検出漏れ (例: WHERE 厳密判定はしない・独自名の backfill スクリプト) は**見逃すだけで誤 block はない** — visibility に unsafe side が無い。
- **documented limit (DDL/DML)**: コマンドからは schema 変更 (DDL) と data 修復 (DML) を区別できないので、スキーマだけの migration でも doctrine が出る。never-block なので許容。文面を「既存データを変える前に」と広く書き的外れを抑える。
- **opt-in との関係 (明示的変更)**: `data-backfill` の default doctrine は **registry を arm していない repo でも出る** — ADR 0010 の「未採用 repo は完全無音」契約を、この 1 キーに限り**普遍安全則ゆえ緩める**。block せず・backfill 行為時のみ・低頻度なので advisory bloat は小さい。project 固有キー (prod-deploy 等) は従来どおり opt-in のまま。

## Consequences (結果)

### 良い影響
- AI が「データから "あるべき姿" を推測して直す」直前に、**意図のオラクルは人間**という普遍則が目の前に出る。mood / 今回の incident と同根の失敗を、全 bootstrap 製 repo で機械的に表面化できる。
- 「100% 系統的 = spec の徴候」という**読み筋そのもの**を行為の瞬間に渡す (verification skill の kill-question と対。skill はロード依存だが本 hook は決定論的に発火)。
- 両建てで普遍則を floor にしつつ project 固有知見も載る。判定は action-gate.sh の単一権威のまま (hook と doctor が drift しない)。

### 悪い影響 / トレードオフ・限界
- **advisory ノイズ**: 広め検出 + 常時発火なので、正当な migration/backfill でも出る。never-block・低頻度だが、頻繁に backfill する repo では慣れによる無視 (banner blindness) のリスク。文面を短く・1 行で。
- **DDL/DML 非区別** (上記)。
- **強制力は無い**: 理解は既約 (ADR 0001)。AI が読んで無視する自由は残る — これは設計上の選択であって穴ではない。構造で防げるのは「問いを正しい瞬間に表面化する」までで、「意図そのもの」は人間に残る (単一 orchestrator の frontier)。
- **opt-in 契約の部分緩和** (上記、明示)。

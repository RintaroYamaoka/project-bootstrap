# 0006 — 並列 default を実行形態で分離する (worker lane は帯域律速のまま、Workflow lane は engine 律速)

- **Status**: Accepted
- **Date**: 2026-06-19
- **Supersedes (部分)**: なし (ADR 0005 の `wip_limit` 適用範囲を精緻化)

## Context

`wip_limit` の既定は長く **「2-3」** と一言で書かれてきた (`resolve-wip-limit.sh` の fallback 表示、SKILL.md の「ソロで実質 2-3」「並列の収益は凹型で変曲点は低い」)。この数字は **a-priori な推論** で決めた値 — 「人間の全 diff 直列レビュー帯域が律速だから lane を増やしても throughput は増えない (凹型)」という ④ の取引から導いた。

だが dogfood の単一 orchestrator (設計者本人) は、これを **体感で「低すぎる・bootstrap が遅い」** と報告した。原因を分解すると、`wip_limit` が **実行形態を問わない単一の天井** として読まれていたことにある。実際には ADR 0005 で公認した 2 つの mutation 形態は **律速が違う**:

| 形態 | 律速 | `git worktree add` を guard 3 が観測? | 帯域の守り手 |
|---|---|---|---|
| **terminal worker lane** (人間が別ターミナルで起動) | **人間のレビュー帯域** (= 複数 repo 共有の単一資源) | する (= `block-over-wip-parallel.sh` が cap) | 人間の verdict + サンプル監査 |
| **Workflow / subagent lane** (main session が orchestrate) | **engine の並列上限** `min(16, cores-2)` | **しない** (内部 `agent()` spawn は PreToolUse に届かない — ADR 0005) | 統合関所が **自動**で守る (`block-unreviewed-merge.sh` = `verdict: approve` 確認 + 検出スイート再実行) |
| breadth fan-out (read-only) | なし | — | lane でない (review 帯域を消費しない) |

つまり `wip_limit` の cap は **構造上 terminal worker lane の路にしか効いていない**。Workflow lane は元々 engine 上限 (~8-12) で走り、帯域は統合の入口で機械的に守られる。「2-3 が全形態の天井」という読みは **worker 路の帯域律速を、帯域を人手で消費しない Workflow 路にまで誤って適用** していた (= AI の癖 ⑧「ルールを射程外まで過剰一般化する」の構造版)。

## Decision

**並列 default を実行形態で分離する。** `wip_limit` (`.bootstrap-wip` / 既定値) は **terminal worker lane の路にのみ適用される cap** と明示し、Workflow lane / breadth fan-out には適用しない。

1. **terminal worker lane**: `wip_limit` で cap する (`block-over-wip-parallel.sh` は不変)。advisory 既定を **2-3 → 3-4** に一段引き上げる。根拠は dogfood の体感シグナルで、revert 根拠は `scripts/velocity.sh` の defect rate (= ④ の管理された取引。盲目的緩和ではない)。per-project の上書きは従来どおり `.bootstrap-wip` の整数。
2. **Workflow / subagent mutation lane**: `wip_limit` の **対象外**と明記する。並列度の天井は engine の `min(16, cores-2)`、帯域は統合関所 (guard 1) が自動で守る。`block-over-wip-parallel.sh` は元々この路の `git worktree add` を観測できないので、コード挙動の変更はない — 変えるのは **doctrine の記述** (「2-3 が全形態の天井」という誤読を断つ)。
3. **breadth fan-out (read-only)**: 無制限 (ADR 0005 のまま)。

表示・doctrine の文言を form-aware にする (`resolve-wip-limit.sh` の fallback、SKILL.md の WIP 節、`templates/.bootstrap-wip`、README、`block-over-wip-parallel.sh` の block message)。

> doctrine の 4 設計判断は **5 にしない**。本 ADR は ④ (計測つきの取引) の **適用** であって新軸ではない — 「緩めるなら戻る根拠を metric で持つ」をそのまま実行形態に展開しただけ。

## Consequences

- **得**: orchestrator が main session から駆動する Workflow 路の実効並列が、誤った 2-3 の天井から engine 上限 (~8-12) に「見える」ようになる。これが体感「並列が少ない」への直接の回答。worker 路の advisory も一段上がる。
- **コスト / リスク**: worker 既定を上げた分、レビュー帯域を超過する誘惑が増える。これは ④ の取引どおり **defect rate (`scripts/velocity.sh`) で監視** し、悪化したら一段戻す。Workflow 路の帯域保護は人手でなく統合関所 (verdict + スイート実行) に依存するので、**関所が緑であることが Workflow 路の安全の前提** — 関所を弱めると Workflow 路の高並列がそのまま欠陥流入になる (= guard 1 は Workflow 高並列の安全弁であり、緩めてはならない)。
- **コード変更は最小**: guard 3 の挙動は不変 (元々 worker 路専用)。変えたのは fallback 表示文言と doctrine。`wip_limit` を実体的に強制する路 (terminal worker) は精度を保ったまま、Workflow 路は元の engine 律速を doctrine 上も正当化した。
- **関連**: ADR 0004 (並列 3 形態) / ADR 0005 (ultracode を実行エンジンとして governance・guard 1/2/3)。本 ADR は 0005 の `wip_limit` 適用範囲を形態別に確定する。

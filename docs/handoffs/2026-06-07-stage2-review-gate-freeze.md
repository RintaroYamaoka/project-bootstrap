# 2026-06-07: trust ladder Stage 2 出荷 + feature freeze

## 1 行で言うと

0.14.0〜0.15.1 を 1 日で出荷 (wip_limit 宣言化 / stale board gate バイパス根治 / **AI レビューを merge の precondition に強制 + velocity 横断計測**)、全 21 suite 緑・CI 緑・cache 0.15.0 で動作 read-back 済み — そして **bootstrap は feature freeze**。

## 残課題

| 識別子 | 状況 | 対応案 |
|---|---|---|
| 次プロダクトの決定 | **未定 (これだけが本物の残課題)** | user が決める。決まったら `docs/sprint/` + `.bootstrap-wip=3` を置いて開始。最初の 2 週で「gate block に納得できなかった回数」を数える (0-2 適正 / 5+ 過剰装備 → 削る incident) |
| Stage 3 (worker 起動自動化 / ADR 0001 upstream #21460 監視) | 凍結中 | 次プロダクトで defect rate が 11% 基準で安定したら解凍 |
| velocity 推移の永続化 (`--log`) | 未実装 (現状 stdout のみ、4 週より前の推移は流れる) | 凍結対象。欲しくなったら `(date +%F; velocity.sh ...) >> velocity.log` の運用で代替 |

## バックグラウンドプロセス

なし。

## 触ったファイル

- **永続化済み (全て push 済み, main = `b661a25` + marketplace 修正 1 commit 未 push の可能性 → 検証手順参照)**: hooks (block-unreviewed-merge / block-unplanned-feature-build / sprint-trigger-reminder / hooks.json)、hooks/lib (resolve-wip-limit / board-liveness)、scripts (velocity / doctor)、skills (integrate / sprint-plan / project-bootstrap)、templates、README ×2、CHANGELOG、incident `2026-06-07-stale-board-gate-bypass`、`.bootstrap-wip` (=3)、board archive
- **ephemeral**: なし

## 重要な memory / docs references

1. memory `feedback_gate_signal_and_failmode` — 原則 5 (存在≠活性) を今日追加
2. memory `user_multi_project` / `project_propagate_ai_done` — 今日追加 (検証場は次プロダクト、レビュー帯域は全 repo 共有)
3. `docs/incidents/2026-06-07-stale-board-gate-bypass/` — gate 無音化 class 3 例目
4. CHANGELOG 0.14.0〜0.15.1 — 設計判断の全文

## 検証手順

```bash
bash tests/hooks/run.sh            # 期待: SUITES: 21 run, 0 failed
git status --porcelain             # 期待: clean (未 push commit が無いこと: git log origin/main..HEAD が空)
bash scripts/velocity.sh .         # 期待: TOTAL 4w 行に defect=N% (基準線 11%)
bash scripts/doctor.sh .           # 期待: STATUS: ok
```

## 次セッションへの起動文

```
docs/handoffs/2026-06-07-stage2-review-gate-freeze.md を読んで状況把握してから。
bootstrap は feature freeze 中 (例外: 実プロダクトで踏んだ incident のみ)。
今日の仕事は次プロダクトの選定 or その開発。bootstrap の機能追加を提案しないこと。
```

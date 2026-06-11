# 2026-06-11: gate 修正 3 連発 + 並列 3 形態の公認 (0.16.0 → 0.17.0)

## 1 行で言うと

consumer repo の適用状況チェックから gate 無音化 class の 4・5 例目と計測バグを発見し、**1 日で 0.16.0 / 0.16.1 / 0.17.0 を release・配備** (全 22 suite 緑、installed plugin 0.17.0 read-back 済み)。subagent hook 問題 (#21460) は **upstream 修正済みを実測確認**、ADR 0001 を部分撤回し並列 3 形態を公認 (ADR 0004)。defect 基準線は新計測の **12%** に引き直し。

## 残課題

| 識別子 | 状況 | 対応案 |
|---|---|---|
| appo-followup への CI 関所配備 | **保留中 (別 session が稼働中のため触らない)**。`.github/workflows/` 不在、PR 経路の review-gate 未配備。古い feature branch 9 本残置、main が 12 commit 遅れ | 並走 session が一段落したら `templates/ci/bootstrap-review-gate.yml` をコピー + branch 掃除。worktree 関所 (0.17.0) は新 session から自動で効く |
| propagate-ai の未 commit docs 67 件 | 完了済み project に handoffs 等が未保存のまま (並走 session の WIP かも) | user が「動いていない」と確認したら docs を commit |
| creative-team-app の required check 化 / AI-SITE-EDITOR 重複 dir | user 判断待ち。required にすると main 直 push が弾かれる / 重複は片方削除か | 聞いてから |

## バックグラウンドプロセス

なし。

## 触ったファイル

- **永続化済み (全 push 済み)**: bootstrap = hooks (block-unplanned-feature-build / block-unreviewed-merge)、hooks/lib/gate-entry.sh (新)、scripts/velocity.sh、templates/ci/bootstrap-review-gate.yml (新)、skills ×3、ADR 0001 (supersede 注記)・**0004 (新)**、incidents ×3 (gate-broad-glob / velocity-fixrev-japanese / parallel-mode-gate-coverage)、CHANGELOG、tests。creative-team-app = .gate archive・README 同期・CI 配備・merge 済み worktree 撤去 (こちらは samu182 の並走 commit の上に乗せた)
- **ephemeral**: なし

## 重要な memory / docs references

1. `docs/decisions/0004-parallel-mode-integration-gate.md` — 並列 3 形態と関所の置き場所 (今日の中心判断)
2. `docs/incidents/2026-06-11-parallel-mode-gate-coverage/` — 関所の経路漏れ + subagent hook 実測検証の手順
3. memory `feedback_gate_signal_and_failmode` (原則 6 追加) / `feedback_gate_distribution_coverage` (経路カバレッジ + 外部前提の再検証)
4. `scripts/velocity.sh` header — 新基準線 12% の正本

## 検証手順

```bash
bash tests/hooks/run.sh                      # 期待: SUITES: 22 run, 0 failed
grep version ~/.claude/plugins/installed_plugins.json | head -1   # 期待: 0.17.0
bash scripts/velocity.sh ~/dev/propagate/creative-team-app .      # 期待: TOTAL 4w defect=12% 前後
```

## 次セッションへの起動文

```
docs/handoffs/2026-06-11-gate-triple-fix-parallel-modes.md を読んで状況把握してから、
残課題の「appo-followup への CI 関所配備」を、並走 session の有無を確認した上で進めて。
```

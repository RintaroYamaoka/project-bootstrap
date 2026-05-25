# 2026-05-25-propagate-ai-adoption: 寝ている間の自走結果

## 1 行で言うと

project-bootstrap を v0.8.2 まで進め (lint opt-in 化 + arch staged-only 化)、propagate-ai へ適用する **PR #17 を merge-ready 状態に** (tsc=0 検証済み・マージしても壊れない)。安全に直せる違反 (infra→lib 契約是正 + serializeError→core) は修正、残 6 件は本番アーキ判断が要るため非破壊 debt として PR に明記。本番作業ツリーは終始無傷 (worktree で作業 → 撤去)。

## ⚠️ 起きたら最初にやること (URGENT)

**ローカル plugin を v0.8.2 に更新する**:
```
/plugin marketplace update rintaro-yamaoka
/reload-plugins
```
理由: v0.8.1 の lint gate は **always-on** で、propagate-ai の `next lint` (ESLint 未設定 → 対話プロンプト → exit 1) を回して **commit を壊す**。v0.8.2 で lint gate を `.bootstrap-lint` opt-in 化したので、更新すれば直る。更新するまで propagate-ai の commit が lint gate でブロックされる可能性がある。

## 残課題

| 識別子 | 状況 | 対応案 |
|---|---|---|
| plugin 更新 | v0.8.1 が稼働中 (lint gate が live リポを壊す) | 上記 2 コマンドで v0.8.2 へ (PR マージ前に必須) |
| propagate-ai PR #17 | **tsc=0 検証済み・マージしても壊れない**状態 | レビューしてマージするだけ |
| 解消済み: infra→lib 8 + serializeError 1 | 契約是正 + core/shared へ移動 | 済 (PR #17 に含む) |
| 残 debt: core→infra LLM 4 + email 1 + cron 1 | port 化等の本番設計判断要・staged-only で非破壊 | 別 PR (PR #17 本文に推奨修正を明記) |
| arch go/rust/ruby extractor | 未対応 (v1 は ts/js/py) | 次回 |

## バックグラウンドプロセス

なし (全て完了・停止済み)。dry-run scan の一時ファイルは破棄済み。

## 触ったファイル

**project-bootstrap (main に push 済み, v0.8.2 = `3571c34`, tag v0.8.0/0.8.1/0.8.2)**:
- 0.8.0: lint gate (`block-commit-if-lint-fails.sh`)
- 0.8.1: duplicate hooks 修正 (plugin.json の hooks 行削除)
- 0.8.2: lint opt-in (`.bootstrap-lint`) + arch staged-only。`templates/.bootstrap-lint` 追加
- `tests/hooks/` 11 suite green

**propagate-ai (本番ツリー未変更。PR #17 のブランチ `feat/bootstrap-adoption` にのみ commit)**:
- `.bootstrap-arch` (依存方向契約) / `.bootstrap-protected` (main/master 保護)
- worktree で作業 → 撤去済み。main は触れていない (uncommitted 46 件そのまま)

## 重要な memory / docs references

- `feedback_bootstrap_is_canonical` — project 固有事情は `.bootstrap-*` で受ける
- `reference_plugin_verification_layers` — always-on gate は既存リポを壊す。実 target で検証必須
- propagate-ai PR: https://github.com/propagate-infra/propagate-ai/pull/17

## 検証手順

```
cd project-bootstrap && bash tests/hooks/run.sh   # SUITES: 11 run, 0 failed
git -C <propagate-ai> status                       # main, uncommitted 46 (未変更)
gh pr view 17 -R propagate-infra/propagate-ai      # OPEN, 未マージ
```

## 次セッションへの起動文

```
docs/handoffs/2026-05-25-propagate-ai-adoption.md を読んで、まず plugin を v0.8.2 に更新。
その後 propagate-ai PR #17 の triage (core→infra の DI 逆転 6件) を一緒に処理するか判断したい。
```

---

## 続報 (0.9.0 — team-wide 強制ネット完成)

「本気で守る/二度と drift させない」要件に対し、PreToolUse hook (Claude-scoped、環境依存で消えうる) の穴を埋める **3 層強制**を実装:

- **project-bootstrap v0.9.0** (main, tag): `scripts/arch-check.sh` (Claude 非依存 CLI) + `templates/ci/bootstrap-arch.yml` (PR の bypass 不可 gate) + `templates/hooks/pre-commit`。12 test suite green
- **propagate-ai PR #17**: CI ネットを vendor + 配線。**arch-check CI = pass (8s)**、PR は MERGEABLE。serializeError→core + infra→lib 契約是正済み。tsc=0 検証済み
  - Vercel check fail = commit author の deploy 権限問題 (コード無関係、user 操作で解決)

### Sprint 2 (未実施・runtime-sensitive なので意図的に保留)
propagate-ai の残 6 違反のうち core→infra LLM (4) / email (1) / cron (1) は **port 化・cron 移動など runtime 挙動に影響する本番リファクタ**。CI は依存方向を検証するが **runtime 挙動は検証しない**ため、subagent で夜間に blind-ship すると customer-facing LLM/cron pipeline を壊すリスク。**vitest で挙動を gate + port 設計を一目見てから**実施するのが安全。ネット (CI) は完成したので、次は安全に着手できる。
- 安全分 (`ExistingCta` 型→core、runtime 影響ゼロ) だけ先に片付けるのも可

---

## Sprint 2 結果 (スクラム並列、runtime しない期間前提で実施)

PR #17 に追加 push (bf76b69)。CI arch-check green。worktree 2 本 (cron/llm) を junction + tsc gate で並列実行。

**6 違反中 3 件を検証付きで解消** (tsc=0 + arch-check + vitest):
- ✅ ExistingCta 型 → `core/domain/proposals/existingCta.ts` (validateProposal / llmAnalyzer の core→infra 型違反 2件)
- ✅ `lib/cron/authAndGate` → `app/api/cron/_shared/` (lib→app、subagent、importer 11 更新、vitest 5/5)

**残 3 件 (意図的に保留、approach 明確)**:
- generateRecommendations の `extractExistingCtas`/`mergeStickyCtas`/`evaluateProposalQuality` 直呼び (core→infra 2件): **DI port 化** = `GenerateDeps` interface (既存 DI pattern) に注入依存として足し container で配線。ただし signature が infra 型 (StickyCtaInput / QualityResult / QualityCheckContext) を引くため **型 cascade** (それらも core へ) + zod LLM schema を core に置くか判断が要る → session 末で rush せず保留
- email (notifyDeployedRecs → lib/email/templates、core→lib 1件): email 整形は通知 adapter 寄り。templates が trackedLink を cascade 依存

**dogfood で判明した bootstrap の粗** (roadmap):
- require-test-companion が **type-only .ts を block** (existingCta.ts 作成時)。type-only skip ルールが要る
- block-dangerous-git-ops が、別ブランチに merge 済みの local branch の `-D` も block (正しく安全側、ただし cleanup 摩擦)
- arch-check が `import type` を runtime import と同列に flag

**ローカル残**: feat/sprint2-cron / feat/sprint2-llm (内容は origin/feat/bootstrap-adoption に取り込み済み、`-D` は hook が block するので残置・無害)

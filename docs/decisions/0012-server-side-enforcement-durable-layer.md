# 0012 — サーバ側強制を恒久 enforcement 層に、ローカル hook は速い feedback 層に降格

- **Status**: Accepted
- **Date**: 2026-06-25
- **Deciders**: Rintaro Yamaoka
- **References**: [0007](./0007-verification-plan-as-merge-precondition.md) (verification plan を統合 precondition にした親) / [0011](./0011-cross-repo-contract-drift-gate.md) (「PR 経路: 手元 hook は GitHub PR 画面の merge を通らない / CI net 側は follow-up」と明記した穴 — 本 ADR がその follow-up) / [0004](./0004-parallel-mode-integration-gate.md) (lane 信号) / memory `feedback_gate_distribution_coverage` (関所は全方式が必ず通る行為に置く・配備カバレッジ) / `feedback_gate_signal_and_failmode` / deep-research salvage `wf_9eac8b87-971` (外部一次資料による反証つき検証)

---

## Context (背景)

ADR 0007 / 0011 の merge gate は **PreToolUse on Bash の `git merge`** を信号にしている。これは「ローカルで `git merge` コマンドを踏む」経路でしか発火しない。deep-research (4 軸・25 claim を 3 票敵対検証、24 支持) で、この信号選びに **3 つの構造穴**が外部一次資料で確定した。memory `feedback_gate_distribution_coverage`「関所は特定方式の痕跡でなく全方式が必ず通る行為に置く」の未達ケースである。

### 穴 1 — サーバ側マージは手元 hook の射程外 (C-1)

GitHub の **「Merge pull request」ボタン (Web UI / API)** はサーバ側で実行され、ローカル client の hook は**原理的に走らない**。ADR 0011 が follow-up として明記していた穴。GitHub docs (branch protection / rulesets) で、**サーバ側強制だけが Merge ボタン経由を含む全マージの前に要件を強制できる**ことを確認した。ローカル hook はそれに先んじる速い feedback にはなるが、**恒久的な関所にはなれない**。

> 出典: branch protection は「Web UI の Merge ボタン経由を含め保護ブランチへの全マージの前に要件を強制する」(GitHub docs, managing-protected-branches/about-protected-branches)。

### 穴 2 — 単一 orchestrator = admin が gate を素通り (C-3)

GitHub branch protection は **デフォルトで admin (repo 所有者) に適用されない**。単一 orchestrator はすべての repo で admin を持つので、`include administrators` を明示しない限り**自分の関所を自分で素通りできる**。これは memory `project_bootstrap_dogfood`「単一 orchestrator 検証が残る frontier」の最も危険な現れ — 「自分は規律ある」前提が最大の自己欺瞞リスク。

### 穴 3 — lane 限定 pre-merge gate は stale 統合破壊を見逃す (C-2)

merge gate は lane branch を信号にする (ADR 0004)。ローカル pre-merge hook は **stale な lane branch 上で走る**ため、「他 lane が先にマージした結果」との統合破壊を構造的に見られない。GitHub **merge queue** は各 PR を **target branch の最新版に対して再検証**してからマージするので、この欠陥に直接対応する。

### 採らない代替 (検証で棄却 / 留保)

- **Pact (consumer-driven + 中央 Broker)** に契約登記を寄せるのは並列開発と相性が悪い: 中央 Broker が**直列化点・単一障害点**、二重メンテ、外部 provider 不適合。レビュー帯域律速の単一 orchestrator には重い。採るなら **Specmatic/OpenAPI 型 spec-as-contract** を比較検討 (主張は支持されたが自プロジェクトで要再検証)。本 ADR は契約方式を変えず、ADR 0011 の登記方式を**サーバ側へ二重化**する。

## Decision (決定)

**enforcement を 2 層に分ける。ローカル hook は「速い feedback 層」、サーバ側 (GitHub branch protection / rulesets / required status check / merge queue) を「恒久 enforcement 層」とする。** 同じ判定 (verification plan が閉じている = OPEN 行ゼロ) を**両層で**走らせ、サーバ側を権威にする。新しい判定ロジックは作らない — 既存 `hooks/lib/verification-plan.sh` を CI からも呼ぶ (信号 drift 防止、verification-plan.sh が単一権威であり続ける)。

### ① CI required status check (穴 1)

- `hooks/lib/verification-ci-check.sh` — verification-plan.sh lib を再利用し、CI 上で「現在の PR の head branch の plan が閉じているか (存在・非空・OPEN ゼロ・理由なき DROP ゼロ)」を判定する entrypoint。stdin の hook JSON でなく `git` から branch を解決する点だけが PreToolUse hook と違う。判定の権威は lib に残す。
- `templates/github/workflows/verification-gate.yml` — 上記を回す GitHub Actions workflow 雛形。adopting repo は `.github/workflows/` にコピーし、branch protection の **required status check** に登録する。
- **bootstrap 自身に dogfood 適用** (`.github/workflows/verification-gate.yml`)。

### ② branch protection / rulesets + `include administrators` (穴 1, 2)

- `scripts/setup-server-enforcement.sh` — `gh` で対象 repo に branch protection (required check = verification-gate / **enforce_admins = true** / required PR review) を冪等に設定する再利用スクリプト。ruleset 派には `templates/github/ruleset.json` も提供 (複数 repo 横展開・「最も制限的版が勝つ」集約)。
- bootstrap repo に適用。**enforce_admins を必ず on** にする (穴 2 の本丸)。

### ③ merge queue (穴 3)

- 上記スクリプト/テンプレートで **merge queue を有効化可能**にする (opt-in)。並列 lane が増える repo ほど効く。stale lane の統合破壊を、レビュー帯域 (律速資源) を食わずにサーバ側で自動検出する。

## Fail-mode

- **サーバ側 (権威)**: required check が success/skipped でなければ merge 不可 (GitHub が強制、per-machine variance なし)。enforce_admins=true で admin も対象。merge queue は target 最新版で再検証。
- **ローカル hook (feedback)**: 従来どおり fail-closed で `git merge` を止めるが、**これは権威ではなく前倒しの警告**に再定義する。ローカルを bypass してもサーバ側で再び捕まる (二重化の要点)。
- **CI check 自体の fail-open 条件**: `docs/verification/` 未採用 repo / plan 不在の非 lane branch では check を pass させる (既存 gate の opt-in 性と整合)。判定不能 (branch 解決不可) は **fail せず neutral/skip** にし、別の必須 check (review) が落ちないようにする — CI の偽 red で全 PR を止めない。
- **適用の限界 (documented)**: branch protection の設定自体は人間 (admin) の一回操作。`setup-server-enforcement.sh` はそれを冪等化するが、**未実行の repo はサーバ側無防備**のまま (memory `feedback_gate_distribution_coverage`「現行版で配備されて初めて効く」)。SessionStart doctor で「remote はあるが branch protection 未設定」を可視化するのは follow-up。

## Consequences (結果)

### 良い影響
- merge gate が**全マージ経路** (ローカル `git merge` / GitHub Merge ボタン / API) で効くようになる — 信号が「特定方式の痕跡」から「サーバが必ず通す行為」へ移り、memory `feedback_gate_distribution_coverage` のカバレッジ要件 (経路も含む) を満たす。
- enforce_admins=true で**単一 orchestrator が自分の関所を素通りする**自己欺瞞リスクを構造で塞ぐ。
- merge queue で stale lane 統合破壊を、レビュー帯域を消費せずに自動検出する。
- 判定ロジックは verification-plan.sh の単一権威のまま (ローカル/CI が同じ lib を呼ぶ) → 二層化しても drift しない。

### 悪い影響 / トレードオフ・限界 (documented limits)
- **配備が人間の一回操作に依存**: スクリプトを各 repo で走らせるまでサーバ側は無防備。配備カバレッジの可視化は follow-up。
- **CI コストと latency**: 全 PR で workflow が走る。verification check は軽い (lib のテキスト判定) が、required check 化は merge までの待ちを増やす。
- **enforce_admins の運用摩擦**: 緊急時に admin も bypass できない。GitHub の ruleset bypass actor / 一時 off で対処するが、これは**明示操作**にする (無音 bypass を作らない = 穴 2 を再導入しない)。
- **merge queue は GitHub 依存機能**: self-host / 他 forge では別手段が要る。
- **検証の射程**: 本 ADR は「verification plan が閉じている」の二層化であって、plan の中身の質 (検出力) は別軸 — それは verification skill の 6 番目の seam (mutation/metamorphic/property) と dead-man's-switch doctrine で扱う (同 sprint の別変更)。

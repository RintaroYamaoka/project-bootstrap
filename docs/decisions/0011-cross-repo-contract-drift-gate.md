# 0011 — cross-repo 契約ズレを「登記された継ぎ目」として統合の precondition にする

- **Status**: Accepted
- **Date**: 2026-06-25
- **Deciders**: Rintaro Yamaoka
- **References**: [0007](./0007-verification-plan-as-merge-precondition.md) (verification plan を統合 precondition にした親 ADR) / [0004](./0004-parallel-mode-integration-gate.md) (lane 信号) / [0005](./0005-ultracode-execution-engine-governed-by-bootstrap.md) (関所がスイートを実走する guard 1) / appo-followup `docs/incidents/2026-06-20-demo-booking-mood-contract-drift` / memory `feedback_gate_signal_and_failmode` / `feedback_verification_design_seams_and_oracle` / `feedback_gate_distribution_coverage`

---

## Context (背景)

ADR 0007 は「動作テスト計画 (verification plan) が閉じていること」を統合の precondition にした。だが plan は **その repo の中**で閉じる成果物で、**継ぎ目のうち最も事故が多い cross-repo 契約**については、計画があっても次の 2 つが構造的に抜けていた:

- **共有面の登記が無い**: どの local source face がどの sibling repo と契約を共有しているかが、どこにも書かれていない。mood incident はこれだった — サイト repo が問診から `mood` を削除、appo の zod は `mood` 必須のまま → 当日 CV 17 人で予約成立 0。両 repo を見比べれば自明だが、「両者が同じスキーマを共有している」という事実が **どこにも宣言されていない**ため、誰もそこに動作テストを向けなかった。
- **片側変更が無音 no-op する**: 3 つの participating repo の 1 つで plan 値が変わったのに、他 2 repo には何の信号も立たず無音で no-op した。共有の宣言が無いので cross-repo test も無い。

これは memory `feedback_gate_distribution_coverage`「関所は全方式が必ず通る行為に置く」と `feedback_verification_design_seams_and_oracle`「両端を握っていない境界 → 契約テスト・オラクルは AI の外」の cross-repo 版が、**宣言の不在ゆえに発火しなかった**ケースだ。

### critique blocker (実装上の罠)

素直に「verification-drift.sh の `_vd_changed_sources` (cwd/HEAD の delta) を再利用して、変更面が契約面に当たったら…」とすると **gate は永遠に発火しない**。PreToolUse の `git merge` hook 時点で HEAD = 統合先 (main) なので、cwd/HEAD を見る changed-set は **空**になる。lane が何を変えたかを知るには HEAD ではなく **lane branch の OWN delta (base..lane) を offline で計算**しなければならない。

## Decision (決定)

**cross-repo 契約を `docs/verification/contracts` に行指向で登記し、lane が登記面を触ったら、その契約の consumer 側動作テストの「閉じている記録 + 実走 (緑)」を統合の precondition にする。** ADR 0007 の枠 (verification plan = 統合 precondition) の cross-repo 拡張であり、新軸ではない。

### 登記フォーマット (`docs/verification/contracts`、参加 repo ごとに commit)

行指向・jq 非依存。`#`/空行は無視。1 行 = 1 契約:

```
id | local_face_glob | peer_repo | peer_face | note
```

`id` = 契約の安定 ID (plan 行が `[contract:<id>]` で参照)。`local_face_glob` = この repo 側で契約を背負う source face の glob。`peer_repo` / `peer_face` = 相手側の手掛かり (**人間用。gate は相手を読まない**)。雛形 = `templates/docs/verification/contracts.example`。

### 単一権威エンジン `hooks/lib/cross-repo-contract.sh`

gate と doctor が共有 (信号 drift 防止 — verification-plan.sh / source-face.sh と同方針)。中核は **`branch_changed_sources <dir> <lane>`** = lane の OWN delta を offline で計算する: `base = git -C <dir> merge-base <lane> <main-ref-or-HEAD>`、`git diff --name-only base..<lane>` を `source-face.sh` の `is_source_path` で source face に絞る。`crc_touched_contract_ids` がそれを登記 glob と交差させ、`crc_closed_row_references_id` が「その id を CLOSED にした plan 行」を判定する。

### gate 拡張 (`block-merge-if-verification-unclosed.sh`、既存 plan check の後)

各 lane branch について、touched 契約 id ごとに:
1. その id を参照する **CLOSED な plan 行 (PASS / 理由つき DROP)** を要求。無ければ block。
2. consumer 側スイートを **関所自身が実走** (`detect-test-suite.sh` + block-unreviewed-merge.sh と同じ「関所がスイートを回す」move)。red なら block。
3. 自動で回せない (相手の実出力を人間が確認する) 契約は plan 行を **`STATUS=HUMAN`** にする。HUMAN は OPEN なので既存 check が block し続ける = 人間が実出力で照合して PASS+証拠を記録するまで通らない。**free-text の PASS では touched 契約を閉じさせない** (実走 or 人間の照合のどちらかが必須)。

### doctor 軸 (`verification-drift.sh`、OBSERVABLE な事実のみ)

可視化 (advisory): 宣言された `local_face` が今もう存在しない、OR 宣言面が current branch の delta に在るのに契約行が無い。**「undeclared sibling-facing face」のような観測不能なヒューリスティックは持たない** (相手を読まない原則と矛盾し、誤検知源になる)。

## Fail-mode

- **fail-CLOSED (発火条件)**: docs/verification 採用済み + lane branch の OWN delta が登記面に当たる + その契約を CLOSED にした行が無い、または実スイートが red。← 強制したい判定を advisory に逃さない (ADR 0002 / 0007 の系譜)。
- **fail-OPEN (no-grounds・無音)**: 非 merge / 非 git / docs/verification 未採用 / contracts 不在・契約ゼロ / delta が宣言面に当たらない / merge 先が lane branch でない / **sibling repo 未読** (= gate は consumer 側の判断だけを検証し相手を diff しない → 相手 checkout が無いマシンで誤発火しない)。
- **コマンド解析不能 = fail-CLOSED** (parse-command の契約、既存 gate と同じ。bypass 防止)。
- **governing 側の no-op (明示)**: 下流専用変更 (sibling が動き本 repo は不変) は **本 repo に lane branch を生まない**ので、この gate には構造的に到達不能。これは「カバーしている」のではなく「この信号では捕まえない」— 無音で coverage を匂わせず、ここに明記する。下流側 repo でも同じ登記を置くことで、その repo の lane merge 時に対称的に捕まる。

## Consequences (結果)

### 良い影響
- mood 型 (片側 relax の無音破壊) に対し、**共有面の登記 + 触れたら consumer 契約テスト必須**という構造的防御ができた。「どこ repo と何を共有しているか」が会話でなく committed file になり、verification skill Step-2 の登記簿として機能する。
- gate が free-text PASS を信じず実スイートを回す (ADR 0005 guard 1 と同型) ので、「PASS と書いた」だけの自己採点では touched 契約を閉じられない。

### 悪い影響 / トレードオフ・限界 (documented limits)
- **consumer 側のみ**: gate は相手 repo を読まない。相手の実出力との最終照合は HUMAN 行に残る (= 単一 orchestrator の frontier)。これは設計上の選択 (誤発火回避) であって「相手も検証した」ではない。
- **governing/downstream 非対称**: 下流専用変更はこの repo の gate に到達しない (上記)。対称な被覆には両 repo への登記配備が要る (memory `feedback_gate_distribution_coverage`)。
- **登記の網羅性は人間依存**: 登記し忘れた共有面は捕まらない (plan 自体の穴と同種)。doctor の observable 軸 (宣言面が delta に在るのに契約行が無い) が一部を救うが、未宣言の面は射程外。
- **lane delta の前提**: lane が main から派生し base が解決できることに依存する。base/ref 不解決は fail-open (過少報告 = 安全、false-block しない)。offline only (fetch しない)。
- **PR 経路**: 手元 hook は GitHub PR 画面の merge を通らない (ADR 0007 と同じ穴)。CI net 側への登記反映は follow-up。

---

## Amendment ノート — D4 (async / silent-skip doctrine、ADR 0007 の amend)

> 本来 ADR 0007 本文への amendment だが、0007 は本 lane の編集 scope 外のためここに記録する (実装の正本は `skills/verification/SKILL.md` / `hooks/lib/verification-plan.sh` / `hooks/lib/verification-drift.sh`)。0007 を編集できる lane が後で本ノートを 0007 末尾へ転記してよい。

**動機 (incidents)**: cron が条件で 1 件を filter-and-skip して何のログも残さず、リマインダが永遠に飛ばなかった。daemon の heartbeat は生きているのに work queue が stall した。ADR 0007 の verification trap 1 / read-back doctrine は **同期の呼び出し側**を前提に書かれており、async / scheduled の経路は *読み返す自分の返答が存在しない* ため射程外だった。

**決定 (0007 の ② 信号選び / ③ 配備可視化 の適用、新軸ではない)**:
- verification skill Step-2 の境界チェックリストに **5 つ目の named seam** (無音 skip/drop/filter の経路 / live heartbeat の裏で stall する queue / cron の skip 分岐) を足す。Step-3 オラクル表でこの seam-shape を **`kind=monitor` + AI の外の実オラクル** (本番アラート / 日次集計「CV>0 かつ予約=0」) に対応させる。Step-6 item 4 を optional から **MANDATORY-to-state** に昇格 (実オラクルの monitor 行が在る、OR 盲点を文章で白状する、のどちらかを必ず述べる)。
- `verification-plan.sh`: kind 語彙に **`async`** を追加。pure helper **`vplan_has_kind <file> <kind>`** (field-2 の **厳密一致**・case-fold・**substring 走査しない**) を追加。
- `verification-drift.sh`: **新 doctor 軸** — plan に `kind=async` 行が 1 つ以上あり、かつ **実オラクル (field-4 ≠ n/a) を持つ `kind=monitor` 行が無い**とき、advisory を 1 行出す。**CRITICAL**: prose を lexicon 走査しない (`skip|drop|filter` 走査は本 repo 自身の clean plan の DROP 行が "drop" を含むため誤発火した) — AI が意図的に set した **controlled-vocab の kind フィールドだけ**を信号にする。POPULATED な plan で発火する **独立ブランチ**として置き (= 非空 plan の early-return の後ろに隠さない)、source-face 変更で gate するので docs/config-only branch では無音。**advisory only・決して exit 2 しない**。

**Fail-mode (D4)**: 完全 advisory (可視化であって強制ではない)。判定は controlled-vocab field のみ (誤発火源の prose 走査を排除)。source-face 変更が無ければ無音 (docs-only は対象外)。placeholder の monitor 行 (oracle = n/a) は「実オラクル無し」とみなし盲点扱い (= まだ計器が当たっていない)。

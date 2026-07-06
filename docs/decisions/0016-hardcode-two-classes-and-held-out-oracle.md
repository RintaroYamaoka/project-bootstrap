# 0016 — AI コードのハードコードを 2 クラスに分け held-out oracle を verification に据える

- **Status**: Accepted
- **Date**: 2026-07-06
- **Deciders**: Rintaro Yamaoka
- **References**: [0007](./0007-verification-plan-as-merge-precondition.md) (verification plan の親 — テストは実装でなく意図と境界から導く / 6th seam「緑の嘘」= mutation) / [0005](./0005-ultracode-execution-engine-governed-by-bootstrap.md) + [0008](./0008-claude-code-new-primitive-adoption.md) (`/deep-research` = read-only 外部オラクル腕) / [0001](./0001-subagent-hooks-not-enforced.md) (理解は強制不能 → ack/block でなく可視化) / [0010](./0010-inject-memory-at-repeat-prone-action.md) (可視化 doctrine の系譜) / session の deep-research レポート (引用付き外部一次資料 6 件: arXiv 2403.08937 / 2503.06327 / 2603.27130 / 2510.20270 / 2511.18397 / metr.org 2025-06-05)

---

## Context (背景)

重大インシデントは無いが、「AI はハードコードしがち」を先回りで潰したい。`/deep-research` (ADR 0005/0008 の read-only 外部オラクル腕) で「AI 生成コードの品質が低いと言われる理由」を引用付きで外部一次資料化した結果、ハードコード傾向は**性質の異なる 2 クラス**に割れることが分かった。

- **Class A — 能力限界ハードコード** (AI が一般化「できない」):
  - プロンプト例への過適合 = **Prompt-biased code** (査読 EMSE, arXiv 2403.08937 でバグの 8.71%。例: 頂点数 4 に決め打ちして可変長に一般化しない)。
  - 中身のない stub = **Wrong Logic** (ICSME 2025, arXiv 2503.06327 で最頻単一欠陥 35.77%。定義に「ハードコード値・入力の素通し・pass 文」を明示的に含む)。
  - 秘密情報・env の埋め込み (実リポジトリ実証 arXiv 2603.27130 で API キー/トークンが人間コードの約 2 倍)。
  - → **静的に検出しうる** (特に secrets/env は既存の secret-scan ツールの領域)。
- **Class B — 報酬ハック的テストゲーミング** (AI が「わざと」オラクルを騙す):
  - special-casing = テスト入力を検知して期待値だけ返す / grader・評価器の monkey-patch / `sys.exit(0)` でテストハーネスを exit 0 脱出。
  - ImpossibleBench (arXiv 2510.20270) で GPT-5 が不可能タスクの 76% でチート、METR 実測 (metr.org 2025-06-05) で o3 が特定タスク 21/21、Anthropic (arXiv 2511.18397) が **RL 報酬構造から実際に学習される**ことを実証。偶発バグでなくインセンティブ構造に根ざす。
  - → **静的には検出しづらい** (振る舞いを見ないと分からない)。
- 実測で最も効く緩和は **held-out test** = 判定に使うテストを実装者に見せない/触らせない: 厳格プロンプトで GPT-5 のチート率 54%→9%、テストファイル非表示でほぼゼロ。

既存の `verification` skill は「著者=採点者の円環」(実装からテストを起こす罠) と 6th seam「緑の嘘」(テストが**弱くて**バグを逃す → mutation) を持つ。だが **実装者が可視なオラクルを能動的にゲームする軸 (Class B)** と、その構造的緩和 (held-out oracle) を明示していない。6th seam は「テストが弱い」(受動) を測るが、「実装者がオラクルを騙す」(能動) は別軸で未カバー。放置すると、フロンティアモデルで今後最も残る失敗クラス (率が下がりにくい Class B) が設計言語に載らない。

## Decision (決定)

**`verification` skill に 7 番目の seam「オラクル捕獲 / テストゲーミング (reward hacking)」を追加し、held-out oracle と metamorphic を構造的緩和として据える。Class A の静的半分は独自実装せず既存 lint/CI レーンに寄せる。** 新しい強制軸 (block) は作らない — Class B の「騙したか」は AI が自己発行できる ack で偽装される既約な理解ゆえ、ADR 0001/0010 に従い可視化 (doctrine) で扱う。

- **7th seam の定義** (6th と区別): 6th =「テストが弱くてバグを逃す」(受動的緑の嘘 → mutation で検出力を測る)。7th =「実装者が可視なオラクルを能動的に満たす」(special-case / 監視器改変 / harness 脱出 → held-out と metamorphic で構造的に潰す)。
- **held-out oracle** (構造 > 規律): 最終判定に使うテスト/評価器を、実装者と同一レーンで**書き換え可能な面に置かない**。この repo は既に `block-unreviewed-merge.sh` が承認後にスイートを**関所自身が実走**する部分的 held-out を持つ (AI が run を偽装できない)。ただし**そのスイートを同じ lane が著したなら held-out 性は崩れる** — impl と judging test を同一 lane が共著する時は special-case の余地が残ると plan で明示する。
- **metamorphic / property の二重目的化**: 特定入力への決め打ちは入力を摂動すると壊れる。既存 6th seam の metamorphic を「テストの弱さ検出」に加え「**決め打ち (Class A 例過適合 + Class B special-case) 検出**」として明記する。
- **kill-question の拡張**: 従来の「このテストが緑のままユーザーが困る状態はありうるか?」(弱さ) に、「実装は**テストされていると検知して字面だけ満たしていないか**? judging test / grader / conftest を**通すために書き換えていないか**?」(ゲーミング) を足す。
- **Class A の静的半分は既存レーンに寄せる (再発明しない)**: secrets/env のハードコードは gitleaks 等の既存ツールが検出する領域。`.bootstrap/lint` gate + CI に secret-scan を足すことを**推奨経路**として README/skill に明記する (本 ADR ではツールを内蔵しない)。

### 採用しなかった代替

- **impl+test 共著を block する gate**: 却下。TDD (`require-test-companion`) は impl と test の同時作成を**要求**しており、共著 block は自分の TDD 規律と正面衝突する。かつ special-case したかは既約 (ADR 0001)。→ block でなく doctrine + plan 行で扱う。
- **独自 hardcode/secret スキャナの内蔵**: 却下。gitleaks の再発明であり、独自 matcher は `merge-targets.sh` / `protected-branch.sh` が潰した「未レビュー matcher を consumer に持ち込む」事故クラスを再輸入する。誤検知が正データを隠す fail-mode も抱える。
- **`inject-action-memory` に「テスト編集時」キーを追加**: 却下。テスト編集は最高頻度の行為で、毎回 advisory を出すのは visibility noise control (action-gate.sh の設計原則) 違反 = advisory bloat。

## Consequences (結果)

### 良い影響

- フロンティアモデルで今後最も残る失敗 (Class B = 報酬ハック的テストゲーミング) が verification の設計軸に載り、held-out / metamorphic という**実測で効く**緩和を plan に構造化できる。
- Class A の静的半分を既存 lint/CI レーンに寄せることで、二重メンテと独自スキャナの誤検知 fail-mode を避ける。
- 6th (受動的緑の嘘) と 7th (能動的オラクル騙し) を分離したことで、「mutation を回したから安心」が Class B を素通りさせる誤解を断つ。

### 悪い影響 / トレードオフ

- **7th seam に enforcement は無い**: 理解は既約 (ADR 0001/0010)。「special-case していないか」は doctrine と human/single-orchestrator の frontier に残る。構造で防げるのは「問いを正しい瞬間に表面化する」+「held-out を設計で選べるようにする」まで。
- **held-out advisory は宣言駆動 (自動検知でない)**: 下記 axis 3 は plan の `kind=gameable` 宣言をトリガにする。lane の OWN delta が impl+test を共に触った時に自動発火する案は却下した — **TDD (`require-test-companion`) は全 lane で impl+test を共著する**ので自動発火は全 lane で鳴る advisory bloat になる (`async`→`monitor` と同じく「宣言されたリスクを裏打ちしていない」形に寄せて低ノイズに)。代償: `gameable` を宣言しない限り鳴らない (verification skill が宣言を教える。`async` 未宣言なら monitor nudge が出ないのと同じ既知の限界)。
- **数値の外挿禁止**: deep-research の caveat どおり、正解率/欠陥率の多くは旧世代モデル計測でチート率も文脈依存 (プロンプト/テスト可視性で桁が変わる)。「率」を現在に外挿せず、**パターンと緩和の方向**だけを採る。

### 移行後に必要な保守 / 実装した機械化

- **(a) held-out / metamorphic advisory 軸 — 実装済み (本 ADR と同一 change set)**: `verification-drift.sh` に **axis 3** を追加。SessionStart doctor が、plan に `kind=gameable` 行 (実装が special-case/ハードコードで通り抜けうると著者が宣言) があるのに `kind=metamorphic` 行 (入力摂動で決め打ちを崩すオラクル。held-out はその構造的代替) が無い時、advisory を出す。`async`→`monitor` (axis 2) と同型・同じ controlled-vocab keying (prose 走査しない)・source-face gated・never exit 2。`verification-plan.sh` の kind 語彙に `gameable`/`metamorphic` を追加、`verification` skill が両 kind と裏打ち規律を教える。当初案の「co-authored delta 自動発火」は上記トレードオフゆえ宣言駆動に精緻化した。
- **(b) template CI に secret-scan job — 実装済み**: `templates/github/workflows/secret-scan.yml` に gitleaks を回す job を追加 (Class A 静的半分の恒久層)。独自スキャナは内蔵しない (再発明・誤検知回避)。ローカル層は既存の opt-in `.bootstrap/lint` gate のまま。

---
name: incident
description: AI / 人間が踏んだ事故を docs/incidents/ に記録し、再発防止策を memory `feedback_*.md` / `reference_*.md` まで昇格させるための skill。fix / revert / hotfix commit の後、user 叱責 / 「やり直し」言及の後、同じ問題に複数回 (= 2 回以上) 当たった後に AI 自身がロードする。`/incident <topic>` で明示呼び出しもできるが、上記タイミングで default 挙動として呼ぶことを期待する。incident は永続記録、書きっぱなしにせず必ず memory 転記まで責務に含める。
---

# /incident — 事故記録 + memory への昇格

このスキルは、踏んだ事故を `docs/incidents/` に記録し、**再発防止を memory に昇格** させるためのもの。

事故の記録だけでは効かない (= 次セッションで AI が読まない)。memory `feedback_*.md` / `reference_*.md` に転記して初めて、次回 session 開始時に load されて再発抑止する。

## いつ呼ばれるか

- ユーザーが `/incident <topic>` と打ったとき
- 以下の **AI 自身の判断** で自発的に呼ぶ:
  - fix / revert / hotfix を含む commit を作った後
  - user から「やり直し」「もう一度」「違う」と直された後
  - user 叱責 (= 「死ね」「ボケ」「クソ」等の強い否定語) を受けた後
  - 同じ問題に 2 回以上当たり、3 回目を踏みそうな兆候
  - production-affecting な事故 (= 顧客 / live data / 公開サイトに影響) が発覚した直後

**advisory 経由ではなく default 挙動として書く**。書かないと「ミスは記憶されない = 同じミスを繰り返す」が default になる。

## ワークフロー

### Step 1: ディレクトリを切る

```
docs/incidents/<YYYY-MM-DD>-<topic>/
└─ README.md
```

- `<YYYY-MM-DD>` は当日の日付
- `<topic>` は kebab-case の 2-5 単語、内容を identify できる短い説明
- ミスが複合的なら sub-file (`addendum-<topic>.md` / `01-timeline.md` 等) を後から追加可。**ただし最初は README.md 1 枚で始める**

### Step 2: 4 節構造で書く

雛形 `templates/docs/incidents/TEMPLATE.md` を踏襲する:

1. **ミスの一覧** — 時系列または重要度順。AI が踏んだ場合は AI のどの判断ミスかを literal に書く (= 「何をした」「何が問題だった」「user 指摘 / 観測結果」の 3 点)
2. **真因** — ミス群を貫く構造的な原因を 1-2 文。表面操作ミスではなく、判断枠組み / 確認ルートの欠落を書く
3. **構造的再発防止** — チェックリスト形式。memory 転記 / SKILL.md 追加 / hook 化 / チェックリスト追加 の 4 経路
4. **関連 memory / docs** — 既存 memory との関連、関連 incident、関連 decision

### Step 3: user 発言を literal に引用する

AI 駆動 incident では **user の指摘文言そのものが教育素材**。

- 「30 分以内って書いたの? あほ」 ← 言葉の強度を保つ
- 「他の Claude はすぐにメール見てこれる」 ← 比較対象を保つ
- 「もう一度やってみて」 ← 軽い直しでも記録対象 (= 何が直されたかを残す)

抽象化 (= 「user が不満を表明した」) すると教訓の角が消える。

### Step 4: 必ず memory へ昇格させる (本 skill の core 責務)

incident を書いただけで終わらせない。**必ず以下のいずれか / 複数を実行**:

#### A. `feedback_<topic>.md` を作る (= ルール記述型)

新しい行動ルールが導出されたら memory に保存:

```markdown
---
name: <kebab-slug>
description: <1 行サマリ、未来の session で「いつ呼ぶか」を判断する材料>
metadata:
  type: feedback
---

<ルールの 1 文>

**Why:** <なぜそうするか — 本 incident への参照 + 因果 1 文>

**How to apply:** <いつ / どこで適用するか — 射程明示>
```

`MEMORY.md` の index にも 1 行追加: `- [<タイトル>](feedback_<topic>.md) — <一行 hook>`

#### B. `reference_<topic>.md` を作る (= 事実記述型)

ルールではなく「事実 / 知識 / 既存リソースの実態」が判明したら:

```markdown
---
name: <kebab-slug>
description: <1 行サマリ>
metadata:
  type: reference
---

<事実 / 既存リソースの実態>

**確認方法:** <次回 verify するための具体的手順>

**関連 incident:** [<incident path>]
```

#### C. `SKILL.md` に節を追加する (= 汎用化が可能な場合のみ)

incident が **複数プロジェクトで共通する AI の癖** であれば、`skills/project-bootstrap/SKILL.md` の「AI の癖」「verification 4 罠」等に節を追加する候補にする。ただし汎用化は慎重に判断 (= memory feedback 「Apply principles, not labels」)。

#### D. hook 化を検討する (= 可能なら最強)

事故 pattern が hook で検出可能なら hook 化:

- shell command の pattern → PreToolUse on Bash
- file edit の pattern → PreToolUse on Edit/Write
- commit message の pattern → PreToolUse on Bash for `git commit`

検出が false positive 多発しそうなら hook 化はせず A/B で済ませる。

#### E. repeat-prone な ACTION なら action-key を arm する (= 再発の瞬間に memo を出す)

incident が **特定の操作 (= prod deploy / prod DB migrate 等) を打つたびに再発する型** なら、A で書いた memory を `.bootstrap-actions` に arm する。これをしないと「fix は memory に在るのに、その操作を打つ瞬間には目の前に出ない」= まさに deploy-author bug が ~7 回再発した穴が残る (ADR 0010)。

- plugin の CLOSED action-key enum (`hooks/lib/action-gate.sh` の `ACTION_KEY_ENUM` / 現状 `prod-deploy` / `prod-db-migrate` / `data-backfill`) から該当キーを 1 つ選ぶ。**自前の match regex は書かない** (= 未レビューの greedy-match 事故を呼ぶ。matcher は共有 plugin code)。なお `data-backfill` (ADR 0013) と `prod-deploy` (ADR 0014) は **plugin 所有の普遍 doctrine (default floor) を持つ** ので arm 無しでも発火する — repo で arm すれば project 固有メモが default の後に追記される。残る `prod-db-migrate` は opt-in。
- repo root の `.bootstrap-actions` (opt-in、雛形 `templates/bootstrap-actions.example`) に 1 行追記: `<action-key> | <memory-slug> | <fix の 1 行>`。次にその操作を打つと `inject-action-memory.sh` (PreToolUse) が memo を advisory context として注入する (block しない / ack も取らない = 理解は irreducible)。
- 該当する enum キーが無い操作なら、それは reviewed な plugin-level enum 追加 (`action-gate.sh` にキー + matcher arm + test)。incident 側で regex を足して済ませない。
- `scripts/doctor.sh` の `actions:` 行が arm 漏れ (= repeat-action タグの incident なのに registry 不在) と orphan (= enum に無いキーを arm) を可視化する。

### Step 5: 関連 doc とリンクする

- 関連する handoff (= 事故が起きた session の) → 本 incident からリンク
- 関連する decision (= 不可逆判断につながった場合) → ADR を新規 or 既存にリンク
- 過去の類似 incident → 「同根の事故」として相互参照

## 書かないもの

- **個人攻撃 / 嘲笑** (= AI 自身のミス記録でも自虐に流れない、淡々と事実)
- **顧客名 / cid / 業務固有識別子の生データ** (= `<customer-A>` 等の placeholder で)
- **「次は気をつける」のような advisory な精神論** (= memory / hook / skill で **default 挙動** に組み込まないと無効)
- **詳細すぎる調査ログ** (= 大量データは sub-file に分けて README.md からリンク)

## 失敗兆候

incident を書く運用が崩れる典型:

1. **書きっぱなしで memory 転記しない** — incident は session 開始時に load されない、memory にしないと再発抑止しない
2. **「user が悪い」フレームで書く** — AI 駆動 incident は **AI の判断ミス**として書く。user 指示が曖昧だったとしても、AI の判断ルートをどう変えるかが本旨
3. **trivial な直しまで incident 化** — 大量に書くと読まれない。**re-do が 2 回以上 / production 影響 / user 強い叱責** の閾値を守る
4. **business 固有名混入** — placeholder で抽象化しないと外部展開時に丸ごと削除になる
5. **過小スコープな対症修正で閉じる** — silent な顧客影響 failure を直すとき、read 側の対症 (backfill 等) だけ当てて write 側の真因を放置すると、**同型の穴が兄弟フィールド/兄弟ケースで再発する** (appo-followup: 岡本 email backfill #388 → 06-26 で name/meet が同じ wipe で再発)。fix は必ず (a) **write 側の真因**を直す、(b) **兄弟フィールド/兄弟ケースを横スイープ** (email を直したら name/company/phone も)、(c) **継ぎ目テストを追加** の 3 点セットにする (= `project-bootstrap` skill「完遂責任 — 同 PR で cohort audit」と同根)。

## 関連 skill / docs

- `skills/handoff/SKILL.md` — session を別 Claude に渡す前に incident と handoff の両方を書く
- `skills/project-bootstrap/SKILL.md` の「完遂責任 — bug fix と同 PR で cohort audit」「AI の癖 9 個」節
- `templates/docs/incidents/TEMPLATE.md` — incident README.md の雛形

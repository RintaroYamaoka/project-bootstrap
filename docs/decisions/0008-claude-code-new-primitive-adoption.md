# 0008 — Claude Code 新 primitive の採用方針 (prompt/agent hook / exec-form / saved workflow)

- **Status**: Accepted (#1 実装済み / #2 受諾 → opt-in pilot 実装済み / #3 却下 / #4 却下 — plugin は workflow を配布不可と確認)
- **Date**: 2026-06-21
- **Deciders**: Rintaro Yamaoka
- **References**: 本 repo の評価 workflow (2026-06-21、local audit + web research + 3-vote adversarial verify)。`docs/decisions/0004-*` / `0005-*` / `0006-*` (並列 governance の系譜)。Claude Code docs: [hooks](https://code.claude.com/docs/en/hooks) (handler 5 型) / [workflows](https://code.claude.com/docs/en/workflows) (bundled `/deep-research`, saved workflows) / [goal](https://code.claude.com/docs/en/goal)。`skills/project-bootstrap/SKILL.md` の AI 癖 (3 scope-creep / 4 症状隠蔽 / 7 不在断定) と「完遂責任」cohort audit。

---

## Context (背景)

Claude Code が進化し、評価 workflow で実在を確認した新 primitive が複数ある。**機能の存在は 3-vote adversarial verify または公式 doc 直読で確認したが、バージョン番号は信頼しない** — 検証での反証 3 件はすべて版番号の誤りで、機能自体は実在した:

- **hook handler が 1→5 型**: `command` / `http` / `mcp_tool` / `prompt` (単発 yes/no のモデル評価) / `agent` (subagent が Read/Grep/Glob で判定して block。experimental)。
- **exec-form `command` hook**: `args: string[]` で shell を介さず spawn。
- **saved workflows**: `/workflows`→`s` で `.claude/workflows/` に保存し `/<name>` コマンド化。
- 別 ADR 不要だったもの: **`/deep-research`** = bundled Workflow (read-only breadth 腕として編入)。**`/goal`** = session 内 autonomous loop で、評価器が tool を呼べず本プラグインの「実テストを回す」gate より弱い → 取り込まない。**`/workflow` (ultracode)** = ADR 0005/0006 が既に実行エンジンとして governance 済み → 足さない。

問い: これらを bootstrap に取り込むか。とくに `prompt`/`agent` hook は、本プラグインが現状 **advisory のまま放置している規律** (癖 3 scope-creep / 癖 4 症状隠蔽 / cohort audit / ADR 習慣) を gate 化する初めての手段になりうる — だが確率判定は決定論 gate (② 信号選び) の原則を曲げる。無音で見送らず、1 件ずつ disposition する。

## Decision (決定)

新 primitive ごとに別 disposition。**4 設計判断は 5 にしない** (①〜④ の適用方針であって新軸ではない。ADR 0005/0006 と同じ立場)。

### 1. `/deep-research` を breadth 腕として編入 — 実装済み (本 ADR 不要だった)

read-only の web 照合腕を `skills/plan` (前提検証 Step) / `skills/verification` (外部事実オラクル) / `skills/project-bootstrap` (癖 7) に編入。「オラクルは AI の外」(verification skill) の web 版で、advisory input 限定 (`HUMAN`/意図行を web claim で自動 close しない — stale/hallucinated な引用が偽オラクルになりうる)。harness の bundled Workflow を呼ぶだけなので二重化せず同梱もしない。

### 2. `prompt`/`agent` hook で advisory 規律を gate 化 — **Proposed (受諾待ち)**

現状 advisory (= 実質何も強制していない) の規律を確率 gate に**昇格**するのは純増 — 決定論 gate を確率で**置換**するのではない (置換は禁止: TDD / arch / merge gate は決定論のまま)。受諾するなら以下を**全て**満たす:

- **(a) block でなく warn から始める** (`prompt` hook の非 block 出力)。誤検知は guard を無効化する (`docs/incidents/2026-05-29-cross-wip-bash-false-positive` = cry-wolf)。捕捉率が確認できてから block 化を別途判断。
- **(b) 誤検知率を metric で監視** (④)。`velocity.sh` と並ぶ列を持ち、誤検知が閾値を超えたら撤回する。計測なき確率 gate は盲信に戻る。
- **(c) CI でテスト不能**を明記。モデルを呼ぶ hook は pure-bash の self-CI (`tests/hooks/`) の射程外。だから pilot を **1 本 (cohort-audit) に限定**し、実運用で誤検知/捕捉率を測ってから展開可否を決める。
- **(d) 対象は advisory 規律のみ** (癖 3 / 癖 4 / cohort audit)。決定論で書ける gate (新規 source / 依存方向 / merge) は確率化しない。

受諾されたら cohort-audit pilot を実装する。本 ADR は「確率 gate を入れてよい条件」と「決定論 gate を置換しない線引き」を固定する。

**受諾・実装 (2026-06-21)**: スキーマを公式 docs で検証した — `type: "prompt"` hook は `Stop` イベントで動き、model (既定 Haiku) は `{"ok": bool, "reason": str}` を返す。`Stop` で `ok:false` のとき **reason が Claude に戻り作業を継続** (= block でなく warn nudge、条件 a を満たす)。これを `templates/hooks/cohort-audit-pilot.json` に実装。**default の 17 hook (当時; 0.24.0 で 19) には入れない** — 確率 gate を全 consumer に毎ターン強制するのは pilot でなく full rollout なので、**opt-in テンプレ**にして blast radius を絞り、enable した repo で誤検知率を観測してから default 昇格を判断する (条件 b/c)。prompt は「user-facing bug fix かつ cohort audit 不在のときだけ ok:false / それ以外と不確実は ok:true」で cry-wolf を抑える。CI テスト不能 (条件 c) ゆえ measurement は実運用の手動観測 — `velocity.sh` の defect-rate と並べて誤検知が多ければ撤回する。`hooks/README.md` の「opt-in pilot」節と `skills/project-bootstrap/SKILL.md` の完遂責任節にミラー (ADR→SKILL、ADR 0003)。

### 3. exec-form hook (`args[]`) — **却下**

hook の起動文字列 `bash "${CLAUDE_PLUGIN_ROOT}"/hooks/X.sh` には **untrusted 入力が一切流れない** (path は harness 設定の trusted env、追加引数なし、`"..."` で空白も安全)。shell injection 面が存在しないので exec-form 化は**硬化すべき脅威が無い** = rent を払わない複雑さ。加えて exec-form で `${CLAUDE_PLUGIN_ROOT}` が展開されるかが未検証で、誤ると**全 hook が無音で壊れる** (リスク > 利得)。doctrine「rent を払わない複雑さを足さない / 不確実な harness 依存を盲目的に入れない」に従い却下。将来 hook command に untrusted 入力を渡す設計が出たら再検討。

### 4. saved workflow (`.claude/workflows/`) を同梱 — **却下 (2026-06-22 確認済み)**

並列 adversarial レビューを `/bootstrap-review` として再利用可能な saved workflow にする案。**plugin は workflow を配布できないと確認した** — 公式 plugin structure の package 可能 component は skills / commands / agents / hooks / MCP / LSP / monitors / bin / settings のみで、**`workflows/` ディレクトリは存在しない** ([plugins docs](https://code.claude.com/docs/en/plugins) の plugin structure overview)。consumer の `.claude/workflows/` へは手動 save しか経路が無く「同梱」は成立しない。よって却下。レビューの再利用は `integrate` skill のレビュー Step が breadth fanout (ADR 0005、隔離不要・`wip_limit` 非対象・gate 摩擦ゼロ) を直に使えば足り、別 saved workflow を要しない。(手動 save 用テンプレを `templates/` に置く余地は残るが「同梱」ではなく、breadth fanout で足りる以上 rent を払わないので現時点では作らない。)

## Consequences (結果)

### 良い影響
- 「新 CC 機能を取り込むか」が 1 件ずつ理由つきで disposition され、**無音で見送らない** (③ の自己適用)。
- #1 で「オラクルを AI の外から取る」実体ができ、癖 2/7 と verification の長年の空白を埋めた。

### 悪い影響 / トレードオフ
- #2 を受諾すると **初の非決定論 gate** が入る。線引き (advisory 昇格のみ / block でなく warn 始動 / 誤検知 metric / 決定論 gate は置換しない) を破ると、プラグインの「決定論で確実に効く」信条が薄まる。本 ADR の条件 (a)〜(d) がその歯止め。
- #2 はモデルを呼ぶため self-CI で守れない。pilot を実運用の測定で守るしかない。

### 移行後に必要な保守
- #2 受諾 → cohort-audit pilot を実装、誤検知列を `velocity.sh` に追加、N 週後に展開可否を判定。
- #4 → 確認済み・却下 (plugin は workflow を配布不可)。レビュー再利用は `integrate` の breadth fanout で足りる。手動 save テンプレの要望が出たら `templates/` に置く (同梱ではない)。
- 新 primitive の**版番号は信頼しない**方針を維持 (CC アップグレード時は機能の存在を doc で再確認。`hooks/README.md` の harness contract 節と同じ規律)。

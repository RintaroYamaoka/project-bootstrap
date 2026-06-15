# 0005 — ultracode/Workflow を「実行エンジン」と位置づけ、bootstrap の関所で governance する (ADR 0004 を一般化)

- **Status**: Accepted
- **Date**: 2026-06-15
- **Deciders**: Rintaro Yamaoka
- **References**: `docs/decisions/0004-parallel-mode-integration-gate.md` (本 ADR が一般化する正本) / `docs/decisions/0001-subagent-hooks-not-enforced.md` (前提の系譜) / `docs/incidents/2026-06-11-parallel-mode-gate-coverage` / Claude Code の `ultracode` (= `xhigh` effort + dynamic workflow 自動 orchestration) / Workflow tool (single-turn multi-agent orchestration)

---

## Context (背景)

Claude Code 本体に `ultracode` (= `/effort ultracode`、または prompt 内キーワード) が入った。実体は **`xhigh` effort + Workflow tool による subagent の自動 orchestration** で、1 turn 内で最大 16 並列・最大 1000 agent をファンアウトする。これは本プラグインの sprint-plan / integrate が担う「1 feature を複数 Claude で並列開発する」と**機能が重複する**。

確定している事実:

- ultracode/Workflow は ADR 0004 が公認した**並列 3 形態の ③ (Workflow subagent 並列 + main session 統合) そのもの**。新しい並列方式ではなく、③ をハーネス側が一級コマンド化したもの。
- subagent の edit/merge/commit には plugin hook が発火する (ADR 0004、2026-06-11 実測 / 2026-06-15 再実測: 一時ではなく本 repo で subagent に新規 source の Write を指示 → `block-unplanned-feature-build.sh` が exit 2 で block)。
- **hook は Workflow 内部の `agent()` spawn を観測できない**。`hooks.json` の PreToolUse matcher は tool 名 (`Edit|Write|MultiEdit` / `Bash`) で発火するが、Workflow runtime が産む subagent は main session の tool 呼び出しではないため、内部 16 並列の **spawn そのもの**は PreToolUse に届かない。届くのは各 subagent が実際に行う Edit/Write/Bash と、main session が打つ最上位の Workflow 呼び出しだけ。
- bootstrap が持ち ultracode が原理的に持たない層がある: **永続性** (board / handoff / incident / ADR が `/clear`・session 死を越える) / **強制** (hook が precondition を fail-closed) / **実検証** (統合の入口で実テストスイート) / **横断 memory**。ultracode は揮発的 (1 turn で消える)・無強制・agent 判定どまり。

放置できない理由: どちらを使うかが Claude の気分次第になると、ultracode に転んだ日に sprint-plan の WIP 上限・lane 隔離・統合関所が**素通り**になりうる (gate 無音化 class の再来)。重複を「競合」のまま放置せず、層の境界を doctrine で固定する必要がある。

## Decision (決定)

**ultracode/Workflow を独立した並列方式として扱わず、bootstrap が governance する「実行エンジン」と位置づける。** 4 つの設計判断を 5 に増やさない — これは方式の重複を解く scope/層別の宣言であって、新しい設計軸ではない。

1. **ultracode の 2 つの顔を別 governance にする。**
   - **breadth (read-only ファンアウト)**: 探索 / 監査 / 移行発見 / レビューの多レンズ。**無制限・隔離 worktree 不要・`wip_limit` 非対象・gate 摩擦ゼロ**。lane ではないので review 帯域も消費しない。plan / sprint-plan の探索 Step と integrate のレビュー Step に置く。
   - **mutation lane (source を書き換える subagent)**: 形態 ③ そのもの。**必ず隔離 worktree** (Workflow の `isolation:'worktree'`)、`wip_limit` 対象、edit/merge/commit gate を terminal worker と同一に通過。
2. **WIP・隔離の強制は spawn 時でなく edit/merge/commit 時に置く。** hook は Workflow 内部 spawn を見ないので、「16 並列を spawn で止める」設計は構造的に不可能。代わりに、各 subagent の Edit (隔離 lane 判定) と統合の入口 (`git merge` / `git commit` 時の lane 数・レビュー記録・実テスト) で縛る。これは ADR 0004 の「方式でなく統合の入口に関所を置く」を WIP と検証へ一般化したもの。
3. **agent 判定のレビューは実検証を代替しない。** `block-unreviewed-merge.sh` は `verdict: approve` を確認した上で、**検出したテストスイートを関所自身が実行**し fail なら block する (= `tests:` 行のような自由文を信じない。信号は実テストの実行結果)。LLM が LLM を判定した記録を実検証に化けさせない。検出は commit gate と共有 lib (`lib/detect-test-suite.sh`、単一権威で drift 防止)、runner 未検出は fail-open。

採用しなかった代替案:
- *ultracode を gate で禁止して sprint-plan に誘導* → 「実装させる Workflow か」の判定が語彙解析になり穴が空く (ADR 0004 で却下済みの理由がそのまま該当)。subagent に hook が効く今、禁止する理由が無い。
- *ultracode を 5 番目の設計判断として doctrine に追加* → SKILL 名・skill description・memory がすべて「4 判断」で、増やすと正本が分裂する。これは ④ までの判断を**適用する対象**であって新判断ではない。
- *breadth ファンアウトも `wip_limit` 対象にする* → read-only は review 帯域 (= 全 repo 共有の律速資源) を消費しないので縛る根拠が無い。16 並列の探索を lane 数と混同すると `wip_limit` を黙って引き上げることになり、scrum の本質 (WIP 制限) に反する。

## Consequences (結果)

### 良い影響

- 機能重複が「競合」から「層の包含」に変わる: bootstrap が governance/lifecycle/durability、ultracode が実行エンジン。hook が subagent に効くので bootstrap が ultracode を**包める** (排他でない)。
- breadth ファンアウトが正式に gate 摩擦ゼロの一級経路になり、探索・レビューを速くできる (本 ADR 自体の設計も理解フェーズを Workflow にファンアウトして行った)。
- WIP・隔離・実検証の 3 guard が「どの並列方式でも」統合の入口で効く。

### 悪い影響 / トレードオフ

- WIP・隔離を spawn 時に予防できない (構造的限界)。guard 3 は観測可能な `git worktree add` を信号にするが、Workflow 内部の isolation worktree 生成は見えない — そこは統合の入口 (guard 1: 各 lane が review + 実スイート) が最終 net。breadth と mutation の区別を skill 側が正しく出力することに依存する。
- guard 1 は merge が PreToolUse ゆえ統合"後"の結合状態は測れない (統合先が緑であることまでを保証。post-merge 全スイートは integrate skill Step 3 が担う)。
- guard 2 (mutation の worktree 隔離) は `block-uniso-main-edit.sh` が「main worktree + active lane + 非統合操作中 + source 面」の全条件で block する精密な信号で実装。誤検知を避けるため統合操作中 (MERGE_HEAD / rebase / cherry-pick / revert) は fail-open にしており、その間の shared-tree 編集は通る (= lead の conflict 解決を妨げない代わり、統合中の未隔離 mutation は検出しない — 誤検知 > false negative の意図的なトレードオフ)。`block-cross-claude-wip.sh` (commit 時) が二重の net。新 gate は lead の正当な作業を誤爆しやすく (誤検知 > false negative)、慎重な設計を要するため分離した。

### 移行後に必要な保守

- subagent への hook 配達は upstream の挙動に依存する (ADR 0004 から継承)。回帰したら本 ADR の guard も ADR 0001 の回避設計に戻す。再検証手順は ADR 0004 / incident に記録済み。
- ハーネスが Workflow 内部 spawn を PreToolUse に surface するようになったら、WIP を spawn 時に予防する設計へ見直す (superseding ADR を起こす)。
- 本 ADR の運用ルールは `skills/project-bootstrap/SKILL.md` の並列 3 形態節にミラーすること。ADR が SKILL に反映されないと runtime で発火しない死んだ governance になる (ADR 0003 の警告)。

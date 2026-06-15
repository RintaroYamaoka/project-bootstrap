---
name: integrate
description: 並列開発した複数の feature branch を依存順に統合し、統合 verify を通して claim を閉じる skill。sprint-plan で分解した task が in-review になったら lead がロードする。depends_on の topological order で merge し、各 merge 後に全テストスイート (= task 単位でなく統合の verify) を回し、conflict を解消し、board.json の status を done に、worktree を撤去する。並列開発が壊れるのは統合フェーズなので、ここに単一の coherent view を置く。「統合して」「マージして」「sprint を閉じて」と言われたとき、または board の task が出揃ったときにロードする。
---

# /integrate — 並列レーンを安全に組み戻す

`sprint-plan` で分解・並列実装した branch を統合する skill。並列開発の事故は統合フェーズに集中するので、**merge 順序と統合 verify を単一の頭脳 (lead) で所有する**。

## いつ呼ぶか

- board の task が `in-review` (= worker が push 済) になった
- 「統合して / マージして / sprint を閉じて」と言われた

## ワークフロー

### Step 1: board を読み、依存順を決める

`docs/sprint/board.json` を読む。`depends_on` で **topological order** を作る (= 直列 spine task が先、その下流が後)。`in-review` / `done` でない task があれば、それを待つか lead が引き取る。

### Step 2: merge 前に adversarial AI レビュー → verdict を記録 (人間は全 diff を読まない)

throughput の律速は人間のレビュー帯域 (しかも user は複数プロジェクト並行 = 全 repo 共有の単一資源)。一次レビューは **read-only の subagent** に移す — レビューは判定であって mutation を伴わないため、どの並列形態 (worker ターミナル / PR / Workflow lane) でも同じ agent 設計で回せる (ADR 0001→0004)。

依存順に、各 task について merge の**前に**:

1. **adversarial レビュー agent を回す** (read-only)。プロンプトの態度は「この branch を落とすつもりで読む」: 正しさ / 統合境界 (共有 interface の前提ずれ) / verification 4 罠 / scope 逸脱。観点が複数要るなら lens を分けて並列に — これは ADR 0005 の breadth 顔なので **Workflow で 1 lens = 1 subagent に最大 16 ファンアウト**してよい (read-only・隔離不要・`wip_limit` 非対象)。ただし**各 lens を `reviews/<branch>.md` に並行追記させない** (verdict 行が競合して監査証跡が壊れる) — 各 subagent は指摘を**返り値で返し**、main session が 1 つの verdict 記録に集約する
2. **結果を `docs/sprint/reviews/<branch名の `/` を `_` に置換>.md` に書く**。必須行は `verdict: approve` または `verdict: reject`、以下に指摘一覧。この記録は commit する (= defect 発生時に「どの verdict が通したか」を遡る監査証跡)
3. **人間が読むのは: verdict / 指摘一覧 / diff のサンプル 1-2 割 / 統合境界だけ**。全 diff の目視はしない — それをやると lane を増やしても throughput が増えない
4. `reject` なら worker lane に指摘を差し戻し、修正後に re-review。記録は上書きでなく verdict 行を更新する

> **この precondition は gate で強制される** (`hooks/block-unreviewed-merge.sh`)。活性 sprint 中の task branch を `git merge` しようとした瞬間、レビュー記録が無ければ block、`verdict: reject` のままなら**より強く** block (却下の踏み越え禁止)。「レビューの質」は gate で保証できないので、velocity (`scripts/velocity.sh`) の defect rate が跳ねたらレビューを 1 段厚く戻す — これが安全網。
>
> **agent 判定の `verdict: approve` は実テストスイートを代替しない** (ADR 0005 guard 1)。Workflow 自身の subagent が下した approve は LLM が LLM を判定した記録であって、実検証ではない。`block-unreviewed-merge.sh` は approve を確認した上で**検出したテストスイートを自分で実行**し、fail なら block する (= `tests:` 行のような自由文を信じない。信号は実テストの実行結果そのもの。runner 未検出は warn して fail-open、commit gate と同じ)。これにより approve は「レビューが起きた」証明であって「テストが通った」証明ではない、が構造的に担保される。なお merge は PreToolUse なので統合"後"の結合状態は測れない (Step 3 の post-merge 全スイートが本体) — 関所が保証するのは「統合先が緑」まで。

### Step 3: 1 task ずつ merge → 統合 verify

依存順に、各 task について:

1. その branch を統合先 (= integration branch or main) に merge する (= review gate を通過する)
2. **全テストスイートを回す** (= その task のテストだけでなく、統合後の全体)。これが verification の本体。task 単位で緑でも、統合で semantic 結合が壊れることがある (= 共有 interface の前提ずれ)
3. fail したら **その merge を戻して原因を特定**。conflict / 結合バグは「症状を隠す」のでなく根本 (= interface の前提ずれ等) を直す
4. 緑なら次の task へ

scope を disjoint に切れていれば file conflict はほぼ出ない。出たら **分解が甘かった signal** (= incident / 次回の sprint-plan へのフィードバック)。

### Step 4: cohort / verification の最終確認

統合後、production-affecting な変更があれば `project-bootstrap` SKILL の verification 4 罠を最終 gate として確認する。user-facing bug fix を含むなら同根 cohort audit も。

### Step 5: claim を閉じ、worktree を撤去

各 task の `status` を `done` に。worktree を撤去する:

```
git worktree remove ../wt-<id>
git branch -d feat/<id>-<topic>   # merge 済を確認してから
```

board の全 task が done になったら sprint 終了。**board.json と `reviews/` を必ず `docs/sprint/archive/` へ移す** (board は `archive/<sprint>.json`、レビュー記録は `archive/<sprint>-reviews/`) (= sprint 終了の定義に board の終端処理を含める。残置は任意ではない)。ephemeral state の残置は権威の分散そのもので、実際に完了済み board の残置が sprint 発火 gate を 2 週間無音バイパスさせた (`docs/incidents/2026-06-07-stale-board-gate-bypass`)。gate 側も信号を「board の存在」から「未完了 task の有無 (活性)」に直してあるが、archive は防御の二重化ではなく lifecycle の責務 — 次の sprint-plan が古い board と衝突しないための正本整理。

## やってはいけないこと

- **統合 verify を省く** (= 各 task 緑だから OK と決めつける。結合は別物)
- conflict を握り潰す merge (= `-X ours`/`theirs` で機械的に潰して中身を見ない)
- 未 merge branch の `git branch -D` (= 強制削除は作業を消す。`-d` で merge 済を確認)
- main への直接 push (= `block-push-to-protected.sh` が止める。PR / integration branch 経由で)

## 関連

- 分解 = `skills/sprint-plan/SKILL.md`
- 事故が出たら = `skills/incident/SKILL.md` (分解の甘さ / 結合バグを記録 → 次回 sprint-plan に反映)
- 並列の安全規律 = `skills/project-bootstrap/SKILL.md`「並列開発フロー」節

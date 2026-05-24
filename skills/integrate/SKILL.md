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

### Step 2: 1 task ずつ merge → 統合 verify

依存順に、各 task について:

1. その branch を統合先 (= integration branch or main) に merge する
2. **全テストスイートを回す** (= その task のテストだけでなく、統合後の全体)。これが verification の本体。task 単位で緑でも、統合で semantic 結合が壊れることがある (= 共有 interface の前提ずれ)
3. fail したら **その merge を戻して原因を特定**。conflict / 結合バグは「症状を隠す」のでなく根本 (= interface の前提ずれ等) を直す
4. 緑なら次の task へ

scope を disjoint に切れていれば file conflict はほぼ出ない。出たら **分解が甘かった signal** (= incident / 次回の sprint-plan へのフィードバック)。

### Step 3: cohort / verification の最終確認

統合後、production-affecting な変更があれば `project-bootstrap` SKILL の verification 4 罠を最終 gate として確認する。user-facing bug fix を含むなら同根 cohort audit も。

### Step 4: claim を閉じ、worktree を撤去

各 task の `status` を `done` に。worktree を撤去する:

```
git worktree remove ../wt-<id>
git branch -d feat/<id>-<topic>   # merge 済を確認してから
```

board の全 task が done になったら sprint 終了。board.json は次 sprint まで残すか archive する。

## やってはいけないこと

- **統合 verify を省く** (= 各 task 緑だから OK と決めつける。結合は別物)
- conflict を握り潰す merge (= `-X ours`/`theirs` で機械的に潰して中身を見ない)
- 未 merge branch の `git branch -D` (= 強制削除は作業を消す。`-d` で merge 済を確認)
- main への直接 push (= `block-push-to-protected.sh` が止める。PR / integration branch 経由で)

## 関連

- 分解 = `skills/sprint-plan/SKILL.md`
- 事故が出たら = `skills/incident/SKILL.md` (分解の甘さ / 結合バグを記録 → 次回 sprint-plan に反映)
- 並列の安全規律 = `skills/project-bootstrap/SKILL.md`「並列開発フロー」節

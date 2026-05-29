---
name: sprint-plan
description: 1 つの feature を複数 Claude で安全に並列開発するための sprint 計画 skill。feature を scope 非重複 (= 触る file glob が重ならない) の task に分解し、共有 interface/型は直列 spine (depends_on) に切り出し、各 task に worktree + .bootstrap-lane を用意して、ワーカー起動文を吐く。並列が本当に得かを WIP 上限と disjoint 性で判定し、得でないなら逐次を勧める。実装はしない (= 計画と worktree 準備まで)。これは default 挙動として自動でロードする: feature の実装に着手し、探索の結果 scope 非重複の leaf が 2 個以上 (≤ wip_limit) に割れると判断したら、「並列で」「チーム/スクラムで」と言われなくても自動で起動する (= 明示呼び出し待ちにしない)。bug fix / refactor / 単一 file / 自明な小変更には起動しない。「並列で」「チーム/スクラムで」「複数ターミナルで」と明示されたときも当然ロードする。統合は integrate skill が担う。
---

# /sprint-plan — feature を安全に並列分解する

複数の Claude (= 別ターミナル / 別 worktree) で 1 feature を並列開発するための計画を立て、worktree と lane を用意する skill。**実装はしない**。`/plan` の単一タスク版に対し、これは並列タスクの分解版。

## 大前提 — 並列は得なときだけ

並列の収益は凹型カーブで変曲点は低い (ソロ開発で実質 2-3)。**まず「並列にすべきか」を判定する**:

- feature が **scope 非重複の leaf** に割れるか? 割れないなら逐次でやる (= 無理に刻むと協調コストが利得を食う)
- 共有 interface / 型 / 契約 があるか? あるなら **それを先に作る直列 spine** が要る。spine 完了前に下流を並列化しない
- 同時 lane 数 ≤ `wip_limit` (既定 2-3) か? 超えるなら lane を減らす。レビューは人間 1 人で直列なので throughput は増えない

判定の結果「並列にする価値が薄い」なら、**正直にそう言って逐次 (/plan → TDD) を勧める**。

## ワークフロー

### Step 1: 探索 (read-only)

`/plan` と同じく `Read` / `Grep` / `Glob` だけで feature の影響範囲を把握する。**この段階で Edit / Write しない**。

### Step 2: scope 非重複の task に分解

- 各 task の **owned file glob** を決める。**task 間で glob が重複してはいけない** (= 並列の不変条件)
- 重複が避けられない file (= 共有 interface / 型 / 設定 / 共通 util) は、それを作る/変える **直列 spine task** に切り出し、依存する task の `depends_on` に入れる
- task は 1 責務・1 PR 単位。細かく刻みすぎない (= 1 lane が 1 画面の責務に収まる粒度)

### Step 3: board.json を書く

`docs/sprint/board.json` を生成する (雛形 `templates/docs/sprint/board.example.json`)。`sprint` / `wip_limit` / 各 task の `id` `title` `scope` `branch` `depends_on` `status: todo` `worktree: null` `claimed_by: null`。

### Step 4: 並列可能な leaf だけ worktree を用意

`depends_on` が空 (or 既に done) の task のうち、**`wip_limit` 個まで** worktree を作る:

```
git worktree add ../wt-<id> -b feat/<id>-<topic>
```

各 worktree root に **`.bootstrap-lane`** を置く (= board の `scope` を 1 行 1 glob で展開):

```
printf '%s\n' "src/auth/**" "tests/auth/**" > ../wt-<id>/.bootstrap-lane
```

`.bootstrap-lane` を各 worktree の `.gitignore` に追加する (= commit しない)。これで `block-out-of-lane-edit.sh` が宣言外編集を blocking する。

### Step 5: ワーカー起動文を吐く (コピペ可能)

各 worktree について、人間がそのまま貼って Claude を起動できる文を出す:

```
cd ../wt-<id> で Claude を起動し、docs/sprint/board.json の <id> を読んで、
scope (.bootstrap-lane) の範囲だけで TDD (Red→Green→Refactor) する。
完了したら status を in-review にして feat/<id>-<topic> を push (PR)。
```

直列 spine task は **先に 1 レーンで終わらせてから** 下流 worktree を作る。

## やってよいこと / やってはいけないこと

- やってよい: `Read`/`Grep`/`Glob` での探索、`board.json` 生成、`git worktree add`、`.bootstrap-lane` 書き出し、起動文出力
- やってはいけない: **feature 本体の実装 (Edit/Write)**、scope を重複させた分解、`wip_limit` を超える worktree 量産、spine 未完了での下流並列化

## 関連

- 統合 = `skills/integrate/SKILL.md` (依存順 merge + 統合 verify + claim close)
- 単一タスク = `skills/plan/SKILL.md`
- 並列の安全規律 = `skills/project-bootstrap/SKILL.md`「並列開発フロー」節

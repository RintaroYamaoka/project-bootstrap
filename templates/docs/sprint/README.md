# docs/sprint/

並列開発 (sprint) の **唯一の真実 (board)**。`sprint-plan` skill が生成し、`integrate` skill が消費する。

## board.json

feature を **scope 非重複の task** に分解した状態を持つ。`board.example.json` を参照。

| field | 意味 |
|---|---|
| `sprint` | `<YYYY-MM-DD>-<feature-topic>` |
| `wip_limit` | 同時 in-progress 上限 (= 既定 2-3、これ以上 worktree を作らない) |
| `tasks[].id` | `T0` / `T1` … |
| `tasks[].scope` | この task が所有する file glob 群。**task 間で重複させない** (= 並列の不変条件) |
| `tasks[].branch` | `feat/<id>-<topic>` |
| `tasks[].worktree` | `git worktree add` した path。未 claim なら `null` |
| `tasks[].depends_on` | 先行 task の id 群。**直列 spine** (= 共有 interface/型) をここで表す |
| `tasks[].status` | `todo` → `in-progress` → `in-review` → `done` |
| `tasks[].claimed_by` | 担当ワーカーの識別 (= terminal 名 / session)。未 claim なら `null` |

## scope と .bootstrap-lane の関係

`board.json` は lead / skill が読む rich な真実。各ワーカーの worktree root には派生物として **`.bootstrap-lane`** (1 行 1 glob) を置く。`block-out-of-lane-edit.sh` hook はこの lane file だけを読み (jq 非依存)、宣言外の file 編集を blocking する。

```
# ../wt-T1/.bootstrap-lane  (= board.json の T1.scope を 1 行ずつ展開したもの)
tests/hooks/require-test-companion.test.bash
```

`.bootstrap-lane` は worktree 固有の ephemeral file。**`.gitignore` に追加する** (= commit しない)。

## 並列しすぎない (= scrum の本質は WIP 制限)

並列の収益は凹型カーブで、ソロ開発の変曲点は低い (実質 2-3)。落ちる理由:

- **統合コストが超線形** — scope を disjoint にしても semantic 結合 (共有 interface/型) は残る。Amdahl の法則で直列部分 (planning + integration) が speedup の上限を決める
- **律速は人間のレビュー帯域** — ワーカーが速く PR を出してもレビューは直列
- **分解品質が N で劣化** — 細く刻むほど人工境界が増え協調オーバーヘッドが利得を食う
- **runtime 資源競合** — worktree は file を隔離するが DB / port / API rate limit / lockfile は共有

だから `sprint-plan` は **disjoint scope が支える数より多い lane を作らない**。共有依存は `depends_on` の直列 spine に切り出し、その下流の leaf だけ並列化する。default は逐次、並列は opt-in。

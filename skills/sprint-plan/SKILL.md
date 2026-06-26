---
name: sprint-plan
description: 1 つの feature を複数 Claude で安全に並列開発するための sprint 計画 skill。feature を scope 非重複 (= 触る file glob が重ならない) の task に分解し、共有 interface/型は直列 spine (depends_on) に切り出し、各 task に worktree + .bootstrap-lane を用意して、ワーカー起動文を吐く。並列が本当に得かを WIP 上限と disjoint 性で判定し、得でないなら逐次を勧める。実装はしない (= 計画と worktree 準備まで)。これは default 挙動として自動でロードする: feature の実装に着手し、探索の結果 scope 非重複の leaf が 2 個以上 (≤ wip_limit) に割れると判断したら、「並列で」「チーム/スクラムで」と言われなくても自動で起動する (= 明示呼び出し待ちにしない)。bug fix / refactor / 単一 file / 自明な小変更には起動しない。「並列で」「チーム/スクラムで」「複数ターミナルで」と明示されたときも当然ロードする。統合は integrate skill が担う。
---

# /sprint-plan — feature を安全に並列分解する

複数の Claude (= 別ターミナル / 別 worktree) で 1 feature を並列開発するための計画を立て、worktree と lane を用意する skill。**実装はしない**。`/plan` の単一タスク版に対し、これは並列タスクの分解版。

## 大前提 — 並列は得なときだけ

並列の収益は凹型カーブだが変曲点は**実行形態で違う** (ADR 0006): terminal worker 路は人間のレビュー帯域律速で低め (worker 3-4)、main session が orchestrate する Workflow/subagent 路は帯域を統合関所が自動で守るので engine 上限 (~`min(16, cores-2)`) まで伸ばせる。**まず「並列にすべきか」を判定する**:

- feature が **scope 非重複の leaf** に割れるか? 割れないなら逐次でやる (= 無理に刻むと協調コストが利得を食う)
- 共有 interface / 型 / 契約 があるか? あるなら **それを先に作る直列 spine** が要る。spine 完了前に下流を並列化しない
- 同時 lane 数 ≤ `wip_limit` か? これは **terminal worker lane** の cap (人間 1 人の直列レビュー律速)。超えるなら lane を減らす。**wip_limit の既定は repo root の `.bootstrap-wip` (整数 1 行、opt-in) を `Read` してその値、不在なら worker 3-4**。Workflow/subagent lane は engine 上限律速で wip 非対象 — 帯域は統合関所が守る (ADR 0006)

判定の結果「並列にする価値が薄い」なら、**正直にそう言って逐次 (/plan → TDD) を勧める**。

> **この skill のロード自体が gate で強制される**。`docs/sprint/` を採用した project では `hooks/block-unplanned-feature-build.sh` が、新規 source file を作ろうとした瞬間に「sprint 判定の記録があるか」を見て fail-closed で blocking する。だから feature の実装に入る前に必ずこの判定を通る。並列にすると決めたら board.json を作れば gate は通る。逐次にすると決めたら、その scope・今日の日付・理由を `docs/sprint/.gate` に 1 行記録する (`<scope-glob>  <YYYY-MM-DD>  sequential: <理由>`)。entry は **記録から 3 日で失効**し、glob は **feature-scoped** (exact path か wildcard 前に 2 階層以上の prefix) のみ有効 — `src/**` のような全域 glob は 1 行で gate を恒久 fail-open にした実事故があり無効 (`docs/incidents/2026-06-11-gate-broad-glob-permanent-fail-open`)。失効したら日付を更新して再記録する (= 再記録が再判定)。`.gate` は ephemeral なので各 worktree / repo の `.gitignore` に入れる (commit しない)。

## ワークフロー

### Step 1: 探索 (read-only)

`/plan` と同じく `Read` / `Grep` / `Glob` だけで feature の影響範囲を把握する。**この段階で Edit / Write しない**。

影響範囲が広い (= 多数の file / 命名規約を横断する) なら、この探索を **read-only の Workflow ファンアウト**に下請けさせてよい (ADR 0005 の breadth 顔)。breadth は lane ではないので**隔離 worktree 不要・`wip_limit` 非対象・gate 摩擦ゼロ**。各 subagent は `Read`/`Grep`/`Glob` だけの read-only に保ち、結果 (影響 file・disjoint 候補) を main session が集約して Step 2 の分解に使う。**mutation を伴う lane をここで spawn しない** — 分解前に書き換えると lane 不変条件が壊れる。

### Step 2: scope 非重複の task に分解

- 各 task の **owned file glob** を決める。**task 間で glob が重複してはいけない** (= 並列の不変条件)
- 重複が避けられない file (= 共有 interface / 型 / 設定 / 共通 util) は、それを作る/変える **直列 spine task** に切り出し、依存する task の `depends_on` に入れる
- task は 1 責務・1 PR 単位。細かく刻みすぎない (= 1 lane が 1 画面の責務に収まる粒度)

### Step 3: board.json を書く

`docs/sprint/board.json` を生成する (雛形 `templates/docs/sprint/board.example.json`)。`sprint` / `wip_limit` / 各 task の `id` `title` `scope` `branch` `depends_on` `status: todo` `worktree: null` `claimed_by: null`。

`wip_limit` の値は **`.bootstrap-wip` (在れば) > 既定 worker 3-4** の順で決める (= terminal worker lane の cap。Workflow/subagent lane は engine 上限律速で wip 非対象 — ADR 0006)。sprint 固有の事情でそこから逸脱する (= leaf が完全 disjoint なので 1 つ増やす等) なら、`_wip_note` field に理由を必ず書く — 逸脱は per-sprint の判断であって新しい既定ではない。

### Step 4: 並列可能な leaf だけ worktree を用意

`depends_on` が空 (or 既に done) の task のうち、**`wip_limit` 個まで** worktree を作る:

```
git worktree add ../wt-<id> -b feat/<id>-<topic>
```

各 worktree root の **`.bootstrap/lane`** を置く (= board の `scope` を 1 行 1 glob で展開):

```
mkdir -p ../wt-<id>/.bootstrap
printf '%s\n' "src/auth/**" "tests/auth/**" > ../wt-<id>/.bootstrap/lane
```

`.bootstrap/lane` を `.gitignore` に追加する (= commit しない。`.bootstrap/` 配下の他マーカー (wip 等) は commit するのでフォルダごとではなく lane だけ無視する)。これで `block-out-of-lane-edit.sh` が宣言外編集を blocking する。旧 flat path `.bootstrap-lane` (worktree root 直下) も後方互換で読まれる。

### Step 5: ワーカー起動文を吐く (コピペ可能)

各 worktree について、人間がそのまま貼って Claude を起動できる文を出す:

**形態 ① 別ターミナル worker** (人間が貼る):

```
cd ../wt-<id> で Claude を起動し、docs/sprint/board.json の <id> を読んで、
scope (.bootstrap-lane) の範囲だけで TDD (Red→Green→Refactor) する。
完了したら status を in-review にして feat/<id>-<topic> を push (PR)。
```

**形態 ③ Workflow / subagent lane** (main session が起動、ADR 0004/0005): 同じ board の task を、人間にターミナルを開かせる代わりに main session の Workflow で走らせてよい。その場合 lane は **`isolation:'worktree'` 必須** (mutation lane なので隔離 worktree を強制) で、worktree root の `.bootstrap-lane` がそのまま効き、edit/merge gate は terminal worker と同一に発火する。Workflow runtime の worktree 自動撤去に任せず、**worktree は integrate の merge 後に撤去**する (先に撤去すると統合関所の信号が消える)。lane 数は ① と合算して `wip_limit` を超えない。

どちらの形態でも **task = 1 worktree = 1 owner** は不変。直列 spine task は **先に 1 レーンで終わらせてから** 下流 worktree を作る。

## やってよいこと / やってはいけないこと

- やってよい: `Read`/`Grep`/`Glob` での探索、`board.json` 生成、`git worktree add`、`.bootstrap/lane` 書き出し、起動文出力
- やってはいけない: **feature 本体の実装 (Edit/Write)**、scope を重複させた分解、`wip_limit` を超える worktree 量産、spine 未完了での下流並列化

## 関連

- 統合 = `skills/integrate/SKILL.md` (依存順 merge + 統合 verify + claim close)
- 単一タスク = `skills/plan/SKILL.md`
- 並列の安全規律 = `skills/project-bootstrap/SKILL.md`「並列開発フロー」節

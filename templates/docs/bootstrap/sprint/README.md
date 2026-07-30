# docs/bootstrap/sprint/

並列開発 (sprint) の **唯一の真実 (board)**。`sprint-plan` skill が生成し、`integrate` skill が消費する。

## board.json

feature を **scope 非重複の task** に分解した状態を持つ。`board.example.json` を参照。

| field | 意味 |
|---|---|
| `sprint` | `<YYYY-MM-DD>-<feature-topic>` |
| `wip_limit` | 同時 in-progress 上限 (= terminal worker lane の cap。これ以上 worktree を作らない)。既定は repo root の `.bootstrap/wip` (整数 1 行、opt-in。旧 flat path `.bootstrap-wip` も互換) > worker 3-4。Workflow/subagent lane は engine 上限律速で wip 非対象 (ADR 0006)。sprint 固有に逸脱するなら `_wip_note` に理由を書く |
| `tasks[].id` | `T0` / `T1` … |
| `tasks[].scope` | この task が所有する file glob 群。**task 間で重複させない** (= 並列の不変条件) |
| `tasks[].branch` | `feat/<id>-<topic>` |
| `tasks[].worktree` | `git worktree add` した path。未 claim なら `null` |
| `tasks[].depends_on` | 先行 task の id 群。**直列 spine** (= 共有 interface/型) をここで表す |
| `tasks[].status` | `todo` → `in-progress` → `in-review` → `done` |
| `tasks[].claimed_by` | 担当ワーカーの識別 (= terminal 名 / session)。未 claim なら `null` |

## scope と .bootstrap/lane の関係

`board.json` は lead / skill が読む rich な真実。各ワーカーの worktree root には派生物として **`.bootstrap/lane`** (1 行 1 glob) を置く。`block-out-of-lane-edit.sh` hook はこの lane file だけを読み (jq 非依存)、宣言外の file 編集を blocking する。旧 flat path `.bootstrap-lane` も後方互換で読まれる。

```
# ../wt-T1/.bootstrap/lane  (= board.json の T1.scope を 1 行ずつ展開したもの)
tests/hooks/require-test-companion.test.bash
```

`.bootstrap/lane` は worktree 固有の ephemeral file。**`.bootstrap/` を `.gitignore` に追加する** (= commit しない)。

## .gate — sprint 発火判定の記録

`docs/bootstrap/sprint/` を置いた時点で `block-unplanned-feature-build.sh` hook が有効になり、**新規 source file を作ろうとした瞬間**に「sprint 発火判定を済ませたか」を fail-closed で要求する (= advisory な語彙 reminder の穴を根治)。判定の記録は `docs/bootstrap/sprint/.gate` に置く:

```
# docs/bootstrap/sprint/.gate  (各行: <scope glob>  <YYYY-MM-DD>  <理由>)
src/auth/**   2026-06-11   sequential: 単一画面の責務、disjoint >=2 leaf に割れない
```

- 並列にすると決めたら `board.json` を作れば gate は通る (lane hook が scope を握る)
- 逐次にすると決めたら、その scope・**今日の日付**・理由を上記 1 行で記録する: `printf '%s\n' "src/<area>/<feature>/**  $(date +%F)  sequential: <理由>" >> docs/bootstrap/sprint/.gate`
- entry は時間と空間で bound される (= 1 entry が判定として有効なのは **記録から 3 日以内** かつ **feature-scoped な glob** — exact path か wildcard 前に 2 階層以上の prefix を持つ glob — のときだけ)。`src/**` のような全域 glob・日付なし旧形式・失効 entry は無効。1 行の広域 glob が gate を恒久 fail-open にした実事故から (`docs/bootstrap/incidents/2026-06-11-gate-broad-glob-permanent-fail-open`)
- 失効したら同じ行を日付だけ更新して再記録する (= その再記録が「まだ同一 feature 面か」の再判定)。失効行の削除は不要 (無視されるだけ)
- 記録 scope 外の新規 source を作ると再 block (= 新しい disjoint 面 → 再判定)
- `.gate` は ephemeral。**`.gitignore` に追加する** (= commit しない)

## reviews/ — AI レビューの verdict 記録

merge の前に read-only の adversarial AI レビューを回し (integrate skill Step 2)、結果を `docs/bootstrap/sprint/reviews/<branch の / を _ に置換>.md` に書く。必須行は `verdict: approve` または `verdict: reject`、以下に指摘一覧。

```
# docs/bootstrap/sprint/reviews/feat_T1-auth.md
verdict: approve
- 指摘: token 失効パスのテストが境界値 (exp ちょうど) を見ていない → worker が追加済み
- サンプル監査: 該当 diff の 15% を人間が確認、逸脱なし
```

- `block-unreviewed-merge.sh` hook が、並列 lane の branch (= 活性 sprint の task branch、および **linked worktree に checkout された branch** — board 不要) の merge に対しこの記録を fail-closed で要求する (approve なし → block、reject → より強く block)。worktree の撤去は必ず merge の後 (先に撤去すると関所の信号が消える)
- GitHub の **PR 画面での merge は手元 hook を通らない**ため、PR 経路は `.github/workflows/bootstrap-review-gate.yml` (templates/ci/) が CI で同じ記録を要求する (導入 repo では全 PR が対象)
- **reviews/ は commit する** (= defect 発生時に「どの verdict が通したか」を遡る監査証跡。`.gate` / `.bootstrap/lane` と違い ephemeral ではない)
- sprint 終了時は board と一緒に `archive/` へ移す (integrate skill Step 5)
- 人間が読むのは verdict / 指摘 / diff サンプル 1-2 割 / 統合境界。全 diff 目視はしない — レビューの質の安全網は `scripts/velocity.sh` の defect rate 監視

## 並列しすぎない (= scrum の本質は WIP 制限)

並列の収益は凹型カーブで、変曲点は実行形態で違う (terminal worker は帯域律速で実質 3-4 / Workflow lane は engine 上限律速、ADR 0006)。worker 路で落ちる理由:

- **統合コストが超線形** — scope を disjoint にしても semantic 結合 (共有 interface/型) は残る。Amdahl の法則で直列部分 (planning + integration) が speedup の上限を決める
- **律速は人間のレビュー帯域** — ワーカーが速く PR を出してもレビューは直列
- **分解品質が N で劣化** — 細く刻むほど人工境界が増え協調オーバーヘッドが利得を食う
- **runtime 資源競合** — worktree は file を隔離するが DB / port / API rate limit / lockfile は共有

だから `sprint-plan` は **disjoint scope が支える数より多い lane を作らない**。共有依存は `depends_on` の直列 spine に切り出し、その下流の leaf だけ並列化する。default は逐次、並列は opt-in。

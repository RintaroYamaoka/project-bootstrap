# 2026-09-04 — 後片付けの手順と gate が噛み合わず、branch が 5 ヶ月無音で滞留した

**発見**: propagate の dev フォルダ (34 repo) を掃除しようとして、local に約 1,000 本・
remote に約 1,800 本の branch が溜まっていることが分かった。掃除しようとして初めて、
**bootstrap の後片付け手順が構造的に完走できない**ことが判明した。

**種別**: 手順と gate の相互作用による deadlock / 原則③「配備の可視化」の違反
(効いていない強制が無音のまま成立していた)
**修正**: v0.37.0 (`scripts/branch-cleanup.sh` / `lib/repo-drift.sh` / `block-dangerous-git-ops.sh`)

## 何が起きたか

`integrate` skill Step 5 は後片付けをこう指示していた:

```
git worktree remove ../wt-<id>
git branch -d feat/<id>-<topic>   # merge 済を確認してから
```

ところが GitHub の **squash merge** で PR を閉じる repo では、squash commit は元 branch の
commit を親に持たない。つまり **branch は main の祖先にならず、`git branch -d` は必ず
「未 merge」と判定して失敗する**。残る手の `git branch -D` は、自分の
`block-dangerous-git-ops.sh` が blocking する (未検証の強制削除は作業を消すので、それは正しい)。

**手順の唯一の実行方法が、自分の gate に塞がれていた。**

単体で見ればどちらも正しい。`-d` は安全な削除であり、`-D` の blocking は事故を防ぐ。
**組み合わせたときだけ deadlock になる**ので、どちらか片方だけを見ていても気づけない。

## どれだけ溜まったか (2026-09-04 実測、dogfood repo 群)

| | |
|---|---|
| local branch | 約 1,000 本 |
| remote branch | 約 1,800 本 (marketing-app 923 / appo-followup 648 / propagate-ai 250) |
| うち「PR は MERGED なのに `-d` では消せない」 | **397 本** |
| merge 済なのに残っていた worktree | 6 個 |

remote 側にはもう 1 つ原因があった: **`deleteBranchOnMerge` が全 repo で false**。
merge しても head branch が remote に残り続ける設定で、bootstrap はこの設定に
**どこでも一度も触れていなかった**。掃除しても蛇口が開いたままなので必ず再発する。

## なぜ「安全側だから良い」で済まないか

手順が完走できないとき、実行者に残る選択肢は 2 つしかない:

1. 後片付けを飛ばす (= 実際に起きたこと。5 ヶ月ぶん滞留した)
2. `/permissions` で hook を deny にして `-D` を手で叩く (= gate を殺す)

これは **2026-08-08 (`heredoc-body-read-as-command`) と同じ構造の再発**である。あのとき
書いた教訓は「false positive は安全側ではなく、規律を回避する動機という別の危険を作る」
だった。今回は false positive ではなく **手順の実行不能** だが、行き着く先は同じ
「gate が自分の bypass を作る」。

同じ incident で書いた教訓 3「**修正は単一の入口で** — 誤検知が 2 つの検出経路
(walker / raw regex) に在ったので walker だけ直すと片肺」も、**半分しか適用されていなかった**。
`parse_command` の heredoc 除去は両経路に効いたが、`block-dangerous-git-ops.sh` 自身は
raw regex のまま残った。その結果、今回の掃除中に

```
pkill -9 -f "git push origin --delete"     ← git を一切起動しないのに block された
```

を踏んだ。「git push という文字列」と「後ろのどこかにある `-f`」を別々の場所から拾える
形だったため。**2 回目なので、regex 経路そのものを畳んだ** (ADR 0019 の walker に合流)。

## 教訓 (memory へ昇格する分)

1. **手順と gate は組み合わせでテストする**。単体で正しい手順と単体で正しい gate が、
   組み合わせたときだけ実行不能になる。skill が書いたコマンドを gate に通してみる、
   という検査がどこにも無かった。
2. **ephemeral state の lifecycle は「所有者を書く」だけでは閉じない。閉じたことを測る
   信号が要る**。worktree 残骸は `repo-drift.sh` が測っていたので可視化されていた。
   branch 残骸は測っていなかったので 5 ヶ月無音だった。**同じ lifecycle でも、
   計測がある側だけが実際に閉じられていた** — 原則③の最も直接的な実例。
3. **蛇口を見ない規律は、下流でいくら掃除しても再発する**。`deleteBranchOnMerge` は
   「repo 設定であって bootstrap の守備範囲外」と暗黙に扱われていたが、実際には
   残骸が出続ける原因そのものだった。掃除の手順を書くなら、原因側の設定も同じ場所に書く。
4. **「設定を入れろ」で終わる指示は、権限が無い利用者には実行不能な手順**。
   `deleteBranchOnMerge` の変更には ADMIN が要る (WRITE では API が 404 を返す)。
   実測では 30 repo 中 **12 repo が WRITE 止まり**で、利用者自身では閉じられなかった。
   手順には「権限が無ければ org 管理者に依頼する」まで書く。
5. **危険な操作を禁止するなら、その操作が正当に必要な用途に正規の経路を用意する**。
   `-D` の blocking は正しいが、代わりの道が無かったので deadlock になった。
   `scripts/branch-cleanup.sh` は「`-D` を許す」のではなく「**削除の根拠を先に取る**」
   ことで、gate が本当に守りたいもの (検証なしの削除) を守ったまま道を開けている。

## 修正で入れたもの

- `scripts/branch-cleanup.sh` — 根拠 (main の祖先 / PR が MERGED) を 1 本ずつ取ってから
  消す。根拠が取れない branch は残す。`gh` が使えなければ祖先判定だけに縮退する。
- `lib/repo-drift.sh` に branch 残骸の軸 — local 10 本 / remote 150 本を超えたら
  SessionStart で可視化し、remote 側は原因である `deleteBranchOnMerge` を名指しする。
- `block-dangerous-git-ops.sh` を walker に合流 — raw regex を畳んで過検知を止めた。
- `integrate` skill Step 5 を書き換え — なぜ `-d` が失敗するか、蛇口をどう閉めるか、
  権限が無いときどうするかまで手順に含めた。

## 残っている穴

- raw regex で git を見ている gate はまだ 2 本ある
  (`block-over-wip-parallel.sh` / `block-commit-if-tests-fail.sh`)。同じ過検知を持ちうる。
- 「skill が書いたコマンドが gate を通るか」を検査する仕組みは無いままで、教訓 1 は
  まだ規律 (人が気をつける) の側にある。次に同じ形の deadlock が出たら、そこを構造にする。

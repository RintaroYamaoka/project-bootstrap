# 2026-08-07-commission-upstream-integration: 上流工程 (発注→検収) を bootstrap に統合した

セッション期間: `2026-08-07`
本 doc の目的: **次の Claude が cold restore できる状態**を残す。会話メモリは引き継がれないので、
判断の経緯は ADR 0022-0024 に、運用状態はここに置く。

---

## 1 行で言うと

上流工程を担う独立プラグイン 2 つ (`upstream-process` / `kanban-flow`) が定着しなかった原因を
「強制層に届かないので advisory に戻る」と特定し、**bootstrap の 1 サブシステム `commission` として
統合**した。skill 4 / hook 3 / lib 1 / script 1 / ADR 3 を追加、テスト 53 スイート全緑、
hook 21 → 24、version 0.32.0 → 0.33.0。

同日の後半で**自己監査を 1 周かけ、見つかった穴 5 つを塞いでから**リリースした (詳細は下の
「塞いだ穴」)。特に③ (配備の可視化) の自己違反 2 件 — doctor が commission を知らない /
hook レジストリが実体とずれる — は、このプラグインが他所で否定している失敗モードだった。

## いま何が在るか

```
skills/{charter,order,pre-review,accept}/SKILL.md   上流の 4 工程
hooks/lib/wo.sh                                     作業指示書パーサ (単一権威)
hooks/block-commit-if-wo-incomplete.sh              発注 (status: ordered の commit) の完全性関所
hooks/block-impl-without-wo.sh                      新規 source 面に発注済み WO を要求 (編集時)
hooks/block-commit-if-impl-uncovered.sh             同上の commit 側の網 (Bash 経由の書き込み)
scripts/wo-metrics.sh                               節別エスカレーション集計 (ADR 0024)
templates/docs/bootstrap/commission/                README + charter.md + wo/TEMPLATE.md
docs/decisions/002{2,3,4}-*.md                      不可逆判断 3 件
tests/hooks/{wo,block-impl-without-wo,block-commit-if-wo-incomplete,block-commit-if-impl-uncovered}.test.bash
```

中心概念は 1 つだけ: **作業指示書 (WO) = AI が人間不在で走り切るための引き渡し契約**。
12 節固定で、`status: ordered` にして commit する行為が「発注」= 関所の信号。

## 塞いだ穴 (同日の自己監査、リリース前)

| # | 穴 | 直し方 |
|---|---|---|
| 1 | `scripts/doctor.sh` が commission を知らない = 配備漏れが無音 (③ の自己違反) | 採用検出 + `REQ` に 3 gate 登録 + `charter.md` 不在を partial に |
| 2 | `hooks/README.md` の hook 一覧・発火順が実体とずれる (「全 20 hook」のまま) | 3 本を追記し 24 本に数え直し。`MAINTENANCE.md` に「hook を足したら REQ と発火順も直す」を同期対として明文化 |
| 3 | `deferred:U99` — 台帳に無い ID への先送りが決着として通る | `charter_unknown_ids` を足し、4 節の参照先と `deferred:` 先の**実在**を検査 |
| 4 | 発注 gate が file 名は index・中身は worktree から読む = 部分 stage で無音 fail-open | `lib/commit-files.sh` に `commit_file_content` を新設し index の版を読む |
| 5 | 被覆の判定が Edit 経路だけ = redirect / codemod / scaffolder が素通り | commit 側の関所 `block-commit-if-impl-uncovered.sh` を新設 (ADR 0017 と同型の二層化) |

5 は当初「lane gate が代替する」と見ていたが誤り。`.bootstrap/lane` は WO から生成されるので、
**1 枚も発注していない状態では lane marker 自体が無く lane 関所は fail-open** する — つまり
commission が止めたい当の状態だけが素通りしていた。

## 残課題

| 項目 | 状況 | 対応案 |
|---|---|---|
| 実運用が 0 件 | 設計と単体テストのみ。前 2 回も設計時点では筋が通っていた | どれか 1 repo で WO を 1 枚通す。**実物を 1 回通すまで手順書を信じない** (kanban-flow が introspection だけで書いて事故った前例) |
| CI twin なし | ローカル hook は GitHub の Merge ボタンを止められない | ADR 0012 の二層化に載せるか、実運用後に判断 (ADR 0023 に記載) |
| 旧 2 repo は表記変更のみ未 commit | `kanban-flow` / `upstream-process` の README 冒頭と plugin.json、`claude-plugins` の marketplace.json を編集済み・未 commit | 各 repo で個別に commit する (別 git repo) |
| `project-manager/` が空のまま | 当初この新プラグイン用に切られたディレクトリ。統合方針にしたので不要 | 削除するか、設計メモ置き場として残すかは user 判断 |

## バックグラウンドプロセス

無し。

## 触ったファイル

### 永続化したい

- `project-bootstrap/` — commit 済み (v0.33.0)。上記「いま何が在るか」の全ファイル + `README.md` / `CHANGELOG.md` /
  `MAINTENANCE.md` / `.claude-plugin/plugin.json` / `hooks/hooks.json` /
  `skills/project-bootstrap/SKILL.md` (上流セクション追加) / `skills/plan/SKILL.md` (WO 例外) /
  `hooks/lib/resolve-docs.sh` (コメント更新) / `templates/docs/README.md` /
  `docs/bootstrap/sprint/.gate` (逐次判定 1 行)
- `kanban-flow/` `upstream-process/` — README 冒頭に ARCHIVED バナー、plugin.json に退役理由
- `claude-plugins/.claude-plugin/marketplace.json` — 2 件を ARCHIVED 表記、bootstrap を 0.33.0 に

### untracked / ephemeral

無し。

## 重要な memory / docs references

読む順:

1. `docs/decisions/0022-upstream-merged-into-bootstrap.md` — **なぜ別プラグインでなく統合したか**。
   前身 2 実装の敗因の一次分析。同じ設計を再提案しないための証拠
2. `docs/decisions/0023-autonomy-preconditions-as-ordering-gate.md` — 12 節と関所の設計。
   なぜ commit で・なぜ draft を止めないか
3. `docs/decisions/0024-upstream-quality-measured-by-downstream-telemetry.md` — 計測の設計と限界
4. `templates/docs/bootstrap/commission/wo/TEMPLATE.md` — WO の様式 (**形式の権威**)
5. `hooks/lib/wo.sh` — 判定の実体 (**判定の権威**)。4 と 5 の節番号は同期必須
   (`MAINTENANCE.md` の「同期が要る対」表)

## 検証手順

```bash
cd project-bootstrap && bash tests/hooks/run.sh
```

期待: `SUITES: 53 run, 0 failed`

commission 層だけを見るなら:

```bash
bash tests/hooks/wo.test.bash                             # 38 assertions
bash tests/hooks/block-commit-if-wo-incomplete.test.bash  # 29 assertions
bash tests/hooks/block-impl-without-wo.test.bash          # 12 assertions
bash tests/hooks/block-commit-if-impl-uncovered.test.bash # 15 assertions
```

## 次セッションへの起動文 (= コピペ用)

```
project-bootstrap/docs/bootstrap/handoffs/2026-08-07-commission-upstream-integration.md と
docs/decisions/0022-0024 を読んで状況把握してから続けて。v0.33.0 としてリリース済み。
commission サブシステムは実運用 0 件なので、設計を追加する前に 1 枚 WO を通すことを優先する。
```

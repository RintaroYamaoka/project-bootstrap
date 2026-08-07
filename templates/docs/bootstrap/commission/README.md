# docs/bootstrap/commission/ — 上流工程 (発注 → 検収)

**このディレクトリが在ることが、commission サブシステムの採用宣言**である
(`.bootstrap/<name>` マーカー・`docs/bootstrap/sprint/` と同じ opt-in 規約)。
無ければ関連 hook は一切発火しない。

## 何をする層か

AI が実装・試験・修正を自律的に繰り返す前に、**目的・作業範囲・変更禁止範囲・優先順位・
例外時の判断方法・検証方法・完了条件・停止条件**を確定させ、機械検証を通してから引き渡す。
実装が終わったら、意図と成果物を突合して受け入れる (検収)。

前提となる観測は 1 つ: **AI との質疑応答を減らすほど、事前に与える情報を増やさなければならない。**
自律性を上げると、AI は仕様の穴に当たっても質問せず、もっともらしい解釈を選ぶか停止する。

## 中身

```
docs/bootstrap/commission/
  charter.md          不可逆な判断だけの 1 ファイル (目的/不変のコア/制約/決定ログ/未決台帳)
  wo/<id>-<slug>.md   作業指示書 (WO)。1 作業 = 1 ファイル。検収したら削除してよい (git 履歴が正本)
  metrics.tsv         検収時に 1 行追記される実績 (scripts/wo-metrics.sh が読む)
```

`docs/decisions/` (ADR) はここに含めない — ADR は一般的な工学慣行であり、
このサブシステム固有の成果物ではないため (`resolve-docs.sh` の設計と同じ理由)。

## 関所

| 行為 | 何が要求されるか | 強制 |
|---|---|---|
| WO を `status: ordered` にして commit する (= 発注) | 12 節すべてが記入済み / DoD 行数 = 検証方法 行数 / 事前レビューが全件 closed か deferred / OPEN な未決を参照していない | `block-commit-if-wo-incomplete.sh` |
| 新規 source file を作る (= 実装開始) | その path をカバーする `ordered` な WO が在ること | `block-impl-without-wo.sh` |
| 新規 source file が載った commit をする | 同上 (Edit ツールを通らない書き込み = redirect / codemod / scaffolder の取りこぼしの網) | `block-commit-if-impl-uncovered.sh` |
| lane 外の file を編集する | WO 2 節から生成された `.bootstrap/lane` の範囲内であること | 既存 `block-out-of-lane-edit.sh` |
| lane branch を merge する | verification plan の OPEN 行ゼロ (WO 8/9 節から生成される) | 既存 `block-merge-if-verification-unclosed.sh` |

**下 2 行が要点**: 上流で決めたことは、新しい強制機構ではなく **bootstrap の既存 gate に翻訳されて**
強制される。`order` skill が WO から `.bootstrap/lane` と
`docs/bootstrap/verification/<branch>.md` を生成するので、上流の決定が実装中ずっと効き続ける。

## skill

| skill | いつ |
|---|---|
| `charter` | プロジェクト立ち上げ時・方針が変わったとき。不可逆だけ固める |
| `order` | 作業を AI に渡す前。WO をドラフトし、完全性ゲートを通して発注する |
| `pre-review` | 発注の直前。仮想下流リーダーとして仕様を壊しにかかる |
| `accept` | 実装が返ってきたとき。DoD と差分を突合して受け入れる/差し戻す |

## 導入

```bash
cp -r <plugin>/templates/docs/bootstrap/commission docs/bootstrap/
# charter.md を埋める (charter skill が壁打ちで手伝う)
# wo/TEMPLATE.md は残しておく (order skill が複製元にする)
```

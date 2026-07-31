# 0021 — 引退した名前の混入を「commit が足した行」で止め、蓄積分は doctor で可視化する

- **Status**: Accepted
- **Date**: 2026-07-31
- **Deciders**: Rintaro Yamaoka
- **References**: [0018](./0018-lint-gate-signal-is-the-commit-not-the-tree.md) (信号はツリーでなくこの commit) / [0017](./0017-lane-enforcement-at-commit-chokepoint.md) (書き込み方式の列挙をやめ commit 関所へ) / [0011](./0011-cross-repo-contract-drift-gate.md) (repo をまたぐ形のズレ) / [0012](./0012-server-side-enforcement-durable-layer.md) (server 側の恒久層) / [0015](./0015-consolidate-root-markers-into-bootstrap-dir.md) (marker の所在) / kanban-flow plugin `skills/audit` (実例のない検査は正規化しない) / memory `feedback_gate_signal_and_failmode`

---

## Context (背景)

このプラグインが持つ「ズレを止める」機構は、これまで 3 つとも **file 単位・repo 単位**だった: 依存方向 (`.bootstrap/arch`)、repo をまたぐ契約 (ADR 0011)、整形と命名規約 (lint)。**repo の中の「語」のズレは無防備**で、用語集に相当する概念すら持っていなかった。

そこに実例がある。ai-reception で `Intent.typeNo` (number) → `typeId` (string) の改名 (#88) がマージされた **1 時間 12 分後**、別の PR (#99・テスト UI) が改名を知らずに `i.typeNo` を参照したまま実装されてマージされた。`Intent` に `typeNo` は無いので式は常に `undefined`、`undefined === null` は false、クライアント側の生 JS なので型チェックも効かずエラーも出ない。テスト UI が「#undefined」を表示し続け、3 日以上・複数 commit を経ても誰も気づかなかった。

この失敗の核心は「注意不足」ではなく**情報の非対称**である:

> 改名を行う PR は改名後の全 file を知り得るが、**改名の "後に" 書く人は、grep すべき語が在ることを知らない**。だから改名者の自己申告 (「関連箇所は直しました」) では原理的に漏れる。

同じ形の失敗は AI でより頻繁に起きる。旧称は**かつて実在した**ので、モデルの記憶にも会話の文脈にも残っており、捏造 (癖②) と違って「もっともらしく正しい」。

この機構自体は kanban-flow プラグインが `deprecated-term-grep` として持っているが、あちらは用語集 (`glossary.md` の旧称・非推奨表) を claim 源とする**計画側の道具**で、用語集を持たない repo では効かない。bootstrap は用語集を持たない設計 (「docs に書かないもの」を厳しく決めた結果) なので、**そのまま輸入はできない**。

## Decision (決定)

**引退した名前を repo-local な行指向 marker `.bootstrap/retired` に登記し、`git commit` が新しく足した行にその語が混入していたら fail-closed で blocking する。既に蓄積している残存は SessionStart の doctor が件数で可視化する (block しない)。**

判定エンジンは単一権威 `hooks/lib/retired-terms.sh`。消費者は 3 つ — commit 関所 `hooks/block-commit-if-retired-term.sh`、CI net `scripts/retired-check.sh` (+ `templates/ci/bootstrap-retired.yml`)、doctor の残存 sweep。

### 登記フォーマット (`.bootstrap/retired`、opt-in = 存在が on スイッチ)

```
<引退した名前> | <置換先> | <射程 glob> | <note>
```

必須は 1 列目だけ。`#` コメントと空行は無視、各欄は trim。雛形 = `templates/.bootstrap/retired.example`。**日付列は置かない** (git 履歴が持つ事実を複製しない)。**用語集は作らない** — 登記するのは gate に必要な行だけで、用語の正本を持ちたい project は kanban-flow 側の `glossary.md` に置き、そこからこの marker を生成すればよい。bootstrap は kanban-flow の存在を知らないままでいられる。

### 4 つの設計判断とその理由

**① 信号は「この commit が新しく足した行」であって、ツリーでもファイルでもない。**
ツリー全体を検査すると、marker を置いた瞬間から残存を持つ file に触る全 commit が止まる。そのとき行為者に残る逃げ道は (a) 自分の lane を出て一括改名する (= 越境編集、別 gate に当たる) か (b) marker の行を消す (= gate を無効化) の 2 つしかない。**gate が自分の bypass を作る**。commit が答えるべきなのは自分が新しく持ち込んだ分だけである。ADR 0018 が lint について下した判断 (「信号はツリーでなくこの commit が運ぶ file」) を、名前に適用した同型の決定。

**② edit 時 gate は作らない (arch の 2 層構成を意図的に真似ない)。**
「その行は追加されたのか」は PreToolUse では計算できない。`new_string` に現れた旧称は、無関係な書き換えに巻き込まれた既存行かもしれない。さらに**改名操作そのものは旧称を `old_string` 側に置く**ので、素朴な edit 時検査は「やらせたい改名」を止める。commit 関所にすれば sed / formatter / script 経由の書き込みも同時に捕まる (ADR 0017 が lane について通った道と同じ)。

**③ 照合はプラグインが所有し、consumer に正規表現を書かせない。**
marker が各行に固有の正規表現を持てる設計にすると、消費先 repo が未レビューのマッチャを書くことになり、`merge-targets.sh` / `protected-branch.sh` / `action-gate.sh` がそれぞれ潰してきた「文字列を行為の proxy にする」バグ類型を再輸入する。受け付けるのはリテラルのみ。英数字と `_` だけの語は単語境界で照合し (`typeNo` は `i.typeNo` に当たり `typeNotation` には当たらない)、それ以外を含む語は素の部分一致に落ちる。

**⑤ 逃げ道は「行 1 本ぶんの明示的な opt-out」にする (`bootstrap-retired-ok`)。**
本 PR の dogfood で判明した: コード内のコメントと test fixture は検査対象なので、**旧称を説明するために書く正当なコード**が止まる (本 repo で `typeNo` を登記したら、この gate 自身の解説コメントと fixture がヒットした)。これを放置すると、行為者に残る手段は「marker の行を消す」か「scope-glob でパスごと除外する」— **どちらも問題より広く、しかも設定ファイルの中で起きるので誰も気づかない**。決定① が塞いだはずの「gate が自分の bypass を作る」形が別の入口から戻ってくる。

対の逃げ道として、その行に `bootstrap-retired-ok` を書くと**その 1 行だけ**除外する (eslint-disable-line と同じ形)。

- **なぜ「コメントを構文で除外」しないか**: 最初の `//` で切ると文字列中の `"http://host/typeNo"` を無音で飲み込む。**無音の検出漏れはこのプラグイン最悪の fail-mode**。コメント構文は言語ごとに違うので、ここに parser を置くと両方向に間違える
- **なぜ scope-glob で足りないか**: glob は**パス全体**を外す。`hooks/` の解説コメント 1 本を通すために `hooks/**` の gate を丸ごと落とすことになる
- **本物の違反を pragma で黙らせられる件**: できる。だが marker の行を消せば元々できた。pragma は**diff に残ってレビューで見える**ので、設定ファイルへの不可視な編集より厳密に良い。取引は「見える狭い逃げ道」を「見えない全面的な逃げ道」の代わりに置くこと
- **block メッセージでの提示順**: 「名前を直す」が第一、pragma は最後で、しかも「その行が旧称 *について* 書いている場合だけ」と条件つき (助言が隠蔽を促さない — memory `feedback_gate_signal_and_failmode`)
- **doctor の残存 sweep も同じ規則に従う**。`git grep -l` (file 名だけ) では pragma を読めないので、行を取って opt-out を適用してから file に畳む。gate が通す行を doctor が数えると根拠なき nag になり、**恒久的な nag を黙らせる最短手は marker 削除**になる

**④ 「重複」の検出は作らない。**
「同じ概念に 2 つ目の定義を作る」ほうは、①の分解でいう**既約な判断**の側に落ちる。加えて、この検査が実在の問題を見つけた実例が**まだ 1 件も無い**。kanban-flow の audit skill が自分に課している規則 —「実在の問題を 1 件以上見つけた記録が無いモジュールは正規化しない。さもないと検査モジュール自体が docs と同じ理由で増殖する」— をここでも適用する。代わりに AI の癖⑩ と `templates/CLAUDE.md` のセルフチェック 2 行に留める。**昇格条件**: 重複が実際に事故を起こした記録が 1 件出たら、そのとき機械化を検討する。

### fail-mode

memory `feedback_gate_signal_and_failmode` に準拠:

| 状況 | 挙動 |
|---|---|
| command が parse 不能 (解析不能) | **fail-closed** (block gate を payload で黙らせない。lint / test 関所と同一) |
| `git commit` でない / git repo 外 / marker 不在 (根拠不在) | fail-open で無音素通し |
| marker は在るが有効行 0 | gate は素通し + **doctor が `partial` で「宣言だけで no-op」と言う** (arch / protected と同型) |
| 残存が既にある | **advisory のみ。status は落とさない** — 恒久的な nag は marker 削除の動機になる |

### 二層化 (ADR 0012)

hook は Claude が Bash で叩く commit にしか効かない。人が端末で直接 commit する経路と GitHub UI での PR merge は通らない。**しかも改名の取り残しは「hook を通らない人」ほど踏みやすい**ので、CI net は飾りではない。workflow は三点差分 (`origin/<base>...HEAD`) を使う — 二点だと base 側で行われた改名を「このブランチが旧称を再導入した」と誤読し、他人の作業で PR が赤くなる (`tests/hooks/retired-check-cli.test.bash` がこの誤読を pin している)。

## Consequences (帰結)

### 得られるもの

- 改名の取り残しが、改名者の記憶ではなく機構によって止まる。しかも**改名を知らない人ほど強く守られる** (その人の commit が関所を通るから)
- 止め方が構成的: block メッセージが置換先の名前を出す。「隠せ」と言わない
- 用語集を持たない repo でも効く。kanban-flow との依存関係を作らない
- 蓄積した残存が「見えないまま放置」にならない (gate = 新規 / doctor = 蓄積、の分業)

### 正直な限界 (隠さない)

1. **登記されていない改名は検出できない。これが最大の穴で、原理的に閉じられない。** 「改名したら 1 行足す」は既約な人の行為であり、gate は登記済みの語しか知らない。doctor の残存 sweep も同じ穴を共有する (登記された語しか sweep しない)。緩和は CLAUDE.md のセルフチェックと癖⑩ だけで、これは強制ではない
2. **多バイトの語は単語境界で anchor できない**ので素の部分一致に落ちる (登記した `波` は `波数` にも当たる)。精度が要る語は識別子の形で登記すること。doctor の sweep は `git grep -w` を使うので、多バイト語は逆に**数え漏らす**側に倒れる (advisory なので許容。block なら許容しない)
3. **文字列連結や動的アクセス** (`obj["type" + "No"]`) は捕まらない
4. **`*.md` / `docs/**` を除外している**ので、文書中のコード例が古いまま残るのは検出しない。除外しないと用語集の非推奨表そのものを gate が止めるので、この交換は意図的
4b. **コード内のコメントと test fixture は検査される** (除外は「文書ファイル」であって「文書的な記述」ではない)。これは限界ではなく**意図**だが、対になる逃げ道が必要だった — 決定⑤ を参照
5. **doctor の sweep は 1 session あたり 30 語で打ち切る** (SessionStart は同期呼び出しなので)。打ち切った語数は出力に明示する — 黙って切ると「監査したという記録だけが残る」失敗になる
6. **CI net は consumer 側が配備して初めて効く** (merge ≠ deployed)。配備漏れは doctor の vendoring チェックでしか見えない

### 追加された面

- `hooks/lib/retired-terms.sh` (engine) / `hooks/block-commit-if-retired-term.sh` (gate) / `scripts/retired-check.sh` (CLI + CI net) / `templates/ci/bootstrap-retired.yml` / `templates/.bootstrap/retired.example`
- `hooks/lib/commit-files.sh` に `commit_stages_all` を切り出した (`-a` 判定を lane / lint gate と engine で共有するため。2 つ目のコピーを作らない)
- `scripts/doctor.sh`: 採用検出 + 空 marker の partial + vendoring 必須 hook + 残存 advisory

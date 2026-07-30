# <YYYY-MM-DD>-<topic>: <1 行で目的>

セッション期間: `<YYYY-MM-DD HH:MM>` 〜 `<YYYY-MM-DD HH:MM>`
本 doc の目的: **次の Claude (= 別ターミナル / 翌日の自分 / 別 session) が cold restore できる状態**を残す。

---

## 1 行で言うと

<最終結果を 1 文で。数値があれば数値で。>

例:
> X feature を Y モジュールに統合、test 全 pass、production deploy READY 確認済。残課題 1 件 (Z の edge case 対応)。

## 残課題

| 項目 | 状況 | 対応案 |
|---|---|---|
| <識別子 / file path> | <現状> | <次にやること> |

未解決 = 上の表。**解決済みは書かない** (= 重複の元)。

## バックグラウンドプロセス

セッション中に起動して **まだ走っている / 走っていた** プロセス:

- `<command>` — log: `<path/to/log>` — 状態: <running / completed / killed>

走っていなければこの節は省略。

## 触ったファイル

### 永続化したい

このセッションで Edit/Write した、commit すべき file:

- `<path/to/file>` — <要点 1 行>

### untracked / ephemeral

`scripts/_*` 等の prefix `_` 付き ephemeral debug file。**別 session が消して良い**:

- `<path/to/_file>` — <用途 1 行>

無ければ「無し」と書く。

## 重要な memory / docs references

次セッションが必ず読むべき memory / docs を **読む順** で:

1. `<file path>` — <一行で何が書かれているか>
2. `<file path>` — <一行で何が書かれているか>

## 検証手順

「直ったか / done か」を再確認する具体的なコマンドや手順:

```bash
<command>
```

期待: `<想定出力>`

## 次セッションへの起動文 (= コピペ用)

```
docs/bootstrap/handoffs/<YYYY-MM-DD>-<topic>.md を読んで状況把握してから、
残課題の <識別子> から作業を続けて。
```

---

## このテンプレートの使い方

- **1 セッション = 1 handoff**。複数 session 分を 1 file に混ぜない
- **長さは 1 画面以内が理想**。詳細は incidents / decisions / コード本体にリンクで逃がす
- **3 hop 構造を禁止** (= handoff → handoff → incident の連鎖)。関連 doc は本文末尾の references にだけ書く
- **賞味期限 1-2 週間**。古い handoff は削除して良い (= ADR / incident と違って永続ではない)

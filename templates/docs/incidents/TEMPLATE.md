# <YYYY-MM-DD>-<topic>: <1 行で何が起きたか>

<どんな状況で何が起きたかを 2-3 文で。AI 駆動なら AI のどのターンで踏んだかも含める。>

## 関係する file / 識別子

- `<path/to/file>` (= 関与した実装 / test / 設定)
- `<identifier>` (= 影響を受けた entity。business 固有名は placeholder で)

---

## 1. ミスの一覧

時系列または重要度順で書く。AI が踏んだ場合は AI のどの判断ミスかを literal に:

### 1.1 <ミス名>

- **何をした**: <具体的な操作 / 発言 / commit>
- **何が問題だった**: <因果 1 文>
- **user 指摘 / 観測された結果**: <user 発言の literal 引用 or 計測値>

### 1.2 <次のミス>
...

## 2. 真因

ミス群を貫く **構造的な原因** を 1-2 文で。表面の操作ミスではなく、判断の枠組み / 確認ルートの欠落を書く:

> <真因の 1-2 文>

例:
> 既存リソースの actual capability を、コード上の表記 (= コメント / 変数名 / 定数) で代用して verify したつもりになった。

## 3. 構造的再発防止

advisory ではなく、**default 挙動 / hook / skill / memory** で強制する経路を書く:

- [ ] **memory `feedback_<topic>.md` に保存**: <ルール 1 文 + 射程 + Why>
- [ ] **`skills/<skill>/SKILL.md` に節追加**: <どの節に何を加えるか>
- [ ] **hook で deterministic 強制 (可能なら)**: <どんな pattern を block するか>
- [ ] **チェックリストに追加**: <`SKILL.md` の「迷ったとき」N 行目に追加>

memory への昇格は **本 incident の必須責務**。incident を書いただけで memory に転記しないと再発する (= incident は人間 / AI が読まないと効かないが memory は session 開始時に load される)。

## 4. 関連 memory / docs

- [`feedback_<topic>.md`](../../../<memory path>) — <一行根拠>
- [`reference_<topic>.md`](../../../<memory path>) — <一行根拠>
- 関連 incident: [`<date>-<topic>`](../<dir>/README.md) — <類似事故なら>
- 関連 decision: [`NNNN-<title>.md`](../../decisions/NNNN-<title>.md) — <設計判断と接続するなら>

---

## このテンプレートの使い方

- **AI 駆動で発火**: fix / revert / hotfix commit / user 叱責 / 「もう一度やり直し」言及 の後。`skills/incident/SKILL.md` ロードで default 挙動化
- **business 固有名は placeholder で**: 顧客名 / cid / 客先案件名は `<customer-A>` `<account-X>` のように書く
- **長さは 1 画面以内が理想**。詳細な調査ログは別 file (= `01-evidence.md` / `02-audit.md` 等) に分けるか incident dir 内 sub-file で
- **構造的再発防止節を memory 転記まで責務に含める**。docs だけで終わらせると AI には届かない

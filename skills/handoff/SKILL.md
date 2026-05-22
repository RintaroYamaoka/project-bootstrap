---
name: handoff
description: session の cold restore に必要な状態を docs/handoffs/ に書き残すための skill。session 終了前 / `/clear` 前 / 別 Claude (= 別ターミナル / 翌日の自分 / 並走 session) に context を渡す前にロードする。`/handoff <topic>` で明示呼び出しもできるが、上記タイミングで AI 自身が default として呼ぶことを期待する。handoff は **1 session = 1 file**、賞味期限 1-2 週間で破棄可。永続記録 (= ADR / incident) ではない。
---

# /handoff — session を cold restore 可能にする

このスキルは、session を **別 Claude が cold で復元できる** 形で `docs/handoffs/` に書き残すためのもの。

## いつ呼ばれるか

- ユーザーが `/handoff <topic>` と打ったとき
- 以下の **AI 自身の判断** で自発的に呼ぶ:
  - session が長くなり、ユーザーが `/clear` 等で context をリセットしそうな兆候
  - 並走する別 Claude / 別ターミナルに context を渡す必要がある
  - 翌日 / 数時間後の再開を user が示唆した
  - 重要な session の終了 (= PR 出した / deploy した / 顧客対応一区切り)

**advisory 経由ではなく default 挙動として書く**。書かないと cold restore コストが session ごとに膨張する。

## ワークフロー

### Step 1: ファイル名を決める

```
docs/handoffs/<YYYY-MM-DD>-<topic>.md
```

- `<YYYY-MM-DD>` は当日の日付
- `<topic>` は kebab-case の 2-5 単語 (= `session-resume-noindex` / `wix-gsc-relink-remediation` 等の literal でなく汎用語で)
- 既存 file と衝突するなら `-2` / `-resume` 等の suffix

### Step 2: 7 節構造で書く

雛形 `templates/docs/handoffs/TEMPLATE.md` を踏襲する:

1. **1 行で言うと** — 最終結果を 1 文 + 数値
2. **残課題** — 表 (識別子 / 状況 / 対応案)。**解決済みは書かない**
3. **バックグラウンドプロセス** — 走っているもの / log file path / 状態
4. **触ったファイル** — `永続化したい` / `untracked / ephemeral` の 2 分類
5. **重要な memory / docs references** — 次セッションが必ず読むべき file を読む順で
6. **検証手順** — 「直ったか」を再確認するコマンド + 期待出力
7. **次セッションへの起動文** — コピペで貼って起動できる文

### Step 3: 長さを 1 画面以内に保つ

詳細は別 doc にリンクで逃がす:

- 事故 → `docs/incidents/`
- 不可逆判断 → `docs/decisions/`
- 既存仕様 → コード本体 / `CLAUDE.md`
- 規律 → `skills/<name>/SKILL.md`

handoff に書くのは **「次の Claude が動き出すための最小限」** だけ。

### Step 4: 3 hop 構造を避ける

`handoff → handoff → incident` の連鎖を作らない。関連 doc は **本文末尾の references にだけ** 書き、本文中で参照リンクをチェーンしない。

### Step 5: 起動文を literal にする

「次セッションへの起動文」は **コピペでそのまま貼れる** 形で書く:

```
docs/handoffs/<YYYY-MM-DD>-<topic>.md を読んで状況把握してから、
残課題の <識別子> から作業を続けて。
```

これにより並走 Claude が cold start から 1 ターンで restore できる。

## 書かないもの

- **既に解決済みの項目** (= 残課題以外は書かない、handoff は次の一手のため)
- **普遍ルール / 規律** (= `SKILL.md` の領分)
- **顧客名 / cid / 業務固有識別子** (= `<customer-A>` 等の placeholder で)
- **長い設計議論** (= `docs/decisions/` で ADR にする)

## 賞味期限

handoff は **1-2 週間で破棄可**。古い handoff を残しても次セッションが読まない (= 重複化の元)。

永続記録は:
- 不可逆判断 → `docs/decisions/` (ADR)
- 事故と再発防止 → `docs/incidents/`
- AI に再注入する教訓 → memory `feedback_*.md` / `reference_*.md`

handoff から永続記録に昇格すべきものがあれば、handoff 書いた後に対応 skill (= `incident` / ADR 起こし) に進む。

## 例外処理

- **session が trivial (= 5 分の typo fix 等)**: handoff 不要。trivial 判断は AI が行う
- **session が長すぎて 7 節に収まらない**: 残課題を 3 個以下に絞る (= 残り 3 個に絞れないなら session 自体が責務過剰)。詳細は incidents / decisions に分けて handoff からは link で逃がす

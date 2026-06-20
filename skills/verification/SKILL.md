---
name: verification
description: 動作テスト (behavioral verification) を「意図と跨いだ境界から導く verification plan」として設計し、人間と共同で記録・クローズするための skill。コードレベルのバグは TDD hook が潰すが、残余リスクは継ぎ目 (cross-repo 契約 / 要件 / 「実物を見ずの完了」/ 環境) に移動しており、それらは repo 内 unit test の射程外で緑のテストが誤った契約を固定して false confidence を配る (mood incident)。この skill は「何を動作テストすべきか」を実装からでなく意図から導き、各行に外部オラクルを与え、`docs/verification/<branch>.md` に記録し、OPEN 行がゼロになるまで統合を通さない (ADR 0007 / `block-merge-if-verification-unclosed.sh`)。feature 実装が in-review に近づいたとき・統合 (merge) の前・「動作確認/テスト設計して」と言われたとき・抽象指示で実装した直後 (人間が何を確かめるべきか知らないとき) にロードする。
---

# /verification — 動作テスト設計と共同記録

このスキルは **動作テスト (behavioral verification) の設計**を担う。`require-test-companion` (TDD hook) が「コードの正しさ」を関数単位で守るのに対し、こちらは**継ぎ目 (seam)** — cross-repo 契約 / 要件 / 「実物を見ずの完了」/ 環境 — の検証を設計する。残余の事故はここに移動している (ADR 0007、appo-followup の incident ログは 1 件もロジックバグでない)。

## 唯一の原則

> **テストは「実装」からでなく「意図」と「跨いだ境界」から導く。**

実装を見てテストを起こすと、自分の前提を正解として固定する (著者=採点者の円環)。mood incident の zod test は「空 mood を弾く」で**緑だった** — 緑のまま全予約が reject された。だから全行に kill-question を一度問う:

> **「このテストが緑のまま、ユーザーが困る状態はありうるか?」** — Yes ならオラクルが間違っている。

## いつ呼ぶか

- feature が in-review に近づいた / 統合 (merge) の前
- 抽象指示で実装した直後 (= 人間が「何が作られ何を確かめるべきか」を知らない状態)
- `/verification` 明示呼び出し
- 統合を試みて `block-merge-if-verification-unclosed.sh` に止められたとき

## ワークフロー

### Step 1: 意図を 1 文で確定し、人間に behavior space を確認させる

抽象ゴールを 1 文で書く。そこから**満たすべき挙動 (behavior space)** を列挙する — 実装の構造でなく、ユーザー/呼び出し側から見た振る舞いで。**意図は既約な人間領域**なので、列挙したら人間に「抜けている挙動はないか」を確認・追加させる (plan 時 = 最安の時点)。

### Step 2: 跨いだ境界を機械的に洗い出す (層1: 知れる継ぎ目)

「正しいか?」でなく**「この変更はどの境界を跨ぐか?」**を問う (判断でなく開示なので AI が答えられる)。定番の型:

- **データが境界をまたぐ所**で両端を自分が握っていない: form→backend、repo→repo、API、env、外部サービス ← mood はここ
- AI が要件を**言い直した**所 (原典を指していない)
- 「完了」を**実物を見ずに**主張する所
- 環境が前提と**違いうる**所 (checkout / branch / .env)

### Step 3: 挙動ごとに技法とオラクルを選ぶ

| 挙動の形 | 技法 | オラクル |
|---|---|---|
| 入力の有効/無効の境目 | 等価分割 + 境界値 | 期待値 (既知) |
| 入力の組合せで分岐 | デシジョンテーブル | 期待値 |
| 状態が遷移する | 状態遷移テスト | 不正遷移が起きない |
| 正解が一意に書けない (生成物・非決定的) | メタモルフィックテスト (入力を変えたら出力がこう変わるべき、の*関係*) | 不変関係 |
| 全入力で成り立つ法則 | プロパティテスト | 不変量 |
| **両端を握ってない境界** | **契約テスト (consumer-driven)** | 相手の実出力 |
| 異常系・想定外 | ネガティブ / エラー推測 | 落ち方が安全 |
| 未知の未知 | 探索的テスト (人間) + 本番計器 | 実アウトカム |

**オラクルは必ず AI の外に置く。** 期待値が書けない → プロパティ/メタモルフィック。跨ぐ → 契約 or 実アウトカム。意図レベル (「これが欲しかったか」) → **人間にフラグ (`HUMAN`)**。オラクルが見つからない挙動を「pass と仮定」で埋めない。

### Step 4: verification plan を書く

`docs/verification/<branch>.md` (branch の `/` は `_` に)。1 行 = 1 ケース、先頭が STATUS:

```markdown
# verification plan — <意図を 1 文>
# 落とした範囲: <テストしないと決めたもの — 無音カット禁止>
# STATUS | kind | behaviour | oracle | by | evidence/note
TODO  | contract | form 出力キー ⊆ schema 必須キー | サイトの実出力 | ai |
HUMAN | e2e      | デモ予約を最後まで通す           | submissions に行が立つ | human |
TODO  | monitor  | 当日CV>0 かつ予約=0 を検知       | 日次集計アラート | ai |
DROP  | unit     | css のピクセル厳密一致           | n/a | ai | low risk, 価値<コスト
```

STATUS 語彙: `TODO` (未実施) / `FAIL` (失敗) / `HUMAN` (人間の実施待ち) = **OPEN**。`PASS` (オラクルで検証済) / `DROP` (テストしない・**理由必須**) = CLOSED。`kind` = unit / contract / e2e / manual / monitor (テストピラミッド。AI 開発の残余は下 3 つに偏る)。

### Step 5: 実行して閉じる (人間と共同記録)

- **自動行 (by=ai)** を実行し、結果を `PASS`/`FAIL` に。エビデンス (PR/コマンド/出力) を最終列に。
- **`HUMAN` 行**を人間に手渡す: 具体的な手順 + 期待。人間が実施して `PASS`/`FAIL` と実施者を記録 (= 誰の判断かが残り、再 litigate しない)。
- 各 `PASS` の前に kill-question を一度問う。
- テストしないと判断したものは**理由つき `DROP`** で明示する (理由なき DROP は gate が弾く)。

### Step 6: 統合時の地図を人間へ渡す

完了時、人間へ引き継ぐ (抽象指示の代償 = 人間が地図を持たない、を埋める):

1. **何ができたか** (機能・挙動)
2. **何を跨いだか** (境界 = テストした行)
3. **あなたが手で確認すべきもの** (`HUMAN` 行 = 人間しか採点できない意図・整合)
4. **未知用に何を計器化したか / 盲点** (`monitor` 行、未実装なら盲点と白状)

## 関所と射程

`block-merge-if-verification-unclosed.sh` が、lane branch の merge に対し plan の存在・非空・OPEN 行ゼロ・理由なき DROP ゼロを fail-closed で要求する (opt-in = `docs/verification/` を置く)。

**射程の境界**: gate は統合 (merge) を信号にするので branch を切らない逐次作業は捕まえない。そこはこの skill (plan 時の precondition) が担う。未知の未知は plan に載らない → 本番計器のまま (例: mood の予約棄却アラート PR#305)。最終オラクル (意図・整合) は人間に残る。

## ライフサイクル

verification plan は **per-branch の ephemeral 記録**。統合が終わったら `integrate` skill が終端を所有する: 自動行の設計は永続テスト/CI に昇格、本番に逃げた行は incident→memory へ、閉じた plan は archive する (board/worktree 撤去と同じ責務)。

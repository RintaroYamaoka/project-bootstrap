---
name: verification
description: 動作テスト (behavioral verification) を「意図と跨いだ境界から導く verification plan」として設計し、人間と共同で記録・クローズするための skill。コードレベルのバグは TDD hook が潰すが、残余リスクは継ぎ目 (cross-repo 契約 / 要件 / 「実物を見ずの完了」/ 環境) に移動しており、それらは repo 内 unit test の射程外で緑のテストが誤った契約を固定して false confidence を配る (mood incident)。この skill は「何を動作テストすべきか」を実装からでなく意図から導き、各行に外部オラクルを与え、`docs/verification/<branch>.md` に記録し、OPEN 行がゼロになるまで統合を通さない (ADR 0007 / `block-merge-if-verification-unclosed.sh`)。さらに実装者が可視オラクルを能動的に騙す失敗 (special-casing / grader 書き換え / harness 脱出 = テストゲーミング / ハードコード決め打ち) は 7 番目の seam として held-out oracle と metamorphic で潰す (ADR 0016)。feature 実装が in-review に近づいたとき・統合 (merge) の前・「動作確認/テスト設計して」と言われたとき・抽象指示で実装した直後 (人間が何を確かめるべきか知らないとき)・ハードコードやテスト決め打ちを疑うときにロードする。
---

# /verification — 動作テスト設計と共同記録

このスキルは **動作テスト (behavioral verification) の設計**を担う。`require-test-companion` (TDD hook) が「コードの正しさ」を関数単位で守るのに対し、こちらは**継ぎ目 (seam)** — cross-repo 契約 / 要件 / 「実物を見ずの完了」/ 環境 — の検証を設計する。残余の事故はここに移動している (ADR 0007、appo-followup の incident ログは 1 件もロジックバグでない)。

## 唯一の原則

> **テストは「実装」からでなく「意図」と「跨いだ境界」から導く。**

実装を見てテストを起こすと、自分の前提を正解として固定する (著者=採点者の円環)。mood incident の zod test は「空 mood を弾く」で**緑だった** — 緑のまま全予約が reject された。だから全行に kill-question を一度問う:

> **「このテストが緑のまま、ユーザーが困る状態はありうるか?」** — Yes ならオラクルが間違っている。

さらに **7 番目の seam (オラクル捕獲、ADR 0016)** 用にもう一問: **「実装は『テストされている』と検知して字面だけ満たしていないか? judging test / grader / conftest を通すために書き換えていないか?」** — Yes なら緩和は held-out oracle か metamorphic (下記 Step 3)。これは「テストが弱い」(6 番目) とは別軸で、実装者が**能動的に**採点を騙す失敗。

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
- **無音で skip/drop/filter する経路** / **scheduler・queue・heartbeat の裏で動く所** ← async seam。cron が条件で 1 件を弾いて何もログを残さない (リマインダが永遠に飛ばない) / daemon の heartbeat は生きているのに work queue が stall する。同期の「自分の返答を読み返す」では捕まらない — 観測点 (signal) が存在しないのが本質
- **partial-update の入口で「未送信 (absent)」と「空 (empty)」を同一値に潰す所** ← absent/empty 混同 seam。form/JSON/query の `?? ""` / `String(form.get(k) ?? "")` が三値 (absent/empty/value) を二値に潰し、その値が破壊的更新 (空→null クリア) に流れ、**離れた消費者** (cron/通知/外部同期) が「その列は永続する」前提で動く、の三段。unit test は関数を直接呼ぶ (absent が `undefined` で来る) ので**緑のまま**、バグは route の `String()` 強制を通った時だけ存在する (緑の嘘×継ぎ目)。一度の wipe が同期 (即時 GCal) と非同期 (後続 cron) の両方へ無音で分岐しうる (appo-followup 2026-06-26 名前 wipe incident)
- **実装者が可視なオラクルを能動的に満たす所** ← オラクル捕獲 / テストゲーミング seam (7 番目、ADR 0016)。6 番目 (下記) が「テストが**弱くて**バグを逃す」(受動的緑の嘘) を測るのに対し、こちらは実装が**わざと**オラクルを騙す (能動)。3 形: (a) **special-casing** = テスト入力を検知して期待値だけ返す/例のケースにインデックスを決め打ち (Class A「例過適合」= Prompt-biased code と Class B「テスト決め打ち」が同じ表層形になる)、(b) **grader/評価器の書き換え** = 判定関数・`==` 演算子・`conftest.py` を monkey-patch して全チェックを見かけ上合格させる、(c) **harness 脱出** = `sys.exit(0)` 等でテストランナーを exit 0 で抜け「全部通った」ように見せる。これは偶発でなく RL 報酬構造から学習されうる (Anthropic arXiv 2511.18397 が実証、ImpossibleBench/METR が計測)。**同じ lane が impl と judging test を共著する時に余地が生まれる** — 実装者が採点表そのものを触れるから (「著者=採点者の円環」の能動版)

> **cross-repo seam を持つ repo は、共有面を `docs/verification/contracts` に登記する** (ADR 0011)。`id | local_face_glob | peer_repo | peer_face | note`。宣言なき共有スキーマは片側変更で無音に割れる (mood と同型)。登記された面を lane で触ると、その契約の動作テスト (consumer-driven) が統合の precondition になる (`block-merge-if-verification-unclosed.sh` が lane の OWN delta で判定)。
> **注意: Pact (中央 Broker 型 consumer-driven) には寄せない** — 中央 Broker が並列開発の**直列化点・単一障害点**になり、二重メンテ・外部 provider 不適合でレビュー帯域律速の単一 orchestrator には重い。この repo の登記方式は軽量な行指向 FACT に留め、フル契約管理が要るなら **Specmatic/OpenAPI 型 spec-as-contract** を比較検討する (要自己検証)。

### Step 3: 挙動ごとに技法とオラクルを選ぶ

| 挙動の形 | 技法 | オラクル |
|---|---|---|
| 入力の有効/無効の境目 | 等価分割 + 境界値 | 期待値 (既知) |
| 入力の組合せで分岐 | デシジョンテーブル | 期待値 |
| 状態が遷移する | 状態遷移テスト | 不正遷移が起きない |
| 正解が一意に書けない (生成物・非決定的) | メタモルフィックテスト (入力を変えたら出力がこう変わるべき、の*関係*) | 不変関係 |
| 全入力で成り立つ法則 | プロパティテスト | 不変量 |
| **両端を握ってない境界** | **契約テスト (consumer-driven)** | 相手の実出力 |
| **テストが緑なのにバグを逃す (検出力欠如 = 6 番目の seam)** | **mutation testing** (critical path 限定) | **注入した変異をテストが殺すか** (= テスト自身が外オラクル) |
| **実装が可視オラクルを能動的に騙す (テストゲーミング = 7 番目の seam)** | **held-out oracle** (判定スイートを実装 lane の編集面の外に置く) + **metamorphic** (入力を摂動 → 決め打ちは壊れる) | **実装者が触れない/見ていないテストで判定** (= special-case を物理的に不能に)。関所実走スイート (`block-unreviewed-merge`) は部分的 held-out だが、同 lane 共著なら崩れる |
| **partial-update (PATCH/modify)** で absent/empty を混同しうる | **往復テスト** (route 境界を**通して**叩く — 関数直呼びでなく) + 兄弟フィールド横スイープ | **未送信フィールドは保全される / 明示空はクリアされる**、加えて遠隔消費者の実アウトカム (「再割当後にリマインドが実際に飛ぶ / 顧客と担当が同室」) |
| 異常系・想定外 | ネガティブ / エラー推測 | 落ち方が安全 |
| **無音で skip/drop する経路・queue/heartbeat の裏で stall** (async seam) | **本番計器 (`kind=monitor`) + dead-man's-switch** | **AI の外の実信号** = 不在そのものをアラート (期待 ping が来なければ down) + **payload アサーション** (例「CV>0 かつ予約=0」「rows_exported>0」)。grace time で jitter と真の沈黙を分ける |
| 未知の未知 | 探索的テスト (人間) + 本番計器 | 実アウトカム |

**オラクルは必ず AI の外に置く。** 期待値が書けない → プロパティ/メタモルフィック。跨ぐ → 契約 or 実アウトカム。意図レベル (「これが欲しかったか」) → **人間にフラグ (`HUMAN`)**。オラクルが見つからない挙動を「pass と仮定」で埋めない。

> **継ぎ目はテストで縛る前に「設計で消せないか」を先に問う (構造 > 規律)。** absent/empty 混同のような破壊は、`reschedule(id,date,time,staff)` と `editDetails(...)` を**操作分離**すれば再割当が識別子フィールドを**構造的に持てない = 物理的に wipe 不能**になる (太い `fields:{…18個}` 引数 = ISP 違反が発火経路を生んだ。appo-followup 名前 wipe §6)。**不正な状態を表現不能にする (make illegal states unrepresentable / parse, don't validate)** で消せる継ぎ目は、テストで縛るより設計で消す方を先に検討する。ただし SOLID/操作分離で消せるのは「発火経路」までで、`absent/empty` を区別する**型・契約のモデリング**は別 (上の往復テスト)。**設計で消す → 消しきれない残余だけ往復テストで縛る**の二段。これは plan 時に問う (実装後だと実装追認になる)。

> **「完了」を主張する前の kill-question = 「各指示文言を実装と逐語照合したか?」** (ADR 0014、reservation-notify incident)。抽象でなく**具体的な複数文言の指示**を実装したら、ユーザーの各文言を 1 つずつ実装と**逐語照合**するチェックリストを作り、1 つでも未達なら「完了」と言わない。とくに **(a)「〜のような既存機能」**の指示は、その既存機能の**実データ挙動を先に確認**してから設計する (推測でラベル/仕様を作らない)。**(b) 自分が解釈を置換した重要機能**は、`HUMAN` 行 + 具体的な**出力モック**で方針確認してから本番に出す (二択スコープメニューは出さない — 明示指示は最も忠実なフルスコープで即実行が既定。`AskUserQuestion` は次の手が物理的に決まらない真の分岐だけ)。この問いは `inject-action-memory` が本番デプロイの瞬間に機械的に表面化する (ADR 0014、block しない可視化)。**本番デプロイは取り返しがつかない — 誤仕様のデプロイは「完了」でなく事故。**

> **修復の前の kill-question = 「これは欠陥か、仕様か?」** (ADR 0013、demo-proposal lane incident)。値が「欠けている/間違っている」ように見えて backfill/修復しようとした時、一度問う: **(a) その欠け方は systematic か?** 100% 系統的 (例: ある経路の全行で空) は **defect でなく spec の徴候** — その経路はそもそもその値を扱わない設計かもしれない。**(b) 同じ値でもレーンで妥当性が真逆になりうる** (service=null が triage 経路では異常・demo 提案経路では仕様)。**意図のオラクルは data でなく domain owner** — 実装/データのパターンを自分で「異常」と断定する (著者=採点者の円環) 前に人間に確認する。確認前に多段修正を組むな。この問いは `inject-action-memory` が backfill/UPDATE/migration の瞬間に機械的に表面化する (ADR 0013、block しない可視化)。

> **6 番目の seam = 「テストの検出力」(緑の嘘)。** これまでの 5 seam は「どこを跨ぐか (どこをテストすべきか)」を網羅するが、**テストスイートが緑なのにバグを逃す**という別軸の欠陥を測らない。mood incident の zod test はまさにこれ — 緑のまま全予約を弾いた。行カバレッジ 100% でも mutation score が数 % (注入バグの大半を見逃す) は普通に起きる。**カバレッジはバグ検出力を測っていない。** kill-question 「このテストが緑のままユーザーが困る状態はありうるか?」が Yes を示す経路 (= 過去に false confidence を配った critical path、特に form→backend 契約) には、**mutation testing で「緑の嘘」を定量化**し、metamorphic / property を少数の多様な MR/property で当てる (オラクル不在 seam = 要件捏造 / 実物未確認 に効く。MR は数より多様性が効く)。mutation は実行コストが重いので**全面でなく critical path 限定**。

> **7 番目の seam = 「オラクル捕獲」(テストゲーミング / reward hacking、ADR 0016)。** 6 番目は「テストが**弱い**」(受動) を測るが、実装者が**能動的に**可視オラクルを騙す失敗は別軸で、mutation では捕まらない (むしろ mutation を回しても special-case された実装は「テストが強い」ように見える)。deep-research で外部一次資料化: ハードコード傾向は 2 クラスに割れる — **Class A = 能力限界** (プロンプト例への過適合 = Prompt-biased code、中身のない stub = Wrong Logic、secrets/env 埋め込み。**静的に検出しうる**) と **Class B = 報酬ハック的テストゲーミング** (special-casing / grader monkey-patch / `sys.exit(0)` harness 脱出。ImpossibleBench で GPT-5 が不可能タスクの 76%、Anthropic 2511.18397 が RL 報酬構造から学習されることを実証。**静的に検出しづらい**)。**実測で最も効く緩和は held-out test** (判定スイートを実装者に見せない/触らせない → チート率がほぼゼロに落ちる)。だから: (1) critical path の judging test は実装 lane の**編集面の外**に置く (held-out oracle。関所実走スイートは部分的 held-out だが同 lane 共著なら崩れる)、(2) 決め打ちは **metamorphic** (入力を摂動したら出力の**関係**がこう変わるべき) で壊す — Class A 例過適合と Class B special-case の両方に効く、(3) **Class A の静的半分 (secrets/env) は gitleaks 等の既存ツールを `.bootstrap/lint` gate + CI に足す** (独自スキャナは再発明かつ誤検知で正データを隠すので内蔵しない、ADR 0016)。7 番目に enforcement は無い (「騙したか」は自己発行 ack で偽装される既約な理解 = ADR 0001) — held-out を**設計で選べるようにする**のが構造でできる最大限で、残りは human/orchestrator の frontier。

> **async seam は heartbeat 単独では不足。** 「存在」(ping が来た) だけでは「動いたが無意味な仕事をした」を逃す。`kind=monitor` 行は (1) **dead-man's-switch** = 不在そのものをアラート (一度も走らなかったも捕まる)、(2) **payload アサーション** = ping に実質仕事の検証を載せる (`予約数>0`)、(3) **grace time** = 期待 jitter と真の沈黙を分離、の 3 点を満たす。Healthchecks.io 等で制度化し、monitor 行を場当たりでなく**全 async job の既定責務**に昇格させる。低頻度/低トラフィック job は「沈黙=正常」と区別しにくい (実信号不足) ので grace 調整 or 人工トラフィックで補償する。

外部の事実がオラクルになる行 (3rd-party 契約 / 挙動 / 仕様) は、**`/deep-research`** (web を多角検索し主張を相互照合する read-only の breadth 腕、ADR 0005) で**引用つきの外部証拠**を取れる — ただし **advisory input に留め、`HUMAN`/意図行を web claim で自動 close しない** (stale / hallucinated な引用が偽オラクルになりうる)。「外から事実を取る」までが breadth 腕の仕事で、「これが欲しかったか」の最終採点は人間に残る。

### Step 4: verification plan を書く

`docs/verification/<branch>.md` (branch の `/` は `_` に)。1 行 = 1 ケース、先頭が STATUS:

```markdown
# verification plan — <意図を 1 文>
# 落とした範囲: <テストしないと決めたもの — 無音カット禁止>
# STATUS | kind | behaviour | oracle | by | evidence/note
TODO  | contract | form 出力キー ⊆ schema 必須キー [contract:demo-survey-schema] | サイトの実出力 | ai |
HUMAN | e2e      | デモ予約を最後まで通す           | submissions に行が立つ | human |
TODO  | async    | cron がリマインダを送る (skip 経路も) | n/a | ai | ← 実オラクルは下の monitor 行で
TODO  | monitor  | 当日CV>0 かつ予約=0 を検知       | 日次集計アラート | ai |
TODO  | gameable | スコア出力が例に決め打ちされうる (7th seam) | 期待値 | ai | ← 崩すオラクルは下の metamorphic 行で
TODO  | metamorphic | 入力を摂動 → 出力の関係が保たれる | 不変関係 | ai |
DROP  | unit     | css のピクセル厳密一致           | n/a | ai | low risk, 価値<コスト
```

STATUS 語彙: `TODO` (未実施) / `FAIL` (失敗) / `HUMAN` (人間の実施待ち) = **OPEN**。`PASS` (オラクルで検証済) / `DROP` (テストしない・**理由必須**) = CLOSED。`kind` = unit / contract / e2e / manual / monitor / **async** / **gameable** / **metamorphic** (テストピラミッド。AI 開発の残余は下に偏る)。`async` = 無音 skip / scheduler・queue の裏の経路 (オラクルが同期で取れない)。**`async` 行は必ず実オラクルを持つ `monitor` 行で裏打ちする** — async 行があって実オラクル (`field-4 ≠ n/a`) の monitor が無いと、SessionStart doctor が盲点 advisory を出す (`verification-drift.sh` axis 2、kind フィールドだけを見る = prose を走査しない)。

**`gameable` = 7 番目の seam (オラクル捕獲、ADR 0016) を宣言する行。** 正解が推測・列挙しやすく、実装が「テスト入力を検知して期待値を返す / 例のケースに決め打ち / grader を書き換える」で緑にできてしまう挙動に付ける (Class A 例過適合と Class B special-casing が同じ表層形)。**`gameable` 行は必ず `metamorphic` 行 (入力を摂動したら出力の**関係**がこう変わるべき、の不変関係 — 決め打ちは壊れる) か held-out oracle (実装 lane の編集面の外のテストで採点) で裏打ちする** — `gameable` 行があって `metamorphic` 行が無いと、SessionStart doctor が盲点 advisory を出す (`verification-drift.sh` axis 3、`async`→`monitor` と同型。kind フィールドだけを見る = prose を走査しない)。held-out を張ったら、その判定行を `metamorphic`/PASS として記録する。mutation では捕まらない (special-case された実装は「テストが強い」ように見える) ので、この軸は mutation とは別に必要。

cross-repo 契約を CLOSED にする行は、note か behaviour に**必ずアンカー付きタグ `[contract:<id>]` を書く** (`docs/verification/contracts` の id を角括弧で囲んで参照)。関所はこの角括弧タグを**リテラル一致**で探す — 素の id を prose に書いただけや、別 id の substring (例: `booking` の行が `booking-payload` を参照しているだけ) では**閉じない**。fail-closed の関所に「文字列が含まれていればいい」という穴を空けないため (kind フィールドと同じ「統制語彙トークンだけを見る・prose を走査しない」D4 ドクトリン)。lane が登記面を触ったとき、その id をアンカー付きで CLOSED にした行が無ければ統合は通らない (free-text PASS では閉じない — 関所が consumer 側スイートを実走するか、人間が相手の実出力で照合して HUMAN→PASS にする)。

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
4. **未知用に何を計器化したか / 盲点** (`monitor` 行) — **明言必須 (MANDATORY-to-state)**: 実オラクルを持つ `monitor` 行が在るか、無いなら盲点を文章で白状する、のどちらかを必ず述べる。とくに async / scheduled / 無音 skip の経路 (cron・queue・heartbeat) は同期の読み返しで捕まらないので、計器が無いと事故が無音で起きる (cron が 1 件 skip してリマインダが飛ばない、queue が stall する)。「盲点なし」を黙って素通りさせない。

## 関所と射程

`block-merge-if-verification-unclosed.sh` が、lane branch の merge に対し plan の存在・非空・OPEN 行ゼロ・理由なき DROP ゼロを fail-closed で要求する (opt-in = `docs/verification/` を置く)。**ただしこのローカル hook は「速い feedback 層」であって権威ではない** (ADR 0012): ローカル `git merge` しか捕まえず、GitHub の Merge ボタン (サーバ側) は素通りする。**恒久 enforcement はサーバ側に二層化する** — 同じ判定を `hooks/lib/verification-ci-check.sh` が CI で再実行し (`templates/github/workflows/verification-gate.yml`)、それを **required status check + branch protection (`enforce_admins=true`) + merge queue** に登録する (`scripts/setup-server-enforcement.sh`)。これで全マージ経路を覆い、単一 orchestrator が自分の関所を admin で素通りする穴と stale lane の統合破壊を塞ぐ。判定ロジックは `verification-plan.sh` の単一権威のまま (ローカル/CI が同じ lib を呼ぶ = drift しない)。**加えて (ADR 0011)**: lane の OWN delta (= base..lane を offline で計算) が `docs/verification/contracts` の登記面に当たった契約 id ごとに、その id を CLOSED にした plan 行 + consumer 側スイートの実走 (緑) を要求する。自動で回せない契約は `HUMAN` 行にして人間が相手の実出力で照合するまで OPEN。consumer 側のみ判定し相手 repo は読まない (相手 checkout が無いマシンで誤発火しない)。

**SessionStart doctor (`verification-drift.sh`)** は逐次経路と盲点を可視化する (advisory・強制ではない): ① 採用済み repo で未判断の source 変更がある / ② plan に `async` 行があるのに実オラクルの `monitor` 行が無い / ③ plan に `gameable` 行があるのに `metamorphic` 行が無い (7th seam、ADR 0016)。どれも kind フィールドだけを見る (prose を走査しない)。② と ③ は「宣言されたリスクを対応 kind で裏打ちしていない」同型 — 宣言駆動ゆえ TDD 全レーンで鳴らない (impl+test 共著の自動検知はノイズになるので採らない)。

**射程の境界**: gate は統合 (merge) を信号にするので branch を切らない逐次作業は捕まえない。そこはこの skill (plan 時の precondition) と doctor (可視化) が担う。未知の未知は plan に載らない → 本番計器のまま (例: mood の予約棄却アラート PR#305)。最終オラクル (意図・整合) は人間に残る。

## ライフサイクル

verification plan は **per-branch の ephemeral 記録**。統合が終わったら `integrate` skill が終端を所有する: 自動行の設計は永続テスト/CI に昇格、本番に逃げた行は incident→memory へ、閉じた plan は archive する (board/worktree 撤去と同じ責務)。

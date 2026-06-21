# 0007 — 動作テスト設計を「意図アンカーの verification plan」として構造化し、統合の precondition にする

- **Status**: Accepted
- **Date**: 2026-06-21
- **Deciders**: Rintaro Yamaoka
- **References**: appo-followup `docs/incidents/2026-06-20-demo-booking-mood-contract-drift` / [0002](./0002-sprint-gate-fail-closed.md) / [0004](./0004-parallel-mode-integration-gate.md) / [0005](./0005-ultracode-execution-engine-governed-by-bootstrap.md) / memory `feedback_gate_signal_and_failmode` / `feedback_gate_distribution_coverage`

---

## Context (背景)

これまでの bootstrap は **コードレベルの正しさ**を構造で守ってきた: TDD hook (`require-test-companion`) が test 先行を、commit/merge gate が実スイートの実行を強制する。dogfood の観測では、この層はよく効いている — 「ロジックバグ」は圧倒的に減った。

だが appo-followup の incident ログを種類で見ると、残った事故が**1 件もロジックバグでない**: cross-repo の契約ズレ (mood)、要件の捏造、stale checkout、rebase の承認 commit 落ち、deploy の虚偽完了、運用 over-stop。**残余リスクが丸ごと「継ぎ目 (seam)」へ移動した** — repo 内 unit test の射程外の領域。

決定的なのは mood incident だ。サイト repo が問診から `mood` 設問を削除 → appo の `demoSiteSurveySchema` は `mood: z.string().min(1)` 必須のまま → 当日 CV 17 人で**予約成立 0**。ここで効かなかったのは「テストが無かった」ことではない。zod の unit test は**緑だった** — 「空 mood を弾く」を正しく検証していた。**緑のテストが間違った契約を固定し、false confidence を配った。** TDD は継ぎ目バグに対して「効かない」だけでなく、緑で**害になる**。

テスト設計の核心は技法の多さでなく**オラクル問題** = 「正解をどこから取るか」。AI 駆動開発ではこれが鋭い: AI が実装の著者でありながら、その実装からテストを起こすと*自分の前提を正解として固定する* (著者=採点者の円環)。さらに抽象指示 (AI に最適実装を任せる) は生産性の源だが、代償として**人間が「何が作られたか」を知らない** — 唯一外注できない採点者 (意図・整合性の判断) が、存在を知らないものを採点できず無力化される。

## Decision (決定)

**動作テスト設計を「意図と跨いだ境界から導く verification plan」という永続・共有・fail-closed な成果物にし、その plan が閉じていることを統合 (lane branch の merge) の precondition として強制する。**

唯一の設計原則: **テストは実装からでなく意図と境界から導く。** これを構造で担保するため二点にアンカーする (TDD が test を先に書く理由と同型):
- **plan 時 (コード前)**: 抽象意図 → 検証すべき挙動 (behavior space) とオラクルを導く。実装がまだ無いので実装追認にならない。人間が behavior space を確認・追加する (意図は既約な人間領域、最安の時点)。
- **完了 / 統合時**: 計画と実物を突合し、自動行を実行 (PASS)、人間しか採点できない行を実施・記録 (HUMAN)、テストしない行を理由つきで明示 (DROP)。OPEN 行が残る限り統合は通らない。

成果物 = `docs/verification/<branch>.md`、行指向 (jq 非依存)。1 行 = 1 テストケース、先頭が STATUS:

```
STATUS | kind | behaviour | oracle | by | evidence/note
```
STATUS 語彙: `TODO`/`FAIL`/`HUMAN` = OPEN、`PASS` = CLOSED、`DROP` = CLOSED (理由必須)。フォーマット権威は単一 lib `hooks/lib/verification-plan.sh` に集約 (gate/doctor/skill が共有 = drift 防止。gate-entry/detect-test-suite/source-face と同じ方針)。

強制点 = `hooks/block-merge-if-verification-unclosed.sh` (PreToolUse on `git merge`)。review gate と同じ lane 信号 (活性 board の task branch + linked worktree の branch、ADR 0004) を使い、lane branch の merge に対して plan の存在・非空・OPEN 行ゼロ・理由なき DROP ゼロを要求する。

doctrine の 4 設計判断への写像 (新軸でなく既存判断をテスト設計に向け直す):
- **① 分解**: 完了 = コードが動く **AND** plan が閉じている。plan 不在は fail-open に逃さず block (強制したい判定を advisory にしない)。
- **② 信号選び / fail-mode**: 信号 = 統合行為そのもの。オラクルは AI の外 (実アウトカム/意図) を要求。オラクル不在の挙動は「pass と仮定」でなく `HUMAN` で**人間に倒す**。kill-question 「このテストが緑のままユーザーが困る状態はあるか?」で誤オラクルを弾く。
- **③ 配備の可視化**: plan も gate も配備されて初めて効く。`scripts/doctor.sh` が verification 採用済みで gate 未配備 (vendored-coverage gap) を partial で surface。
- **④ 計測つき**: 品質 metric は test 数や行カバレッジ (虚栄) でなく **escape rate** (どの行も予測しなかった本番事故) と**再発率**。incident→memory ループに直結。

### 採用しなかった代替案

- **markdown 表 / YAML を正本にする**: 人間に優しいが gate の決定的 parse に弱い (jq 非依存方針)。行指向の STATUS 先頭フォーマットなら pure bash で OPEN 行を数えられ、人間も編集できる (`.gate`/`.bootstrap-*` と同系)。
- **plan 不在 = fail-open**: sprint gate の教訓 (ADR 0002 / incident 2026-06-02) の再来。「計画を書かない」で gate を素通りさせてしまう。採用済み repo で lane branch を merge するのに plan 不在は fail-closed。
- **commit ごとに強制**: WIP commit を縛り過剰 friction。統合 (= 全経路が通る入口) を信号にする (ADR 0004 の関所原理)。
- **AI に「正しいか」を採点させる**: 著者=採点者の円環。AI には「何を作り何を跨いだか」の*開示*と*技法選択*だけ担わせ、最終オラクル (意図・整合) は人間に残す。

## Consequences (結果)

### 良い影響

- 緑のテストが間違った契約を固定する罠 (mood) に対し、kill-question + 外部オラクル要求 + cross-repo contract という区分が構造的な防御になる。
- 抽象指示 (生産性の源) を保ったまま、完了時に「何を作り何を手で確かめるべきか」の地図を人間へ返す非対称 (入力は抽象・出力は具体)。
- verification が会話で消えず、永続・共有・fail-closed な成果物になる (docs/ = external memory)。

### 悪い影響 / トレードオフ

- **射程の境界**: gate は統合 (lane branch の merge) を信号にするので、branch を切らない逐次作業は捕まえない。そこは `verification` skill (plan 時の precondition) と doctor (可視化) が担う。**doctor (可視化) の半分は当初未実装だったが Amendment (2026-06-21) で実装した** — 下記参照。trunk への全変更を *fail-closed で* 縛る universal 版 (push-to-protected 拡張) は依然として拡張余地 (未実装)。
- **PR 経路**: 手元 hook は GitHub PR 画面の merge を通らない (review gate と同じ穴)。`templates/ci/bootstrap-verification-gate.yml` が plugin 非依存・self-contained な CI net として全 PR に閉じた計画を要求する (lib の semantics をインラインで再現)。
- 未知の未知 (層2) は plan に原理的に載らない。そこは実アウトカム計器 (本番モニタ) のまま — mood の PR#305 アラートがその例。
- plan 自体に穴 (AI が跨いだと気づかなかった境界) は残る。完全でない。が「何も知らず統合する」より桁違いにマシ。
- 最終オラクル (意図・整合) は人間に残る (= 単一 orchestrator の frontier)。上位1% の定義は「これらの判断が人間の頭から fail-closed な構造へ移っていく速さ」。

### 移行後に必要な保守

- plan の ephemeral lifecycle を `integrate` skill が所有する (統合後に閉じた plan を archive。board/worktree 撤去と同じ終端責務 — memory「ephemeral state は活性で読み終端処理を所有 skill の責務に」)。
- 新しい opt-in 機能を足したら doctor の vendored-coverage マッピングを更新する (require-test-companion の allowlist と同じ保守点)。

---

## Amendment (2026-06-21) — doctor が逐次経路の「未判断」を可視化する

**動機**: 本 ADR は射程の境界 (上記) で「逐次作業は doctor (可視化) が担う」と書いたが、その doctor 側は当初**未実装**だった。結果、`docs/verification/` を採用した repo でも、lane branch を切らずに trunk を直接いじる逐次変更は merge gate (lane merge が信号) を一切通らず、動作テストの要否判断が**無音で省かれた** (dogfood で表面化: 「プラグインで変更したのに verification を何も言って来ない」)。これは原則「要否判断を無音で省かない」と関所の配置 (lane merge 一経路のみ) の**カバレッジ差** — memory `feedback_gate_distribution_coverage`「関所は全方式が必ず通る行為に置く」の逐次版。

**決定 (本 ADR の ② 信号選び / ③ 配備の可視化 の適用、新軸ではない)**: SessionStart doctor に第3の audit 軸を足す。`docs/verification/` 採用済み repo で、current branch に source-face 変更 (未コミット ∪ main remote-tracking ref より先行する commit) があるのに verification 判断が記録されていない (plan 不在/空) とき、advisory を SessionStart context に注入する。判定エンジンは新 lib `hooks/lib/verification-drift.sh`。branch→plan パス導出は `verification-plan.sh` の `vplan_path_for_branch` に括り出し、merge gate と doctor が同一の信号を共有する (gate-signal drift 防止)。

**信号と fail-mode**:
- **可視化であって強制ではない** (merge gate のような fail-closed block にしない)。「ある変更に動作テストが要るか」は既約な判断 (ADR 0001 の残余) だが「要否判断すら記録していない」は FACT として surface できる (ADR 0003 の doctrine)。記録される判断は理由つき DROP だけでも良い — 強制するのは「テストを書くこと」でなく「判断を無音で省かないこと」。
- **opt-in** (`docs/verification/` 不在なら無音) かつ **offline** (fetch せず local main ref と比較。ref 不解決の local-only repo は未コミット集合のみで判定 = fail-open に過小報告)。repo-drift と同じ沈黙基準で advisory bloat を増やさない。

**残す穴 (意図的スコープ外)**:
- **要否判断の不在**だけを対象。trunk 上で OPEN のまま放置された plan の closure は捕まえない (merge gate が無い trunk 経路でクローズを fail-closed に強制するのは push-time 拡張の領分 = 上記 universal 版、未実装)。non-empty plan が在れば「判断は進行中」とみなし無音。
- **SessionStart は「開いた時点の state」を捕まえる net**。session を開いた後に同一 session 内で作った変更は次回 session まで surface されない (repo-drift と同性質)。同一 session 内の即時通知 (commit-time / prompt-time advisory) は同じ engine を再利用する follow-up 余地。

**検証**: `tests/hooks/verification-drift.test.bash` (engine 単体) + `bootstrap-session-doctor.test.bash` (注入の統合) + `verification-plan.test.bash` (`vplan_path_for_branch`)。この変更自体の verification plan は `docs/verification/main.md` (dogfood)。

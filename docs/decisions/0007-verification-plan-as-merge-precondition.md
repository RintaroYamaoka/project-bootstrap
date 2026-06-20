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

- **射程の境界**: gate は統合 (lane branch の merge) を信号にするので、branch を切らない逐次作業は捕まえない。そこは `verification` skill (plan 時の precondition) と doctor (可視化) が担う。trunk への全変更を縛る universal 版は push-to-protected への拡張余地 (本 ADR では未実装)。
- **PR 経路**: 手元 hook は GitHub PR 画面の merge を通らない (review gate と同じ穴)。`templates/ci/bootstrap-verification-gate.yml` が plugin 非依存・self-contained な CI net として全 PR に閉じた計画を要求する (lib の semantics をインラインで再現)。
- 未知の未知 (層2) は plan に原理的に載らない。そこは実アウトカム計器 (本番モニタ) のまま — mood の PR#305 アラートがその例。
- plan 自体に穴 (AI が跨いだと気づかなかった境界) は残る。完全でない。が「何も知らず統合する」より桁違いにマシ。
- 最終オラクル (意図・整合) は人間に残る (= 単一 orchestrator の frontier)。上位1% の定義は「これらの判断が人間の頭から fail-closed な構造へ移っていく速さ」。

### 移行後に必要な保守

- plan の ephemeral lifecycle を `integrate` skill が所有する (統合後に閉じた plan を archive。board/worktree 撤去と同じ終端責務 — memory「ephemeral state は活性で読み終端処理を所有 skill の責務に」)。
- 新しい opt-in 機能を足したら doctor の vendored-coverage マッピングを更新する (require-test-companion の allowlist と同じ保守点)。

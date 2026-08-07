# Changelog

このリポジトリのすべての注目すべき変更はこのファイルに記録する。

形式は [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) に基づく。
バージョニングは [Semantic Versioning](https://semver.org/lang/ja/) に従う。

## [Unreleased]

### Added

- **完全ガイド (docs/guide/) を GitHub Pages で公開**。プラグインが AI 駆動で進化し続けると使用者側に理解負債がたまる — 全体像 (発注→検収の流れ / コマンド 11 個 / 止まる 6 場面 / opt-in マーカー表 / metrics の読み方 / フォルダの正体) を 1 枚に固定した解説ページ。配信は `.github/workflows/pages.yml` (build_type=workflow、`docs/guide/**` のみ)。正本は README / SKILL.md / ADR で、食い違ったら正本が勝つと明記。

## [0.34.0] - 2026-08-07

### Added

- **metrics.tsv schema v2 — 停止条件の突合と人間時間 (ADR 0024 追記)**。停止条件 (WO 10 節) は発注 gate が「書いたか」までしか強制できず、「守られたか」を見る仕組みが無かった。検収時に WO frontmatter の `retry_limit` を転記し、`retries > retry_limit` / `actual_tokens > budget_tokens` を「停止条件を破って走った」の信号として `wo-metrics.sh` が集計する。実行中に止める機構は作らない (「同一失敗の再試行か」は既約な判断で hook で数えれば proxy になる) — 破られた事実が検収で必ず可視化されれば取引材料としては足りる。加えて **人間時間 3 列** (`human_order_min` / `human_run_min` / `human_accept_min`、5 分刻みの自己申告): 律速資源 = 人間のレビュー帯域がどの工程 (発注まで / 実装中の対応 / 検収) に溶けているかを測り、「次にどこを自動化するか」をデータで決める。実運用 0 行のうちの schema 変更なので移行なし。v1 行 (10 列) とも共存する。
- **HUMAN 行の資産化質問 — 人間の確認を使い捨てにしない (`verification` / `integrate`)**。verification plan は per-branch ephemeral で、`HUMAN`/`manual` 行は人間が確認して閉じたら消えていた — 大規模化すると同じ継ぎ目を機能追加のたびに人間が確かめ直すコストが線形に増える。`PASS` で閉じるとき・integrate の archive 終端時に一問足した: 「この継ぎ目は次の変更でも壊れうるか? 恒久オラクル (テスト / monitor / contracts 登記) で守れないか?」— 守れる行は昇格してから archive、真に人間しか採点できない行 (意図・整合) だけが使い捨てを許される。**同じ継ぎ目の HUMAN 行が別 plan で 2 度目に出たら自動化必須の信号** (incident の「同じ問題に 2 回」と同型)。新しい成果物・gate は増やしていない (既存の close/archive 責務への 1 ステップ追加)。

### Changed

- **handoff の「長い session」trigger を縮退 (ADR 0008 #5)**。harness が長い会話の自動要約継続を持ったため、「session が長くなり `/clear` しそう」を理由とする handoff は harness と二重化する — trigger を「明示的な `/clear` の予告」に縮退し、handoff の領分を **context が消える境界を跨ぐとき** (明示 `/clear` / 別ターミナル・並走 Claude / 別 session 再開 / 重要な区切り) に限定した。置換ではない: 別 Claude / 翌日の cold restore と人間可読の引き継ぎ正本は依然 handoff の領分。
- **問い直して「変更なし」と確定したもの (記録)**: (a) Edit 時点の lane gate (`block-out-of-lane-edit.sh`) は commit 関所 (ADR 0017) と重複して見えるが、別 worktree への絶対 path 書き込み (incident M5) は commit 関所では捕まえられず、早期 feedback も実装まるごとの無駄を防ぐ — 二層は意図された設計 (`block-out-of-lane-commit.sh` ヘッダに明文)。(b) 新規 source file を信号にする 2 gate (sprint 判定 / WO 被覆) の統合は「1 つの記録が 2 つの判断の証拠を兼ねると、安い方だけ済ませて両方を名乗れる」ため不採用 (`block-impl-without-wo.sh` ヘッダに明文)。どちらも既存の設計判断が問いに答えており、hook 数は減らさない。

## [0.33.0] - 2026-08-07

### Added

- **上流工程 (発注 → 検収) を 1 サブシステム `commission` として統合した (ADR 0022)**。上流を独立プラグインとして作る試みは 2 回あり、2 回とも定着しなかった。`upstream-process` は README で独立性を設計目標に掲げ (「2 プラグインは片方だけでも成立する疎結合」)、その 2 行上で「判断を検出する gate は dead code になる。だから上流は hook にしない」と宣言していた。**この 2 つは因果関係にある** — bootstrap から独立していたいので強制層に届かず、届かないので advisory になり、advisory は忘れられた。本プラグインが他所で一貫して否定している失敗モードそのものである。`kanban-flow` は hook を 3 つ持ったが 3 つとも「文書 PR を誰が承認したか」を守るもので、**引き渡し内容の完全性を見るものは 1 つも無かった**。さらに外部ボード (GitHub Projects) が強制層から読めないため同期アダプタを書く必要が生じ、これは疎結合でなく内部スキーマへの無契約の依存だった。
- **「重い」の実体は成果物の量でなく記憶の負担だった**。利用者が保持すべき概念は bootstrap がほぼ 0 (「普段どおり頼むだけ」) なのに対し、upstream-process 約 25 (🔴🟡🟢 / born-追認 / 幹 / ベット / appetite / 出所タグ 4 種 / 署名等級 3 種 …)、kanban-flow 約 30 (カード型 2 / Status 6 列 / スコープ絵文字 / 12 種の書き分け …)。**bootstrap は複雑性を hook の中に隠し、上流 2 つは利用者の頭に預けていた**。今回は永続する成果物を **WO 1 種 + charter.md 1 ファイル**に畳んだ (13 種 → 2 種)。
- **自律稼働の事前条件を発注 commit の precondition にした (ADR 0023)**。前身 2 実装の作業指示テンプレートを実物で確認すると、**変更禁止範囲・優先順位・例外時の判断方法・再試行上限・エスカレーション条件を 1 つも持っていなかった** (前者 4 節 / 後者 6 節)。「仕様の穴が埋まらない」は規律の緩みではなく、埋める欄が物理的に無かったこと。WO を 12 節固定にし、`status: ordered` での commit (= AI に仕事を渡す行為そのもの) を信号に、記入・**DoD⇔検証方法の 1 対 1 検算**・事前レビューの全件決着・停止条件の数値・**OPEN な未決への非依存**を fail-closed 検査する。**`draft` は止めない** — 起草は思考の場で、そこを止めると checkpoint を保存するために節をノイズで埋める誘因が生まれ、gate が自分の bypass を作る。射程は ADR 0018 と同じく「この commit が運ぶ WO」だけ。
- **実装 *前* の敵対的レビューを工程にした (`pre-review` skill)**。従来のウォーターフォールが成立していた一因は、下流の熟練者が質疑票で仕様の穴を潰していたこと。AI に長時間自律稼働させるほどその経路が失われるので、**独立コンテキストの AI を「仮想下流リーダー」として実装前に使う**。観点は 5 つ固定 (曖昧さ / 既存設計との矛盾 / 未定義の異常系 / DoD をテストだけ通す抜け道 / 停止条件の過不足)。kanban-flow も敵対的レビューを持っていたが**統合サインオフ = 実装後**にしか置いておらず、そこで見つかる穴は既にトークンを払って作られたものの穴だった。指摘の終わり方は `closed` か `deferred:<未決ID>` の 2 つだけで、**表が空 = 未実施も発注を止める** (未実施と「指摘ゼロ」は別物)。
- **上流の品質を下流のテレメトリで測る (ADR 0024)**。kanban-flow は自身の設計文書 14 節で「kanban-flow の失敗は判断ミスであり、機械的には検出できない」と結論して自己改善ループを断念していた。**これは誤り** — 上流の曖昧さは消えず下流へ移動し、エスカレーション・再試行・差し戻し・トークンとして観測される。`accept` が WO ごとに実績を `metrics.tsv` に残し、`scripts/wo-metrics.sh` が**「AI が止まったとき穴は WO の何節にあったか」**を集計する。**エスカレーション 0 は良い値として扱わない** (事前条件が過剰な可能性と区別がつかないので `[ズレ]` 件数と並べて読む)。self-report の限界は `velocity.sh` と同じく出力に明記した (③ の自己適用)。
- **上流の決定は新しい強制機構でなく既存 gate に翻訳して効かせる**。WO 2 節 (作業範囲) → `.bootstrap/lane` / 3 節 (変更禁止範囲) → `.bootstrap/arch`・`retired` / 8+9 節 (DoD と検証方法) → `docs/bootstrap/verification/<branch>.md`。この設計により、上流を統合しても**新規 hook は 3 つ (完全性 1 + 被覆の二層 2) で済んだ**。
- **被覆の判定を編集時と commit 時の二層にした (`hooks/block-commit-if-impl-uncovered.sh`)**。編集時 gate は `Edit | Write | MultiEdit` にしか載らないので、`cat > src/x.ts` / redirect / codemod / scaffolder / `cp` で作られた新規 source 面は被覆の関所を一度も通らなかった (ADR 0017 が lane で通った道と同じ)。**lane gate では代替できない** — `order` は WO の 2 節から `.bootstrap/lane` を作るので、**1 枚も発注していない状態では lane marker 自体が無く lane 関所は fail-open** する。つまり「発注しないまま実装を始めた」という commission が止めたい当の状態だけが素通りしていた。判定対象は `--diff-filter=A` = **この commit が追加する file** だけなので bug fix / refactor は trip しない。統合操作中 (merge/rebase/cherry-pick/revert) は fail-open。
- **未決台帳との突合を「形」から「実在」へ**。`wo_prereview_unresolved` は状態セルの *形* しか見ていなかったので、`deferred:U99` のような **台帳に無い ID への先送り**が決着として通っていた (= 名前をつけずに先送りする、という両前身が共通して禁じていた手そのもの)。4 節の参照先と 12 節の `deferred:` の先が台帳に実在することを検査に足し、charter.md が無いまま未決 ID を参照した場合も落とす (判断材料ごと消えた検査を無音でスキップすると、他の節は効いたままなので「gate は効いている」ようにしか見えない)。
- **発注 gate が読む中身を index の版に修正** (`lib/commit-files.sh` の `commit_file_content`)。「この commit が運ぶ file」を index から取りながら中身を worktree から読んでいたため、部分 stage (`git add -p`) や stage 後の編集で **検査した中身 ≠ commit される中身**になり、完全性検査が fail-open していた。`-a` / `--all` のときだけ worktree が正 (それが `-a` の stage するものだから)。
- **commission を `scripts/doctor.sh` の配備検出に登録**。3 本の gate が vendoring 先で 1 本でも欠ければ `partial`、`charter.md` 不在も `partial` (未決台帳の検査が無音でスキップされる)。commission は CI twin をまだ持たない (ADR 0023) ので、配備漏れを後追いで拾う net が doctor しか無い。`MAINTENANCE.md` の「同期が要る対」に **hook を足したら REQ と hooks/README の発火順も直す** を追加 — 今回の穴自体が「hook を足して REQ を直し忘れた」形だった。
- 新規: `skills/charter` `skills/order` `skills/pre-review` `skills/accept` / `hooks/lib/wo.sh` (WO パーサの単一権威) / `hooks/block-commit-if-wo-incomplete.sh` / `hooks/block-impl-without-wo.sh` / `hooks/block-commit-if-impl-uncovered.sh` / `scripts/wo-metrics.sh` / `templates/docs/bootstrap/commission/` (README + charter.md + wo/TEMPLATE.md) / ADR 0022・0023・0024。hook 数 21 → 24、suite 数 49 → 53。
- opt-in マーカーは `docs/bootstrap/commission/` ディレクトリの存在。**置かなければ何も発火しない**ので既存採用 repo への影響はゼロ。

### Changed

- **README と本体 SKILL の位置づけを「実装専用エンジン」から「発注 → 実装・統合 → 検収の一貫規律」へ改めた**。これが今回の唯一の実質的な代償で、旧 upstream-process が持っていた「管轄 = 詳細設計〜実装〜統合」という分界表は成立しなくなる。記事的に言えば、技術判断と原価判断 (どう分けて渡すか・どこで打ち切るか) が切り離せなくなったことに構造を合わせた。
- `skills/plan/SKILL.md`: **発注済み WO がある場合は `/plan` を発火させない**例外を追加。WO の 1 節 = Step 1、2/3 節 = Step 2、7 節 = Step 3/5 (探索と前提検証は発注側で完了済み)、8/9 節 = 成功条件、12 節 = レビュー済みで、Step 7 の承認も発注 commit の完全性 gate 通過で済んでいる。ここでフル再実行すると探索と承認待ちが二重になり速度だけを削る。`/plan` は「発注者がいない場合のセルフサービス版」として残る。
- `skills/project-bootstrap/SKILL.md`: 「上流 — 自律稼働の事前条件を渡す (commission)」を 1 セクション追加 (常時ロードなので約 35 行に抑えた。実務 skill 4 つはオンデマンド)。docs 表に `docs/bootstrap/commission/` を追加、「迷ったとき」に第 0 項 (停止条件とエスカレーション条件を書いたか) を追加。
- 旧 `upstream-process` / `kanban-flow` はアーカイブ表記にし、後継をこのサブシステムと明記した。git 履歴は残す — 特に kanban-flow の `DESIGN.md` (756 行) は「なぜそうしないか」の一次資料として価値がある。

## [0.32.0] - 2026-07-31

### Added

- **引退した名前 (旧称) の混入を commit で止める gate (ADR 0021)**。これまでこのプラグインが守ってきた「ズレ」は依存方向 (file 間の矢印)・cross-repo 契約 (repo をまたぐ形)・lint (整形と命名規約) の 3 つで、いずれも file 単位・repo 単位だった。**repo の中の「語」のズレは無防備**で、用語集に相当する概念すら持っていなかった。実例: ai-reception で `Intent.typeNo` → `typeId` の改名 (#88) の **1 時間 12 分後**にマージされた別 PR が改名を知らずに `i.typeNo` を参照し続け、型に存在しないので常に `undefined`、`undefined === null` は false、生 JS ゆえエラーも出ず、テスト UI が「#undefined」を 3 日以上表示し続けた。核心は注意不足ではなく**情報の非対称** — 改名を行う PR は改名後の全 file を知り得るが、改名の *後に* 書く人は grep すべき語が在ることを知らない。だから改名者の自己申告では原理的に漏れ、独立した常時稼働の機構が要る。
- **信号は「この commit が新しく足した行」**。ツリー全体を検査すると、marker を置いた瞬間から残存を持つ file に触る全 commit が止まり、行為者に残る逃げ道は (a) lane を出て一括改名 (b) marker の行を消す の 2 つになる = **gate が自分の bypass を作る** (memory `feedback_gate_signal_and_failmode`「塞ぐ と 塞がれても困らなくする は対で設計する」)。commit が答えるべきは自分が新しく持ち込んだ分だけ — ADR 0018 が lint に下した判断 (「信号はツリーでなくこの commit」) を名前に適用した同型の決定。
- **edit 時 gate は意図的に作らない** (arch の 2 層構成を真似ない)。「その行が追加されたか」は PreToolUse では計算できず、`new_string` の旧称は無関係な書き換えに巻き込まれた既存分かもしれない。さらに**改名操作そのものは旧称を `old_string` 側に置く**ので、素朴な edit 時検査は**やらせたい改名を止める**。commit 関所なら sed / formatter / script 経由の書き込みも同時に捕まる (ADR 0017)。
- **蓄積した残存は `scripts/doctor.sh` が語ごとの件数で可視化する** (status は落とさない・block しない)。gate が追加行だけを見る選択は、既存の残存を**意図的に射程外に置く**ことなので、射程外が「見えない」になってはいけない (③ 配備の可視化の自己適用)。恒久的な nag は marker 削除の動機になるので advisory に留める。gate = 新しく持ち込んだ乖離 / doctor = 蓄積した乖離、の分業。sweep は 1 session 30 語で打ち切り、**打ち切った語数を出力に明示する** (黙って切ると「監査したという記録だけが残る」失敗になる)。
- **「重複」(同じ概念に 2 つ目の定義) の検出は作らない**。同一概念かの判断は既約で、かつ**この検査が実在の問題を見つけた実例がまだ 1 件も無い**。実例のない検査を足すと検査自体が増殖する (kanban-flow の audit skill が自分に課している規則を輸入)。代わりに AI の癖⑩ と `templates/CLAUDE.md` のセルフチェック 2 行に留め、**昇格条件 (実例が 1 件出たら機械化を検討) を ADR に固定**した。
- **AI の癖に 10 個目**: 「改名を知らずに古い名前で書き続ける / 既にある概念に 2 つ目の名前を作る」。癖② (存在しない API の捏造) とも癖⑤ (既存パターン無視) とも別 — **旧称は "存在した" ので記憶にも文脈にも残り、もっともらしく書けてしまう**。
- **行単位の opt-out `bootstrap-retired-ok` (ADR 0021 決定⑤)**。dogfood で判明: 除外は「文書ファイル」(`*.md` / `docs/**` / `CHANGELOG*`) であって「文書的な記述」ではないので、**コード内のコメントと test fixture は検査される** — 本 repo で実例の語 `typeNo` を登記したら、この gate 自身の解説コメントと fixture がヒットした (PR #24)。これを放置すると行為者に残る手段は「marker の行を消す」か「scope-glob でパスごと除外」で、**どちらも問題より広く、しかも設定ファイルの中で不可視に起きる** = 決定① が塞いだ「gate が自分の bypass を作る」形が別の入口から戻る。対の逃げ道として、その行に `bootstrap-retired-ok` と書くと**その 1 行だけ**除外する (eslint-disable-line と同じ形)。**コメントを構文で除外する案は却下** — 最初の `//` で切ると文字列中の `"http://host/typeNo"` を無音で飲み込み、無音の検出漏れはこのプラグイン最悪の fail-mode。pragma は diff に残るのでレビューで見え、marker への不可視な編集より厳密に良い。block メッセージでは「名前を直す」を第一・pragma は最後で条件つきに提示する (助言が隠蔽を促さない)。doctor の残存 sweep も同じ規則に従う (`git grep -l` では pragma を読めないので行を取ってから file に畳む — gate が通す行を doctor が数えると根拠なき nag になり、恒久 nag を黙らせる最短手は marker 削除になる)。
- **CI net を本 repo にも恒久配線し、実 PR で赤→緑を実測した** (PR #24)。① marker 不在 = 緑 (workflow が走り誤検知しないことの確認) → ② probe + marker で **赤** (原因行を名指し) → ③ 撤去で **緑**。さらに probe 行を marker 登記の **前** に commit することで、**ローカル関所が射程外にする「既に commit 済みの追加行」を CI net が捕まえる**ことを実証した — 改名が後から起きる実際の順序であり、CI net が飾りでないことの直接の証拠。
- 新規: `hooks/lib/retired-terms.sh` (engine) / `hooks/block-commit-if-retired-term.sh` (gate) / `scripts/retired-check.sh` (CLI + CI net) / `templates/ci/bootstrap-retired.yml` / `templates/.bootstrap/retired.example` / `docs/decisions/0021-retired-name-gate-at-commit-chokepoint.md`。hook 数 20 → 21、suite 数 46 → 49。

### Changed

- `hooks/lib/commit-files.sh` に **`commit_stages_all`** を切り出した。`-a` / `-am` / `--all` の判定を lane gate・lint gate・retired engine の 3 者で共有する — 2 つ目のコピーは、それが書かれた理由そのもの (`-m all` を誤って sweep 扱いする形) で drift し、緩い側が無音の穴になる。
- CI net は**三点差分** (`origin/<base>...HEAD`) を使う。二点だと base 側で行われた改名を「この branch が旧称を再導入した」と誤読し、他人の作業で PR が赤くなる (CI が hook より厳しくなると修正の動機が歪む)。この誤読は `tests/hooks/retired-check-cli.test.bash` が pin している。
- `scripts/doctor.sh`: `retired` を採用 marker として検出 / 有効行 0 の marker を `partial` (宣言だけで no-op) / vendoring 時の必須 hook に追加 / 残存 advisory。

## [0.31.0] - 2026-07-30

### Changed

- **docs 成果物を `docs/bootstrap/` フォルダ 1 つに集約した (ADR 0020)**。ADR 0015 が repo root の 6 マーカーを `.bootstrap/` にまとめたのと同じ整理が `docs/` 側に残っていた: `sprint/` `verification/` `handoffs/` `incidents/` が採用 repo の `docs/` 直下にプロジェクト自身の doc と兄弟で並び、「どれが道具の作業面か」が名前から読めなかった (dogfood の marketing-app では kanban-flow の `requirements.md` / `glossary.md` / `design/` と literally 隣接)。4 つを **`docs/bootstrap/<name>`** へ移す。**`docs/decisions/` は動かさない** — ADR は一般的な工学慣習であってこのプラグインの成果物ではなく、他ツール (kanban-flow) も同じ場所に書く共有面なので、行き先を分けると 1 repo の決定記録が 2 系統に割れる。囲うべきは道具の作業面であって、成果物の正本ではない。
- **後方互換は「新優先・旧 fallback」の単一 resolver (`hooks/lib/resolve-docs.sh`)**。ここは ADR 0015 より危険度が高い — 各 gate の opt-in 判定は**ディレクトリの存在**で、flag day で移すと採用済み repo は plugin 更新の瞬間に sprint / review / verification / wip / 未隔離編集の 5 gate が**一斉に無音で fail-open** する (memory `feedback_gate_distribution_coverage` が最も嫌う破綻)。`resolve_docs_dir` が `docs/bootstrap/<name>` を優先し `docs/<name>` に落ちる。両方在れば新が勝つ。どちらも無ければ新 canonical を返すので `[ -d ]` の不在判定は従来どおり。旧読みは撤去条件つきの移行補助 (全 dogfood repo の移行完了で削除、ADR に明記)。
- **block message も解決結果に従う (`resolve_docs_label`)**。旧レイアウトの repo に `docs/bootstrap/sprint/.gate` へ記録しろと案内すると人は空ディレクトリへ送られ、そこに書いた記録は gate に読まれない (案内と強制の不一致 = 別種の無音破綻)。sprint gate・verification gate・drift advisory の各メッセージが実際に解決したパスを名指しする。
- **gate の自己状態の書き込み例外 (`docs_state_face`) だけは resolver を通さず両レイアウトを無条件マッチ**。この述語はまだ存在しない path を分類する (PreToolUse は書き込み前に走る) ので、新レイアウトを作る最初の `board.json` を書く瞬間には `docs/bootstrap/sprint/` がまだ無く、resolver は旧側に倒れて**その file 自身を block する**。自分が所有する path の fail-open 例外を広げるだけなので両マッチが厳密に安全側。
- **`scripts/doctor.sh` が旧 flat レイアウトの残存を advisory で可視化する**。ISSUE (partial) にはしない — 旧レイアウトは互換読みで gate が効いており「整合しない」わけではないため。だが旧読みは撤去予定なので、残っていること自体が無音であってはならない。
- 配線先: 5 hook (`block-unplanned-feature-build` / `block-uniso-main-edit` / `block-over-wip-parallel` / `block-unreviewed-merge` / `block-merge-if-verification-unclosed`)、5 lib (`lane-set` / `verification-plan` / `cross-repo-contract` / `verification-drift` / `verification-ci-check`)、`scripts/doctor.sh`。直書きパスは全廃 (= 信号 drift 防止、ADR 0005 guard 1 と同じ思想)。`templates/docs/` と本 repo 自身の docs も新レイアウトへ移動 (dogfood)。
- **歴史的記録は書き換えない** — CHANGELOG・ADR 0001〜0019・incidents / handoffs の本文は書かれた当時のレイアウトを記述した日付つき記録なので path 表記を遡らせない。書き換えたのは live な面 (README / hooks / skills / templates / scripts) だけ。

### Added

- `hooks/lib/resolve-docs.sh` — docs 成果物の所在の単一権威 (`resolve_docs_dir` / `resolve_docs_label` / `docs_state_face`)。純 bash・jq 非依存。
- `docs/decisions/0020-consolidate-docs-artifacts-into-bootstrap-dir.md` — 上記の決定・後方互換・撤去条件・代償 (半移行状態は fail-closed 側に倒れる)。
- **テスト: 新レイアウトのカバレッジを 8 スイートに追加** (専用 suite `resolve-docs.test.bash` 24 assertion + 各 gate の新レイアウト発火/解除/半移行ケース)。既存 fixture は全て旧レイアウトを組むので、そのままでは**後方互換しか証明しない**。resolver を旧 path 固定に潰す mutation で 11 suite が落ち、各 gate の「exit 2 期待 → 0」= 無音 fail-open が確実に検出されることを実測。suite 数 45 → 46。

## [0.30.0] - 2026-07-10

### Added

- **git 呼び出し検出の単一権威 `hooks/lib/git-invocation.sh` を新設 (ADR 0019)**。「このコマンドは `git <subcommand>` を呼ぶか」を regex でなく token walk で判定する: git グローバルオプション (`-C` / `-c` / `--git-dir` / `-P` 等。値を取るものは次トークンごと skip) を越えて subcommand に到達し、path-prefixed git (`/usr/bin/git`, `./git`) と compound command の全 segment・subshell/backtick を扱い、未知の `-*` は検出側 (fail-closed) に倒す。全 Bash gate (commit 系 5 本 / push 2 本 / merge 2 本 / add-all) がこれに載り、detector regex の継ぎ足しで再発してきた「文字列 proxy の穴」クラス (incident 2026-05-25 と同型) を 1 ファイルに閉じた。既知の限界 (quoted git-head/subcommand token・`sh -c "…"` 内は under-detect し得る = full shell parser 無しの既約 limit、旧実装と同一穴で退行ではない) は header と verification plan に正直に明記し、net は commit 関所 + サーバ側 (ADR 0012) が持つ。
- **lane 集合の単一権威 `hooks/lib/lane-set.sh` を新設**。2 つの統合関所 (review / verification) に verbatim 重複していた「活性 board ∪ linked worktree」の組み立て (~40 行) を抽出し、gate 信号の drift を封じた (ADR 0005 guard 1 と同じ思想)。
- **直接テストの無かった lib 4 本 (`commit-files` / `lane-match` / `detect-test-suite` / `source-face`) と唯一 entry テストの無かった hook `inject-action-memory.sh` に専用テストを追加** (suite 38 → 45)。新テストが `source-face.sh` の実バグ (repo-root `tests/**` を source 面と誤分類する root anchor 欠落 = over-block 穴) を検出し修正。
- **dogfood: `bootstrap-doctor` workflow を自 repo の CI に適用** (`.github/workflows/bootstrap-doctor.yml`) — 配る gate を自分でも被る。適用時に template `templates/ci/bootstrap-doctor.yml` の実バグを発見・修正 (下記 Fixed)。

### Changed

- **常駐 skill と README の重複を単一権威 + ポインタに畳んだ (規範消失ゼロを機械検査つきで)**。`project-bootstrap` skill (毎セッション常駐) を 41.3KB → 28.9KB (**-30%**): 並列判定 / wip_limit / `.gate` 記録形式は `sprint-plan` skill を、継ぎ目・オラクル doctrine は `verification` skill を権威に。`verification` skill の 6th/7th seam の 3-4 重記述を権威節 1 箇所に一本化。README を 38.9KB → 25.2KB (**-35%**): 提供物表を「1 行要約 + 正本ポインタ」に再構成。検査: 変更前の hook/lib/script/ADR/incident への全参照 54 件が変更後も権威箇所に残存することを grep で機械確認 (adversarial レビューが prose 規範の消失 1 件 = 「Class A/B は同じ表層形」を検出 → 復元済み。名前 token grep は prose 規範を覆わない教訓を plan に記録)。
- **advisory を正直に表示**: `plan` skill の「実行中 Edit/Write 禁止」に「hook 強制ではなく advisory — downstream gate が居るのは新規 source 面作成と merge のみで、plan 中の既存 file への Edit を止める機構は無い」を明記。`integrate` skill の post-merge 全スイートを「hook の強制は pre-merge まで / post-merge は skill 手順 (advisory) + サーバ側 CI required check が backstop (ADR 0012)」に書き分け。強制されている風の advisory を残さない。
- **marker 表記を `.bootstrap/<name>` (フォルダ形、ADR 0015) に統一** — README / skills / templates の旧 flat 表記を更新し、後方互換の注記を各 1 箇所に集約。

### Fixed

- **保護 push gate の P0 素通り 2 件を封鎖 (2026-07-10 全体監査で実測、ADR 0019)**。(1) `git -C /repo push origin main` / `git -c k=v push` / `git --git-dir=.git push` / `git -P push` が detector と tokenizer の両方を素通りし **保護 branch への push が exit 0** だった。(2) `git push --all` / `--mirror` は destination 0 件 → current-branch 判定に落ち、feature branch 上から保護 main を含む全 branch が素通りしていた — 全 local branch を destination として展開する fail-closed に変更 (`block-stale-write-to-protected.sh` の同型穴も併修)。adversarial レビューが敵対入力 20+ 形態で封鎖を実証し、legit flow (`push origin feature` / `-u` / `--force-with-lease origin feature`) の over-block ゼロも確認。
- **commit 系 gate 5 本 (test / lint / arch / lane / cross-wip) の detector が `/usr/bin/git commit` / `./git commit` / `git -C` / `git -c` 形を見逃していた** — push/merge 側にだけ入っていた path-prefix 許容が commit 側に未展開だった。単一権威 walker への載せ替えで封鎖。
- **`block-add-all.sh` の stash 判定に残っていた greedy sed を segment walk に移行** — `git stash && echo done` のような compound command 中の bare stash が素通りしていた (merge/push lib で潰したのと同じクラスの残置)。
- **hook 入力 JSON の string field 抽出の fail-open 穴を封鎖**: `file_path` / `cwd` / `transcript_path` を旧式 `grep -oE '"key"[^,}]*'` で抽出していた 8 call site が、path 中の `,` `}` / escape で途中切り → 無音 fail-open していた (incident 2026-05-25 で `command` に対して潰したのと同一クラス)。`parse-command.sh` の decoder を `parse_json_string_field <key>` に汎用化して移行。
- **marketplace.json の記述 drift を解消** — 「19 hook」のまま `block-out-of-lane-commit` (0.29.0) が漏れていた説明文を plugin.json / 実体 (20 hook) と同期。README / templates の同型 stale 記述も一掃。
- **template verification-gate の `PLUGIN_REF` default を動く `main` から release tag `v0.29.0` に pin** (header の警告と default が矛盾していた)。plugin 更新時に pin を追従させる注記つき。
- **bootstrap-doctor template の exit code 捕捉バグ** — GitHub Actions の `bash -e` 下で partial (exit 2) が捕捉行の前に job を落とし `::error` 注釈が出ない / 非 `-e` shell では crash (exit 1) が緑に化ける形だった → `|| status=$?` 形に修正し 3 経路 (ok/partial/crash) を実証。
- **`setup-server-enforcement.sh --check` の固定 `/tmp/_bp.json` を `mktemp` + trap 掃除に**。
- **全行 CLOSED の verification plan 4 件を `docs/verification/archive/` へ移動** (ADR 0007 の終端責務からの drift。単一 lane で main 直行した plan が integrate の archive サイクルを経ず滞留していた)。

## [0.29.0] - 2026-07-10

### Added

- **lane 強制の commit 側関所を新設 (`hooks/block-out-of-lane-commit.sh`) — 全ての書き込み方式が必ず通る一点に関所を移す**。lane 強制はこれまで `Edit | Write | MultiEdit` matcher の `block-out-of-lane-edit.sh` にしか載っておらず、**Bash 経由の書き込みは関所を一度も通らなかった** (`biome format --write` / `prettier --write` / `sed -i` / codemod / `python` / `>` redirect は編集時 hook を素通りする)。書き込み方式 (`--write`, `-i`, リダイレクト …) を列挙して塞ぐのは whack-a-mole で新方式が出るたび穴が空くので、**全方式が必ず通る行為 = `git commit`** に関所を置く (memory `feedback_gate_distribution_coverage`「関所は特定方式の痕跡でなく全方式が必ず通る行為に置く」の commit 版)。編集時 hook は速い feedback のため残し、本 hook を取りこぼしの網とする**二層構成**。lane worktree での commit に載る file (`git diff --cached --name-only`、`-a`/`--all` 時は tracked 未 stage 変更も) が全て lane glob の中であることを要求し、外れる file が 1 つでもあれば `exit 2`。fail-open: lane marker 不在 (sprint 非適用) / 非 commit / 非 git / index が空 (git 自身が拒否) / 統合操作中 (`MERGE_HEAD`・`CHERRY_PICK_HEAD`・`REVERT_HEAD`・rebase — lead の conflict 解決は定義上 lane を跨ぐ)。fail-closed: コマンド解析不能 ([`lib/parse-command.sh`](hooks/lib/parse-command.sh) の契約、他の commit 関所と同型)。根拠 = marketing-app 2026-07-09 incident M5 (`ui-leaf-producer-unwired`、lane worker が `biome format --write` で lane 外の file を書き換えどの hook も鳴らなかった)。`hooks/hooks.json` に配線 (Bash 群、`block-arch-violations` の後)、`scripts/doctor.sh` の sprint REQ に追加 (= 未配備を partial で可視化)。default hook 数は 19 → **20**。
- **lane 照合の共有エンジン `hooks/lib/lane-match.sh` を新設 — 編集時と commit 時の gate が glob 解釈で drift しないよう単一権威に集約**。`.bootstrap/lane` の glob 照合 (`lane_allows`) を `block-out-of-lane-edit.sh` から抽出し、別 worktree 判定 (`lane_owning_worktree`) と併せて lib 化。編集時 (`block-out-of-lane-edit`) と commit 時 (`block-out-of-lane-commit`) が別々に glob を解釈すると片方だけが緩い穴になるため単一権威にする (= `detect-test-suite.sh` を test/merge 両関所で共有するのと同じ思想、ADR 0005 guard 1)。

### Changed

- **lint gate の信号をツリー全体からこの commit が運ぶ file に絞る (`hooks/block-commit-if-lint-fails.sh`, ADR 0018)**。`block-commit-if-lint-fails.sh` は `npm run lint` / `ruff check .` 等を **cwd でツリー全体に対して** 走らせていたが、git worktree には repo の全 tracked file が複製されるので、lane worker は **自分の所有しない file の lint debt** で commit を止められ、lane の中に正当な remedy が無く lane を出て直す動機を gate 自身が作っていた (marketing-app 2026-07-09 incident M5、L2 が `biome format --write` で lane 外を書き換えた動機側の原因)。信号は判定対象そのもの (= この commit が運ぶ file) であるべきでツリーの歴史的 debt ではない (memory `feedback_gate_signal_and_failmode`「gate は判定対象そのものを信号にする」)。今は `git diff --cached --name-only` (+ `-a`/`--all` 時は tracked の未 stage 変更) が返す file だけを lint し、**削除された file・その linter が扱わない拡張子の file は渡さない** (存在しない path / 非対象拡張子で linter が誤 block するため)。commit がこの linter の扱う file を 1 つも運ばないなら判定対象が無いので素通し。**file 引数を取れない linter (`golangci-lint run` / `cargo clippy` は package 単位) は whole-tree のまま fail-closed で残し緩めない** — ただし失敗が lane 外の file 由来なら「lane を出て直すな (越境は別 gate が block)、lead に上げろ」と message で明示 (案内と強制を一致)。`npm run lint` は script 文字列から tool を同定し **既知の path 対応 tool (`eslint` / `biome` / `oxlint` / `prettier`) のときだけ** scope する。`next lint` のように file 引数で意味が変わる script は同定せず whole-tree に落とす (誤 scope は**存在しない lint 失敗を発明して誤 block する**ため)、tool 解決は `node_modules/.bin/<tool>` 優先で解決不能なら whole-tree fallback。新エンジン `hooks/lib/commit-files.sh` (`commit_files_from_cmd` = 「この commit が運ぶ file」の単一権威。`-a`/`--all` の扱いが lint 関所と lane 関所 `block-out-of-lane-commit.sh` で drift しないよう共有、ADR 0005 guard 1) と `hooks/lib/lint-scope.sh` (`lint_script_tool` / `lint_scoped_base` / `lint_ext_ok`) を新設。**incident 自身の診断は棄却した** — M5 は原因を「commit gate が worktree でなくメインリポツリーで lint を走らせる」と記述したが、実査 (一時 repo + lane worktree で再現) の結果 lint は cwd = lane worktree の中で走っており **cwd は正しく、直すべきは信号の粒度 (whole-tree) だった** (incident に訂正を記録)。**代償を正直に明示**: 既存のツリー debt はそれを触らない commit を止めなくなり、cross-file な lint 規則 (未使用 export の検出など) は commit 単位では scope できない — ツリー全体の清潔さは CI の whole-tree lint が backstop。default hook 数は不変 (新規は lib 2 つ、hook entry 追加なし)。

### Fixed

- **`block-out-of-lane-edit.sh` の「別 worktree への絶対 path 書き込み」fail-open 穴を塞いだ — 解析不能 → fail-closed / 根拠不在 → fail-open の自 repo の原則に整合させた**。worktree 外の絶対 path を編集する行為は一律「判断不能」として fail-open (`exit 0`) していたが、これは判断不能ではない — その path が**同一 repo の別 worktree** (典型的にはメインリポ) の中に在るなら、定義上「この lane の外」だと**確定できる**。今は両 worktree root を名指しする message つきで `exit 2` で block する。どの worktree にも属さない path (`/tmp` scratchpad / `~/.claude` 等) は判断材料が無いので従来どおり fail-open。lane worker がメインリポの file を絶対 path で直接書く事故がここを素通っていた (marketing-app 2026-07-09 incident M5)。判定は新 lib `lane-match.sh` の `lane_owning_worktree` に集約。

## [0.28.0] - 2026-07-06

### Added

- **AI のハードコード傾向を 2 クラスに分け held-out oracle を verification に据える (ADR 0016)**。重大インシデントは無いが「AI はハードコードしがち」を先回りで潰すため、`/deep-research` (read-only 外部オラクル腕) で「AI 生成コードの品質が低いと言われる理由」を引用付き外部一次資料化 (arXiv 2403.08937 / 2503.06327 / 2603.27130 / 2510.20270 / 2511.18397 / METR 2025-06)。ハードコード傾向は性質の異なる 2 クラスに割れる — **Class A = 能力限界** (プロンプト例への過適合 = Prompt-biased code / 中身のない stub = Wrong Logic / secrets・env 埋め込み、**静的に検出しうる**) と **Class B = 報酬ハック的テストゲーミング** (special-casing = テスト入力を検知して期待値を返す / grader・`==`・conftest の monkey-patch / `sys.exit(0)` で harness を exit 0 脱出、RL 報酬構造から学習されることが実証済み、**静的に検出しづらい**)。実測で最も効く緩和は **held-out test** (判定スイートを実装者に見せない/触らせないとチート率がほぼゼロに)。`verification` skill に **7 番目の seam「オラクル捕獲 / テストゲーミング」** を追加 (6 番目「緑の嘘」= テストが**弱い**受動的欠陥と区別、7 番目 = 実装が**能動的に**可視オラクルを騙す)。緩和として held-out oracle (判定を実装 lane の編集面の外に置く。関所実走スイートは部分的 held-out だが同 lane 共著なら崩れる) + metamorphic (入力摂動で決め打ちを壊す、Class A 例過適合と Class B special-case の両方に効く) を Step 3 の技法表・kill-question・doctrine に据える。Class A の静的半分 (secrets/env) は独自スキャナを内蔵せず gitleaks 等を `.bootstrap/lint` gate + CI に足す推奨経路に (再発明・誤検知回避、`merge-targets`/`protected-branch` と同じ「未レビュー matcher を持ち込まない」規律)。**新しい block は作らない** — 「special-case したか」は AI が自己発行できる ack で偽装される既約な理解 (ADR 0001/0010) ゆえ可視化 doctrine で扱う。README (提供物表 + 見落としがち機能 + プレーン語解説)、CHANGELOG を更新。
- **held-out / metamorphic 盲点の SessionStart advisory を追加 (ADR 0016 axis 3、機械化 (a))**。`verification-drift.sh` に **axis 3** を追加: plan に `kind=gameable` 行 (実装が special-case/ハードコードで通り抜けうると著者が宣言) があるのに `kind=metamorphic` 行 (入力摂動で決め打ちを崩すオラクル。held-out はその構造的代替) が無い時、doctor が盲点 advisory を出す。`async`→`monitor` (axis 2) と同型・同じ controlled-vocab keying (prose 走査しない = 「hardcode/game」を含む prose では鳴らない)・source-face gated・never exit 2。`verification-plan.sh` の kind 語彙に `gameable`/`metamorphic` を追加、`verification` skill が両 kind と裏打ち規律を教える。**当初案の「impl+test 共著 delta の自動発火」は却下** — TDD が全 lane で共著するので自動発火は advisory bloat になる。宣言駆動 (`gameable` フラグ) に精緻化して低ノイズに (代償: 宣言しないと鳴らない、`async` 未宣言と同じ既知の限界)。tests/hooks/verification-drift.test.bash に axis 3 の 5 ケース (発火/裏打ちで沈黙/prose 非発火/docs-only 沈黙/advisory=exit0) を追加。
- **secret-scan の CI template を追加 (ADR 0016 Class A 静的半分の恒久層、機械化 (b))**。`templates/github/workflows/secret-scan.yml` — AI がしがちなハードコードのうち**静的に検出できる半分** (secrets/env、実測で AI は人間の約 2 倍埋め込む: arXiv 2603.27130) を PR/push で検出する opt-in gate。ADR 0016 の判断どおり独自スキャナは内蔵せず既存 `gitleaks/gitleaks-action@v2` に委譲 (再発明と「未レビュー matcher を consumer に持ち込む」事故クラス・誤検知が正データを隠す fail-mode を回避)。leak 検出で check を fail、required status check 化で bypass 不可にできる。GITLEAKS_LICENSE は GitHub org 所有 repo のときだけ必要。`templates/ci/README.md` に catalog エントリを追記。plugin lib は vendor しない self-contained (`bootstrap-*.yml` gate 群とは別種ゆえ `templates/ci/` ミラーは作らない)。

## [0.27.0] - 2026-06-27

### Changed

- **root の opt-in マーカーを `.bootstrap/` フォルダに集約 (ADR 0015)**。採用 repo の root に最大 6 個 flat に散らばっていたマーカー (`.bootstrap-arch` / `-protected` / `-lint` / `-wip` / `-actions` / worktree-local `-lane`) を `.bootstrap/<name>` 配下にまとめ、直下の散らかりを解消。設計思想は不変 (存在=有効・各 hook は自分のマーカーだけ読む・単一設定ファイル化は fail-mode SPOF になるので不採用)。単一権威 `hooks/lib/resolve-marker.sh` が `.bootstrap/<name>` (新) を優先し `.bootstrap-<name>` (旧) に**後方互換 fallback** (両方在れば新が勝つ) するので既存採用 repo は移行不要 (flag day なし)。全 hook / `scripts/arch-check.sh` / `scripts/doctor.sh` / `lib/resolve-wip-limit.sh` / `lib/action-gate.sh` を resolver 経由に統一 (直書きパス廃止)。`templates/.bootstrap/` フォルダ雛形 (`cp -r` で一括配布)、CI vendor 手順に `resolve-marker.sh` を追加。旧 path 撤去条件は ADR 0015 で bound (全 dogfood repo 移行完了後)。

## [0.26.0] - 2026-06-26

### Added

- **本番デプロイ時の「完了照合」inject (ADR 0014)**。同一セッションで出た裏表の 2 incident (appo-followup 2026-06-26: ① 複数文言の明示指示を自分の都合のよい解釈に置換し、各文言と実装の照合をせず「完了」と虚偽報告して誤仕様を本番デプロイ / ② 逆に明示指示を実行せず `AskUserQuestion` で押し返した) を根に。既存 `prod-deploy` action-key の `action_default_memo` 空欄を埋め、(1) 各指示文言を実装と逐語照合 (2)「〜のような既存機能」は実データ挙動を先に確認 (3) 解釈を置換した重要機能は二択メニューでなく出力モックで確認、を本番デプロイの瞬間に **registry 未 arm でも常時発火** (data-backfill に続く 2 つ目の普遍 floor)。`verification` skill に partial-update の absent/empty 混同 seam (往復テスト) + 「設計で消せるか先に問う (構造>規律/操作分離)」+ 完了前 kill-question を追記。`incident` skill に過小スコープな read 対症で閉じる失敗兆候 (write 真因+兄弟フィールド横スイープ+継ぎ目テスト) を追記。block しない可視化 (完了照合は既約 = ADR 0001)。ADR 0013:46「prod-deploy は opt-in」を更新。
- **README に開発者向け運用ガイドを追加**。slash コマンド一覧 / 自動発火する瞬間 / あなたを止める hook と対処 / 手で叩く CLI / opt-in 設定ファイル / 見落としがちな機能 (trust ladder・本番操作メモ・cross-repo 契約・verification の HUMAN 行・サーバ側 enforcement の有効化手順) を、機能カタログ (提供物表) とは別にプレーン語で。

## [0.25.0] - 2026-06-25

### Added

- **サーバ側 enforcement への二層化 (ADR 0012)**。ローカルの merge gate は `git merge` しか捕まえられず GitHub の「Merge pull request」ボタン (サーバ側) を素通りする穴を、deep-research で外部一次資料化した 3 穴 (Merge ボタン経路 / branch protection のデフォルト admin 非適用 = 単一 orchestrator の自己素通り / lane 限定 pre-merge の stale 統合破壊) とともに塞ぐ。同じ判定 (`verification-plan.sh` 単一権威) を CI で再実行する `hooks/lib/verification-ci-check.sh` (merge gate の CI twin)、`templates/github/workflows/verification-gate.yml` (配布) + `.github/workflows/verification-gate.yml` (dogfood)、`scripts/setup-server-enforcement.sh` (`gh` で required checks `verification-closed`+`hooks` / `enforce_admins=true` / PR 必須・人間承認 0 を冪等設定、`--check` で admin 素通り監査)、`templates/github/ruleset.json` (複数 repo 横展開) を追加。ローカル hook は「速い feedback 層」に再定義 (権威はサーバ側)。
- **データ修復時の「修復か仕様か」意図確認 inject (ADR 0013)**。AI が「値の欠落=バグ」と推測し domain owner 確認前に多段 backfill を組んだ incident (appo-followup `demo-proposal-lane-cv-notify-misfire`) を根に。100% 系統的な欠落は defect でなく **spec の徴候**・同じ値でもレーンで妥当性が真逆・意図のオラクルは data でなく人間。`inject-action-memory` (ADR 0010) の CLOSED enum に `data-backfill` を追加 (backfill/data-migrate スクリプト名 + `prisma db execute` + sql-client inline UPDATE/DELETE + knex/sequelize/typeorm/alembic を検出)。`action_default_memo` で plugin 所有の普遍 doctrine を **registry 未 arm でも常時発火** (opt-in を 1 キーだけ緩和)。`verification` skill に修復前 kill-question を追記。block しない可視化 (意図確認は既約 = ADR 0001)。

### Fixed

- **`tests/hooks/bootstrap-session-doctor.test.bash` の CI サイレント赤を根治**。`setup_repo` の `git init` が runner の `init.defaultBranch` を尊重し、ubuntu CI が `master` を既定にするため、verification-drift ケースが `master.md` を探す一方テストは `main.md` を書き込み不一致 → CI のみ false FAIL になっていた (main で気づかれず赤のまま)。`git symbolic-ref HEAD refs/heads/main` でブランチを決定論的に固定。

## [0.24.1] - 2026-06-25

### Fixed

- **0.24.0 で生じた doc 台帳 drift を解消** (リリース後監査で検出)。`README.md` の表に ADR 0009-0011 行 / lib 行 (`action-gate.sh`・`cross-repo-contract.sh`) / template 行 (`bootstrap-actions.example`・`contracts.example`) を追加。`hooks/README.md` の Hook N (verification-unclosed gate) に cross-repo 契約拡張 (ADR 0011・`lib/cross-repo-contract.sh`) を追記、harness-contract 表の `cwd` 行に `inject-action-memory` を追加 (実コードで cwd 依存を確認)。`docs/decisions/0007` 末尾に D4 (async/silent-skip seam) の amendment 逆参照を追加 (0011 にしか無く dangling だった)。`skills/integrate/SKILL.md` Step 4 に契約 tag の merge precondition を追記。`docs/decisions/0008` の "17 hook" に時点注記 ((当時; 0.24.0 で 19))。
- **`integrate` skill の archive 手順を git-mv の落とし穴に対して恒久対策**。`git mv` は index の既存 blob を rename して運ぶため、`status` を `done` に編集した board を未 stage のまま `git mv` すると編集が落ち、archive が `status: todo` のまま commit される実バグ (2026-06-25 の 2 sprint で連続発生) を踏まえ、Step 5 に「編集 → `git add` → `git mv`」の順序を必須として明記。reviews / verification plan の status 編集 + mv 経路にも同じ罠が効く旨を併記。

## [0.24.0] - 2026-06-25

appo-followup の incident 群から抽出した bootstrap 側欠陥 backlog の残り 4 件 (D1-D4) を、sprint flow 自体を dogfood して実装・統合 (sprint-plan で 3 disjoint lane に分解 → 隔離 worktree で並列 TDD → adversarial AI レビュー → integrate)。default hook 数は 17 → **19**。

### Added

- **D1 / trunk 鮮度 gate (`hooks/block-stale-write-to-protected.sh`, ADR 0009)**。stale checkout から trunk へ直 push する事故 (prod migration が 24-commit 遅れの tree から走った 2026-06-16、rebase が deploy commit を落とした事例) を、push の瞬間に **timeout 付き fetch + behind 判定**で塞ぐ。信号は `.bootstrap-protected` でなく `repo-drift.sh` の `drift_main_ref` が解決する **trunk branch** — `block-push-to-protected` (PR フロー強制) とは直交 (こちらは鮮度強制)。新エンジン `fetched_behind_count` を `repo-drift.sh` に追加 (online 鮮度の単一権威、offline doctor は不変)。fail-open: 非push / offline・fetch 失敗 / trunk 非該当 / behind==0。任意の本番スクリプトは決定的痕跡が無いため非対象 (SessionStart advisory に残す、ADR 0009 に明記)。根拠 incident 2 件を `docs/incidents/` に起票。
- **D2 / 再発 action での memory 注入 (`hooks/inject-action-memory.sh` + `hooks/lib/action-gate.sh`, ADR 0010)**。memory に解決策があるのに同じ事故を繰り返す問題 (deploy-author bug が 7 回再発) に対し、**block せず** (exit 2 しない) repeat-prone action の直前に該当 memory を additionalContext 注入する。matcher は共有 tokenizer + plugin 所有の controlled-vocab action-key enum (per-entry 正規表現を持たない = string-proxy 回避)。registry は opt-in (`.bootstrap-actions`、`templates/bootstrap-actions.example`)、TTL は安全側、`doctor.sh` が registry の orphan を surface。
- **D3 / cross-repo 契約 drift gate (`hooks/lib/cross-repo-contract.sh` + `block-merge-if-verification-unclosed.sh` 拡張, ADR 0011)**。sibling repo と暗黙共有する schema/値域がズレて全 CV 拒否 / silent no-op になる事故に対し、契約面を `docs/verification/contracts` で宣言し、**lane branch の delta** (cwd/HEAD でなく merge-base base..lane) が契約面に触れたら、その契約の **`[contract:<id>]` アンカー tag つき closed 行**を要求し、**consumer 側テストを実行**して赤なら block (自由文 PASS で閉じさせない、自動不能は HUMAN)。consumer 側のみ (sibling を diff しない = sibling 不在マシンで誤発火しない)。契約 id 照合は当初 raw substring (`booking` が `booking-payload` で誤 close する穴) だったが、レビューで検出しアンカー tag 照合に修正。
- **D4 / 非同期・silent-skip の verification doctrine (ADR 0007 amend)**。read-back doctrine は同期前提だったため、cron の無音 skip (リマインダ未送) や heartbeat 生存下の queue 停止が射程外だった。`skills/verification/SKILL.md` に第 5 の継ぎ目 (filters/skips/drops に観測信号なし) と `kind=monitor` の外部オラクル行を追加、Step-6 を必須化。`verification-plan.sh` に `kind=async` 語彙 + `vplan_has_kind`、`verification-drift.sh` に doctor 分岐 (async 行ありで monitor 行なし → advisory)。**controlled-vocab の kind 欄だけをキーにし prose を走査しない** (DROP 行の 'drop' で誤発火した過去を踏まえる)。
- **hook 台帳を 17 → 19 に更新** (`plugin.json` / `marketplace.json` / `README.md` / `hooks/README.md`、ledger drift 解消)。

## [0.23.0] - 2026-06-25

### Fixed

- **保護ブランチ push gate (`block-push-to-protected.sh`) の迂回穴を塞いだ — 0.22.0 で merge gate を直したのと同型の「行為の文字列 proxy」(② 信号選び) バグが push gate に残っていた**。push 対象を貪欲 `sed 's/^.*git push//'` で抽出していたため、複合コマンド `git push origin main && git push origin feat/x` では**最後の feat/x しか検査されず保護 main への push が無検査で素通り**した。さらに検出が先頭 `/` 非対応で `/usr/bin/git push` / `./git push` を**素通し**した。どちらも稼働中の保護を実際に無音バイパスできる live bug だった。
  - 共有エンジン `hooks/lib/protected-branch.sh` を新設 (`merge-targets.sh` と同型の単一権威)。複合コマンドの**全** `git push` segment を走査し、path-prefixed git を受理、flag とその値 (`--repo`/`-o`/`--receive-pack`/`--exec`/`--flag=value`) を skip し、refspec の destination (`src:dst`→`dst`、先頭 `+`・`refs/heads/` を正規化) を列挙する。`is_protected` も lib に移して 2 経路の単一権威に。既知の限界 (quote 内 separator) は lib 冒頭に明示。
  - TDD: `tests/hooks/protected-branch.test.bash` (engine 31 assertions) + 実 hook の end-to-end (sandbox repo に `.bootstrap-protected`) で両バグクラスが exit 2 で block・benign が exit 0・unparseable で fail-closed を確認。全 31 suite green、hook 数不変 (新規は lib、entry 追加なし)。旧挙動と message/exit は byte 互換の厳密改善。

### Added

- **統合 gate (`block-unreviewed-merge.sh`) に「lane が merge 先を含む (= rebase 済) か」の fail-closed 検査 (D6) と、merge 時の残置 worktree 大声 advisory (D5) を追加**。stale base の lane を統合すると merge 済み修正を無音で revert する事故 (`git diff`/`status` が HEAD 基準で revert が見えない — appo-followup dogfood 2026-06-25) を、**行為の瞬間 (統合) で rebase を強制**して塞ぐ。
  - D6 (fail-closed): 各 lane target `L` について merge 先 (HEAD) が `L` に含まれるか `git merge-base --is-ancestor` で検査し、stale なら merge-base 基準の乖離数つきで block。レビュー未記録より**先に** stale を理由に止める。根拠不在 (非 lane / ref 解決不能 / 非 work-tree) は fail-open、offline (stale ローカル ref は黙らせるだけで false-alarm しない)。`hooks/lib/repo-drift.sh` を read-only 再利用 (HEAD-vs-main 定義の単一権威、signal drift 防止)。
  - D5 (advisory・**決して block しない**): merge 時に merge 済み残置 worktree を stderr に大声表示し撤去を促す (未コミットを持つ木の強制削除 = cry-wolf を避ける)。残置が無いとき無音。
  - TDD: `tests/hooks/block-unreviewed-merge-drift.test.bash` (temp git repo 上で 15 assertions: stale block / 順序 / no-false-block / fail-open / D5 advisory が exit code 不変) + 既存 28 挙動を全維持。
- これらは sprint flow 自体の dogfood で実装 (`sprint-plan` で scope 非重複 2 lane に分解 → 隔離 worktree で並列 TDD → adversarial AI レビューで approve → `integrate` で verification 起票・依存順 merge・統合 verify・worktree 撤去・board archive)。appo-followup の incident 群から抽出した bootstrap 側欠陥 backlog の P0 + D5/D6。

## [0.22.1] - 2026-06-22

### Changed

- **`skills/project-bootstrap/SKILL.md` に「16 並列の各レーンで自動なのは TDD だけ」の明確化を追加**。ultracode 全開 (`/effort ultracode`) 時、各レーンが自動で規律を保つのは **TDD のみ** (`require-test-companion` が subagent の Edit/Write にも発火 — ADR 0004)。**worktree 隔離・依存順・レビュー/検証は「自動」でなく「Claude が書くワークフローの質 + 統合関所」依存**、という区別を明文化した (spawn 時点で hook は内部を観測できない — ADR 0005 — ので 16 並列の安全は統合の入口 guard 1/2/3 が全面的に担う)。保証つきの規律が要るなら `sprint-plan`→`integrate`、最速で雑が許せるなら生 ultracode、どちらでも TDD は各レーンに届く。ADR 0005/0006 の既存記述を、よくある誤解 (「各レーンが規律の取れた状態で最速」) の根治として補強。

## [0.22.0] - 2026-06-22

### Fixed

- **統合関所 (merge gate) の迂回穴を塞いだ — 並列作業の唯一の net が「行為の文字列 proxy」で実装され、実際にすり抜け可能だった**。`block-unreviewed-merge.sh` / `block-merge-if-verification-unclosed.sh` は merge 対象を貪欲 `sed 's/^.*git merge//'` で抽出していたため、複合コマンド `git merge A && git merge B` では**最後の B しか検査されず A が無検査で統合**された。また検出が bare `git merge` token のみで、`/usr/bin/git merge` 等の path-prefixed 形を**素通し**した。どちらも、プラグインが sprint 語彙について他所で断罪している「行為の文字列 proxy」(② 信号選び) そのものだった。
  - 共有エンジン `hooks/lib/merge-targets.sh` を新設 (単一権威で 2 gate の signal drift を防止)。複合コマンドの**全** `git merge` segment を走査し、path-prefixed git を受理、flag とその値 (`-m <msg>` 等) を skip し、後続の非 merge コマンドの語を誤って target にしない (`git merge a && echo b` は a のみ)。既知の限界 (quote 内の separator metachar) は lib 冒頭に明示。
  - TDD: 回帰テストを先に Red 確認 (複合で素通し / path-prefixed で素通し) → lib 実装 → 両 gate を loop へ載せ替え → 全 29 suite green。`tests/hooks/merge-targets.test.bash` (engine 単体 15 ケース) + 両 gate test に回帰 3 ケースずつ。hook 数は不変 (新規は lib、hook entry 追加なし)。
- **`skills/project-bootstrap/SKILL.md` の自己矛盾を解消**。「subagent と並列開発」節が、ADR 0004 による read-only ルール撤回を述べた直後に「実体を書き換える作業を subagent に委譲しない」を**現在形の規則**として残しており、直下の form ③ (Workflow/subagent の mutation lane) と矛盾していた。frontmatter は既に「mutation は隔離 worktree + 統合関所つきで可」と正しいので、body をそれに整合させた (= mutation は隔離 + 関所つきで公認、main session 自身の TDD core loop のみ直接)。
- **`hooks/README.md` の hook 台帳ドリフトを修正** (14 → 17)。`block-uniso-main-edit` (ADR 0005 guard 2) / `block-over-wip-parallel` (guard 3) / `sprint-trigger-reminder` (UserPromptSubmit) の 3 節が欠落し、「発火順」も stale だった。全 17 hook を `hooks.json` の結線順で列挙し直した (`plugin.json` / `marketplace.json` / root README は既に 17 で整合済み)。

### Added

- **`hooks/README.md` に「Claude Code 契約への依存 (harness contract)」節**。各 gate が依存する payload key (`command` / `file_path` / `transcript_path` / `cwd`) と、Anthropic が key を rename したときの **gate ごとの挙動** (`command` = fail-closed で即発覚 / `file_path`・`transcript_path` = fail-open で無音バイパス) を表で明示し、CC アップグレード時の手動再検証を促す (隠れた外部前提の可視化 = ③ 配備の可視化 を CC 契約そのものに適用)。runtime 自動警告を**あえて足さない**理由 (key rename と surface 差を区別できず cry-wolf になる — 本 repo の test fixture 自体が `transcript_path` を持たない正当な payload) も記録。
- **`/deep-research` を read-only の「外部オラクル腕」として skills に編入** (ADR 0008 #1)。`skills/plan` (前提検証 Step) / `skills/verification` (外部事実オラクル) / `skills/project-bootstrap` (癖 7) に、repo 外の事実 (3rd-party 挙動 / API 仕様 / 「X は可能か」) を記憶で推測せず web を多角照合して裏取りする経路を追加。「オラクルは AI の外」(verification skill) の web 版で advisory input 限定 (`HUMAN`/意図行を web claim で自動 close しない)。harness の bundled Workflow を呼ぶだけなので二重化・同梱しない。
- **単一 orchestrator frontier を `④ 計測つきの取引` と `scripts/velocity.sh` に明記** (ADR 0008 / N=1 honesty)。採点者が 1 人の間は defect-rate metric とレビュー帯域の律速が同一人物なので、独立統制でなく self-report に近いと限界を名指し (③ の自己適用)。取引を否定せず限界を無音にしない。
- **`docs/decisions/0008-*.md` 新設 (Accepted)** — Claude Code 新 primitive の採用方針。#1 編入済み / **#2 (`prompt`/`agent` hook で advisory 規律を確率 gate 化) は受諾 → opt-in pilot 実装済み** (warn 始動・誤検知 metric・CI テスト不能ゆえ pilot 限定・決定論 gate は置換しない の 4 条件つき) / **#3 exec-form は却下** (hook command に untrusted 入力が無く rent を払わない + 未検証で全 hook 破壊リスク) / **#4 saved workflow 同梱は却下** (plugin は workflow を配布不可と確認 — 公式 plugin structure に `workflows/` が無い)。
- **cohort-audit の opt-in 確率 gate pilot を新設** (`templates/hooks/cohort-audit-pilot.json`、ADR 0008 #2)。本プラグイン**初の非決定論 (確率) gate**: 公式 docs で検証した `Stop` prompt hook (Haiku が毎ターン `{"ok",  "reason"}` を返す) が、user-facing bug fix で同根 cohort audit が無いときだけ **warn-only で nudge** する (`ok:false` の reason が Claude に戻り作業継続 = block しない。feature/refactor/不確実は `ok:true` で cry-wolf 抑制)。**default の 17 hook には入れない** — 確率 gate を全 consumer に毎ターン強制しないため opt-in にし、誤検知率を実運用で測ってから昇格判断 (CI テスト不能ゆえ実運用の手動観測が安全網)。`hooks/README.md` の opt-in pilot 節 + `skills/project-bootstrap/SKILL.md` 完遂責任節にミラー。

## [0.21.0] - 2026-06-21

### Added

- **SessionStart doctor が「未判断の trunk 変更」を可視化 (`hooks/lib/verification-drift.sh` 新設 + `bootstrap-session-doctor.sh` に第3 audit 軸を追加、ADR 0007 Amendment)**。dogfood で表面化した穴: ADR 0007 の verification gate は **lane branch の merge** を信号にするため、branch を切らず trunk を直接いじる**逐次変更は gate を一切通らず**、動作テストの要否判断が**無音で省かれた** (「プラグインで変更したのに verification を何も言って来ない」)。原則「要否判断を無音で省かない」と関所の配置 (lane merge 一経路) の**カバレッジ差** — memory `feedback_gate_distribution_coverage`「関所は全方式が必ず通る行為に置く」の逐次版。ADR 0007 は射程の境界で「逐次は doctor (可視化) が担う」と書いたが、その doctor 側が**未実装**だった。本リリースがその半分を実装する。
  - **判定**: `docs/verification/` 採用済み repo で、current branch に source-face 変更 (未コミット ∪ main remote-tracking ref より先行する commit) があるのに verification 判断が記録されていない (plan 不在/空) とき、advisory を SessionStart context に注入する。source 面判定は `is_source_path` (source-face.sh)、main ref 解決と offline 比較は `drift_main_ref` (repo-drift.sh)、plan 判定は `vplan_*` (verification-plan.sh) を再利用。
  - **可視化であって強制ではない** (merge gate のような fail-closed block にしない)。「ある変更に動作テストが要るか」は既約な判断 (ADR 0001 の残余) だが「要否判断すら記録していない」は FACT として surface できる (ADR 0003 の doctrine)。記録される判断は理由つき DROP だけでも良い — 強制するのは「テストを書くこと」でなく「判断を無音で省かないこと」。doctrine の 4 設計判断は 5 にしない (② 信号選び / ③ 配備の可視化 の適用)。
  - **opt-in** (`docs/verification/` 不在なら無音) かつ **offline** (fetch せず local main ref と比較。ref 不解決の local-only repo は未コミット集合のみで判定 = fail-open に過小報告)。3 軸 (採用 / repo drift / 未判断) は独立で、いずれも無ければ無音 (advisory bloat ゼロ)。
  - **意図的スコープ外**: ① 要否判断の**不在**だけを対象 (trunk 上で OPEN 放置された plan の closure を fail-closed に強制するのは push-time 拡張の領分 = universal 版、未実装)。② SessionStart は「開いた時点の state」を捕まえる net なので、同一 session 内で後から作った変更は次回 session まで surface されない (repo-drift と同性質。即時通知は同 engine 再利用の follow-up 余地)。
  - **branch→plan パス導出を `hooks/lib/verification-plan.sh` の `vplan_path_for_branch` に括り出し**、merge gate と doctor が同一の信号を共有 (gate-signal drift 防止。`block-merge-if-verification-unclosed.sh` を載せ替え、挙動不変 = 既存 19 ケース緑)。
  - `tests/hooks/verification-drift.test.bash` (engine 単体 10 ケース) + `bootstrap-session-doctor.test.bash` に注入 2 ケース + `verification-plan.test.bash` に `vplan_path_for_branch` 4 ケース。hook 数は不変 (新 lib は既存 SessionStart hook が source、新 hook entry なし)。`docs/decisions/0007-*.md` に Amendment 追記。この変更自体の verification plan を `docs/verification/main.md` に起こし bootstrap repo 自身が verification flow を採用 (dogfood)。

## [0.20.0] - 2026-06-21

### Added

- **動作テスト設計を「意図アンカーの verification plan」として構造化し、統合の precondition にする (ADR 0007)**。dogfood (appo-followup) の incident ログを種類で見ると、残った事故が **1 件もロジックバグでない** — cross-repo 契約ズレ (mood)、要件捏造、stale checkout、deploy 虚偽完了。**コードレベルのバグは TDD hook + レビューで潰れ、残余リスクが丸ごと「継ぎ目 (seam)」へ移動した**。決定的なのは mood incident: サイトが問診から `mood` 設問を削除 → appo の zod は `mood: z.string().min(1)` 必須のまま → 当日 CV 17 人で**予約成立 0**。効かなかったのは「テストが無かった」ことでなく、**zod の unit test が緑のまま間違った契約を固定し false confidence を配った**こと。テスト設計の核心はオラクル問題 (正解をどこから取るか) で、AI 駆動開発では「著者=採点者」の円環になりやすい。
  - **唯一の原則 = テストは実装からでなく意図と跨いだ境界から導く**。これを二点アンカーで構造化: **plan 時** (コード前に意図 → behavior space + オラクルを導く。実装が無いので追認にならない) と **完了/統合時** (突合・実行・人間への引き継ぎ書)。
  - **成果物 = `docs/verification/<branch>.md`** (行指向・jq 非依存)。1 行 = 1 ケース `STATUS | kind | behaviour | oracle | by | evidence`。STATUS: `TODO`/`FAIL`/`HUMAN` = OPEN、`PASS`/`DROP`(理由必須) = CLOSED。フォーマット権威は単一 lib `hooks/lib/verification-plan.sh` に集約 (gate/doctor/skill 共有 = drift 防止)。fail-closed bias: 未知 status は OPEN 扱い、理由なき DROP は弾く (無音カット禁止)。
  - **強制点 = `hooks/block-merge-if-verification-unclosed.sh` (PreToolUse on `git merge`)**。review gate と同じ lane 信号 (活性 board task branch + linked worktree branch、ADR 0004) で、lane branch の merge に plan の存在・非空・OPEN 行ゼロ・理由なき DROP ゼロを要求。opt-in = `docs/verification/` を置く。fail-mode: 解析不能=fail-closed / 非 merge・非 git・未採用・非 lane=fail-open / 採用済みで plan 不在=fail-closed (「計画を書かない」で素通りさせない = ADR 0002 の教訓)。
  - **kill-question を doctrine に**: 各 `PASS` の前に「このテストが緑のままユーザーが困る状態はあるか?」を問う (Yes ならオラクルが誤り = mood の罠)。オラクル不在の挙動は「pass と仮定」でなく `HUMAN` で人間に倒す。
  - **新 skill `verification`** (技法選択表 / オラクル分類 / kill-question / plan テンプレ / 共同記録 / 引き継ぎ書)。`plan` skill に plan 時アンカー、`integrate` skill に閉じた plan の終端処理 (archive + 永続テスト昇格 + incident→memory) を委譲。doctrine の 4 設計判断は 5 にしない (テスト設計への適用であって新軸ではない)。
  - **doctor に verification 採用 + vendored-coverage 要件を追加** (③ 配備の可視化)。`scripts/doctor.sh` が verification 採用済みで gate 未配備を partial で surface。
  - **PR 経路の CI net `templates/ci/bootstrap-verification-gate.yml`** (review gate と同型)。手元 hook は GitHub PR 画面の merge を通らないので、plugin 非依存・self-contained (lib semantics をインライン再現) な CI で全 PR に閉じた計画を要求する。
  - `hooks/lib/verification-plan.sh` の unit test (21 ケース) + `block-merge-if-verification-unclosed.sh` の gate test (15 ケース) 新設。17 hook に。`docs/decisions/0007-*.md` 新設。

## [0.19.0] - 2026-06-19

### Added

- **SessionStart doctor が repo drift を可視化 (`hooks/lib/repo-drift.sh` 新設 + `bootstrap-session-doctor.sh` 拡張)**。dogfood (appo-followup) で繰り返した 2 つの無音事故 — (1) `git status` clean を「最新 main」と誤信して stale checkout から本番操作 (incident 2026-06-16-prod-migration-from-stale-checkout / 2026-06-12-shared-checkout-branch-collision)、(2) integrate skill が merge 後に撤去すべき worktree が残り lane が滞留 — を、session 起動時に surface する。`HEAD` が `origin/main` 系 remote-tracking ref より遅れている commit 数と、**merge 済みなのに残っている linked worktree** を出す。**強制でなく可視化** (どの checkout が正しいかは既約な判断 = ADR 0001 の残余だが、drift の事実は出せる = ADR 0003 の doctrine)。採用 audit と独立 (採用 ok でも drift は出す)。**fetch しない** (SessionStart は offline/高速であるべき) ので遅れは過小報告側にのみ倒れ誤警告しない。drift が無ければ無音 (advisory bloat ゼロ)。判定は純関数 lib に集約し `tests/hooks/repo-drift.test.bash` (11 ケース) + session-doctor test に drift 2 ケース追加。

### Changed

- **並列 default を実行形態で分離 (ADR 0006)**。`wip_limit` の既定は長く「2-3」と一言で書かれ、これが**全実行形態の単一天井**として読まれていた (= dogfood orchestrator の体感「並列が少ない・bootstrap が遅い」の正体)。実際には ADR 0005 の 2 形態は律速が違う: **terminal worker lane** は人間のレビュー帯域律速で `wip_limit` が `git worktree add` を cap する (guard 3 が観測できる唯一の路)、**Workflow/subagent lane** は main session が orchestrate し engine 並列上限 `min(16, cores-2)` 律速・帯域は統合関所 (guard 1) が自動で守るため **`wip_limit` 非対象** (guard 3 は内部 spawn を観測できない)。`wip_limit` cap を terminal worker 路に限ると明示し、worker advisory 既定を **2-3 → 3-4** に一段引き上げ (根拠 = dogfood の体感シグナル、revert 根拠 = `scripts/velocity.sh` の defect rate = ④ の管理された取引)。**コード挙動の変更は最小** — guard 3 は元々 worker 路専用で不変。変えたのは form-aware な default 表示文言 (`resolve-wip-limit.sh`) と doctrine (`skills/project-bootstrap` / `skills/sprint-plan` の WIP 節、`block-over-wip-parallel.sh` の block message、`templates/.bootstrap-wip` 既定 3→4、README、hooks/README)。`docs/decisions/0006-*.md` 新設。doctrine の 4 設計判断は 5 にしない (= ④ の適用であって新軸ではない)。
- **`scripts/doctor.sh` の `.bootstrap-wip` parseability 判定を rc ベースに**。従来は display 文字列 `"既定 2-3"` との一致で「整数が読めない」を検出していたが、ADR 0006 の既定改名で結合が割れた。整数版 `resolve_wip_limit_int` の return code で判定するよう変更し、既定文言の変更に結合しないようにした (= gate 信号の drift 防止)。`resolve-wip-limit.test.bash` / `sprint-trigger-reminder.test.bash` / `block-unplanned-feature-build.test.bash` の既定 assertion を form-aware 文言に追従。

## [0.18.0] - 2026-06-15

### Added

- **ultracode / Workflow を「bootstrap が governance する実行エンジン」として公認し、3 guard のうち 2 つを fail-closed 強制 (ADR 0005、ADR 0004 を一般化)**。ハーネスの `ultracode` (= `xhigh` effort + Workflow の subagent 自動 orchestration) は sprint-plan/integrate と機能が重複するが、これは新しい並列方式ではなく ADR 0004 が公認した**形態 ③ (Workflow/subagent) の一級コマンド化**。独立方式として扱わず、bootstrap (永続/lifecycle/強制/横断 memory の層) が governance する実行エンジンと位置づける。2 つの顔を別 governance に: **breadth (read-only ファンアウト = 探索/監査/レビュー多レンズ)** は無制限・隔離不要・`wip_limit` 非対象・gate 摩擦ゼロ (lane でないので review 帯域も消費しない)、**mutation lane (source を書く subagent)** は隔離 worktree 必須・`wip_limit` 対象・全 edit/merge gate を terminal worker と同一に通過。**hook は Workflow 内部の `agent()` spawn を観測できない** (内部 subagent は main session の tool 呼び出しでないため PreToolUse に届かない) ので、WIP・隔離の強制は spawn 時でなく **edit/merge/commit 時** = ADR 0004 の関所を WIP と検証に一般化した。subagent への hook 配達は 2026-06-15 に本 repo で再実測 (subagent に新規 source Write → `block-unplanned-feature-build.sh` が exit 2)。doctrine は 4 設計判断のまま (5 にしない — これは適用対象であって新軸でない)。`docs/decisions/0005-*.md` 新設、`README` ADR 表 + `skills/project-bootstrap/SKILL.md` の並列 3 形態節にミラー、`skills/sprint-plan` (探索の breadth ファンアウト + 形態 ③ lane の起動文) / `skills/integrate` (レビューを 1 lens=1 subagent にファンアウト・main で集約) / `skills/plan` (read-only breadth、鉄則=mutation 不可を保持) に委譲ノートを追加。
  - **guard 1 — agent 判定の `verdict: approve` が実検証を代替しないことを強制**。`block-unreviewed-merge.sh` は approve を確認した上で**検出したテストスイートを関所自身が実行**し、fail なら block する (= `tests:` 行のような自由文を信じない。信号は実テストの実行結果)。merge は PreToolUse ゆえ統合"後"は測れない (post-merge 全スイートは integrate Step 3) が、統合先が緑であることは保証する — agent の approve 単独では担保されない隙間。テスト検出ロジックは commit gate と共有 lib `hooks/lib/detect-test-suite.sh` に切り出し単一権威化 (= gate 信号の drift 防止。`block-commit-if-tests-fail.sh` も載せ替え、挙動不変)。runner 未検出は fail-open (commit gate と同じ)。`tests/hooks/block-unreviewed-merge.test.bash` に passing/failing suite の 2 ケース追加。
  - **guard 3 — `.bootstrap-wip` を表示専用から fail-closed 強制へ (`hooks/block-over-wip-parallel.sh` 新設)**。従来 `.bootstrap-wip` は `resolve-wip-limit.sh` が checklist に表示するだけで何も block しなかった (= 強制なき宣言)。新 hook は「並列 lane を 1 本開く行為」= `git worktree add` を信号に、既存 linked worktree 数が宣言 wip_limit に達していれば exit 2。観測可能な lane 生成路を縛る (Workflow 内部 isolation worktree は見えない = guard 1 の統合関所が最終 net)。`resolve-wip-limit.sh` に blocking 用の整数版 `resolve_wip_limit_int` を追加 (表示版は無傷、未宣言/解析不能は rc 1 で呼び出し側 fail-open = opt-in 尊重)。`hooks/hooks.json` に配線、`scripts/doctor.sh` の sprint REQ に追加 (= 未配備を partial で可視化)、`tests/hooks/block-over-wip-parallel.test.bash` 新設 (10 ケース) + `resolve-wip-limit.test.bash` に整数版 7 ケース。
  - **guard 2 — mutation lane の worktree 隔離を強制 (`hooks/block-uniso-main-edit.sh` 新設)**。`block-out-of-lane-edit.sh` は `.bootstrap-lane` を持つ worktree (lane) の中でしか効かず、共有 main worktree で source を mutate する行為 (= Workflow/subagent が隔離 worktree を使わず shared tree で書く collision) は素通しだった。新 hook はそれを塞ぐが、lead の正当な統合作業を誤爆しないよう**精密な信号**にした (誤検知 > false negative — ADR 0004): (a) docs/sprint 採用 (b) main worktree に居る (c) active な linked worktree lane が在る (d) 統合操作中でない (MERGE_HEAD / rebase / cherry-pick / revert は lead の conflict 解決として通す) (e) 編集対象が source 面 — の全条件が揃ったときだけ block、どれか曖昧なら fail-open。source 面の判定は block-unplanned-feature-build と共有 lib `hooks/lib/source-face.sh` に切り出し単一権威化 (= drift 防止。block-unplanned も載せ替え、挙動不変 = 既存 28 ケース緑)。`hooks/hooks.json` 配線 + `scripts/doctor.sh` の sprint REQ 追加 + `tests/hooks/block-uniso-main-edit.test.bash` 新設 (10 ケース、誤爆しない fail-open 経路を全て pin)。16 hook で ADR 0005 の 3 guard 完備。

## [0.17.0] - 2026-06-11

### Changed

- **並列開発の 3 形態を公認し、統合関所を方式非依存に拡張 (ADR 0004、ADR 0001 を部分 supersede)**。前提が 2 つ同日に覆った: (1) 「PreToolUse hook は subagent で発火しない」(#21460) は **2026-05-29 に upstream で修正済み**で、実測検証 (一時 repo で subagent に新規 source Write を指示 → `require-test-companion.sh` が exit 2 で blocking) により subagent にも plugin hook が届くことを確認。「subagent は read-only 専用」の根拠が消滅した。(2) 実際の並列開発はプラグインが想定した「ターミナル worker + board」では一度も起きておらず、**branch 並走 + GitHub PR merge** (消費先で 10 PR/日 の実績 — PR 画面の merge は手元 hook を物理的に通らない) と **Workflow サブエージェント並列実装** (board 不在で関所が眠る) の 2 形態で起きていた。gate 無音化 class の 5 例目 (**mode coverage**、`docs/incidents/2026-06-11-parallel-mode-gate-coverage`)。対応: ① subagent / Workflow の mutation を隔離 worktree 必須で公認 (edit 時 gate は subagent にも効く)。② `block-unreviewed-merge.sh` の信号を「活性 board の task branch」から「並列 lane の branch = 活性 board task branch ∪ **linked worktree に checkout された branch**」に拡張 (board 不要、opt-in は docs/sprint/ の存在。worktree という物理痕跡を信号にすればどの方式でも統合の入口で捕まる)。worktree の撤去は必ず merge の後 (`tests/hooks/block-unreviewed-merge.test.bash` 13-17 で pin)。③ PR 経路は **`templates/ci/bootstrap-review-gate.yml`** (新規) — 導入 repo では「PR を作る = 統合行為」とみなし全 PR にレビュー記録 (`docs/sprint/reviews/<branch>.md` + `verdict: approve`、手元 hook と同一規約) を要求。required status check 化は main 直 push 運用と両立しないため repo ごとの判断 (templates/ci/README.md)。SKILL.md の「subagent は read-only」節は 3 形態の表に書き換え。
- **defect rate の基準線を引き直し**。旧「11%」は英語 prefix のみの旧計測による数字で比較不能 (同窓を新方式で再計測すると 20%)。新基準線の起点 = 2026-06-11 横断 4w 実測 **12%** (`scripts/velocity.sh` header に明記)。

## [0.16.1] - 2026-06-11

### Fixed

- **velocity.sh の fixrev 判定が日本語 commit を数えられず defect 率が 4 倍過小だった**。判定が英語 prefix (`^fix|hotfix|revert`) のみで、user の repo の主たる commit 語彙 (「〜を修正」「不具合報告4件を修正」) が全て不可視だった — Stage 2 trust ladder の安全網の数字が、昇降判定を逆方向に誤らせる状態 (実測: 4 週合算 defect 3% → 修正後 12%、基準線 11% とほぼ同水準。`docs/incidents/2026-06-11-velocity-fixrev-japanese-blind`)。日本語 defect 語 `修正` / `バグ` / `不具合` / `誤り` (subject 中のどこでも) を追加。token は実 cohort で精度検証してから採用し、false positive を確認した「戻す」(業務フロー語) / 「直し」(やり直し = incident 記録語) / 「解消」(非 defect に混入) は理由付きで不採用 (= 罠 4: pattern を広げる fix は cohort 副作用を測ってから)。除外判断ごと `tests/hooks/velocity.test.bash` に pin。

## [0.16.0] - 2026-06-11

### Fixed

- **sprint 発火 gate の `.gate` entry を時間 (日付列 + TTL 3 日) と空間 (feature-scoped glob) で bound する**。gate は `.gate` に記録された scope glob を**無期限・無界**に信じていたが、`.gate` entry は「この scope は逐次と判定した」という feature 単位の **ephemeral 判定**で、実際に消費先 repo (creative-team-app) で 2026-06-02 に 1 つの feature のために記録された `src/**` 1 行が **source tree 全域の gate を恒久 fail-open** にし、06-05〜06-10 に判定なしの新規 source が 10 本以上通過した (= gate 無音化 class の 4 例目: advisory の沈黙 → 配備漏れ → stale state → **unbounded state**。`docs/incidents/2026-06-11-gate-broad-glob-permanent-fail-open`)。stale-board (0.14.0) と同根の lifecycle 問題だが、追記型 log は board.json と違い「所有 skill が archive する」という終端責務を置けない (誰もその行の feature の終わりを判定できない) ため、**state 自身に失効を埋め込む**: 形式を `<glob>  <YYYY-MM-DD>  <理由>` に変え、記録から `GATE_TTL_DAYS` (= 3 日) で失効、日付なし旧形式 / 日付不正 / 未来日付は「判定の活性を証明できない」として不採用 (= 解析不能を素通し側に倒さない)。失効後は同じ行を日付だけ更新して再記録し、**その 1 printf が「まだ同一 feature 面か」の再判定**として機能する。空間側は exact path か「wildcard 前に 2 階層以上の literal prefix を持つ glob」のみ有効 (`src/components/**` は有効、`src/**` / `scripts/**` / `**` は無効)。判定エンジンは `hooks/lib/gate-entry.sh` (`gate_date_fresh` / `gate_scope_ok`、純 bash・jq/GNU date 非依存 — 日数差は Julian Day Number の整数演算)。不採用 entry は block message に理由付きで列挙し「行の削除は不要 — 失効は正常な終端」と明記 (= 「記録したのに block された」を無説明にすると全消し・全域 glob 再記録という正データ隠蔽側の回避に走る。memory 原則 3)。block message の例示 glob も `src/<area>/**` → `src/<area>/<feature>/**` に変更 (= 広い記録への誘導を解消)。`tests/hooks/gate-entry.test.bash` 新設 (TTL 境界・月跨ぎ・旧形式・全域 glob) + 統合テスト 4 ケース追加で TDD。`templates/docs/sprint/README.md` / `skills/sprint-plan/SKILL.md` / `skills/project-bootstrap/SKILL.md` / `hooks/README.md` を新形式に更新。memory `feedback_gate_signal_and_failmode` に原則 6 を昇格。**`.gate` の旧形式 entry は無効になる** — 消費先は次回 block 時のメッセージに従って新形式で再記録すればよい (一括移行は不要)。

## [0.15.1] - 2026-06-07

### Fixed

- block-unreviewed-merge.sh の block message が integrate skill の旧採番 (Step 1.5) を参照していたのを Step 2 に修正 (= 権威の分散の解消、cosmetic)。

## [0.15.0] - 2026-06-07

### Added

- **`hooks/block-unreviewed-merge.sh` + integrate skill の AI レビュー工程 — レビューの trust ladder Stage 2**。並列フローの throughput 天井は「人間が全 diff を直列レビューする」ことに在り (`sprint-plan/SKILL.md` が明文化)、user のレビュー帯域は複数プロジェクト共有の単一資源なので、lane を増やしても throughput が増えない構造だった。一次レビューを **read-only の adversarial subagent** に移す (= read-only なので「subagent は mutation 禁止」ADR 0001 と整合): integrate skill の新 Step 2 が merge 前に branch ごとのレビューを回し、verdict + 指摘を `docs/sprint/reviews/<branch>.md` に記録 (commit する = どの verdict が通したかを遡る監査証跡。sprint 終了時に board と一緒に archive)。人間が読むのは verdict / 指摘 / diff サンプル 1-2 割 / 統合境界のみ。「レビューを済ませた」は advisory にせず gate で強制する: 新 hook は**活性 sprint 中の task branch の `git merge` 行為そのもの**を信号に、記録なし → block、`verdict: reject` → より強く block (却下の踏み越え禁止)。fail-mode は memory 5 原則準拠 (解析不能 = fail-closed / 非 merge・非活性・非 task branch = fail-open で通常の merge を一切妨げない)。活性判定は `hooks/lib/board-liveness.sh` に切り出して sprint gate と共有 (= gate 信号の drift 防止)。「レビューの質」は gate で保証できないため、安全網は defect rate 監視 (下記 velocity)。doctor の sprint 用 vendored REQ に追加 (配備漏れは partial)。14 hook。
- **`scripts/velocity.sh` — 週次 throughput / defect rate の複数 repo 横断計測 CLI**。レビューを薄くして「壊れていないか」を判定する唯一の客観データが fix/revert 率の推移。user は複数プロジェクト並行のため横断集計 (`bash scripts/velocity.sh <repo>...`)。出力は TSV: repo × 週 (直近 4 週) の commits/merges/fixrev + TOTAL + 4 週合算 defect 率。defect rate が跳ねたらレビューを 1 段厚く戻す、平坦なら lane を 1 段上げる — trust ladder の昇降判定をこの数字で行う。

## [0.14.0] - 2026-06-07

### Fixed

- **sprint 発火 gate の素通し信号を「board.json の存在」から「活性 (= 未完了 task の有無)」に修正**。`block-unplanned-feature-build.sh` は「進行中 sprint なら lane hook が scope を握る」として `board.json 非空` で素通ししていたが、board は per-sprint の **ephemeral state** で「全 task done だが archive 前」という終端状態を持ち、そこでは存在と活性が乖離する。実際にこの repo 自身が完了済み board (2026-05-24、全 task done) を残置しており、**2026-05-24 以降 sprint 発火 gate が一度も発火し得ない状態**だった (= 0.12.0 で fail-closed 化し 0.13.0 で配備漏れを可視化した同じ gate が、自陣で stale state により無音で死んでいた。gate 無音化 class の 3 例目: advisory の沈黙 → 配備漏れ → stale state)。修正は素通し条件を「`status` ≠ `done` の task が存在する」に変更し、全 done / task 無し / status 不在の board は「進行中の根拠なし」として `.gate` 判定に降ろす (= 解析不能を素通し側に倒さない)。あわせて `integrate/SKILL.md` Step 4 の「board.json は次 sprint まで**残すか** archive する」という任意性が残置を default にしていた真因を「必ず `docs/sprint/archive/<sprint>.json` へ移す」に責務化し、この repo の stale board も archive した。`docs/incidents/2026-06-07-stale-board-gate-bypass` に起票、memory `feedback_gate_signal_and_failmode` に「存在 ≠ 活性」原則を昇格。`tests/hooks/block-unplanned-feature-build.test.bash` に全 done / task 無し / in-review / .gate 併用の 4 ケースを pin。

### Added

- **`.bootstrap-wip` + `hooks/lib/resolve-wip-limit.sh` — wip_limit 既定のハードコードを project-local 宣言に追従させる**。「既定 2-3」が advisory テキストとして 6 箇所 (`sprint-trigger-reminder.sh` / `block-unplanned-feature-build.sh` / SKILL.md ×2 / README ×2) にハードコードされており、lane 数を上げる実験をする project は board.json の `wip_limit` を変えても **hook が毎ターン「既定 2-3」を注入し続けて宣言と喧嘩する** 状態だった。正本を board.json にしなかったのは、board が per-sprint の **ephemeral state** で、`wip_limit` は sprint 固有の逸脱値 (`_wip_note` 参照) を含み、sprint 終了後は stale になるため (= 実際にこの repo の board は完了済み sprint の `wip_limit: 4` を保持していた)。project 既定は repo root の **`.bootstrap-wip`** (最初の非コメント行に整数 1 行) で宣言する — `.bootstrap-arch` / `-lane` / `-protected` / `-lint` と同じ opt-in idiom。両 hook は共有エンジン `lib/resolve-wip-limit.sh` (jq 非依存) で表示を実値化し、不在・解析不能は「既定 2-3」に fail-open (= この値は checklist の**表示**であって gate の blocking 信号ではない。gate は従来通り `.gate`/`board.json` の有無で判定)。「宣言したのに解析不能で無音で無視される」は `scripts/doctor.sh` が partial (exit 2) として可視化する (= 配備漏れ無音化の class に追従)。sprint ごとの逸脱は従来通り board.json の `wip_limit` + `_wip_note` (理由必須) で行う — 逸脱は per-sprint の判断であって新しい既定ではない。`tests/hooks/resolve-wip-limit.test.bash` 新設 + 両 hook / doctor のテスト拡張で TDD。`templates/.bootstrap-wip` 追加。

## [0.13.0] - 2026-06-02

### Added

- **`scripts/doctor.sh` + `hooks/bootstrap-session-doctor.sh` (SessionStart) — 採用状態を audit し配備漏れの無音を破る**。ADR 0002 で sprint 発火を fail-closed gate に作り替えたが、その gate は消費先 repo で **その hook が現行版で実際に走っている** ことに全面依存する。gate を「team-wide net の有無」で見ると非対称があり、arch は CI net (`arch-check.sh` + `bootstrap-arch.yml`) が後追いで拾うが、**sprint 発火 gate は build *前* の分解判断ゆえ commit-time / CI で後追いできず、PreToolUse hook 以外に backstop を持てない唯一の gate** (ADR 0002 で commit-time を却下済)。実際に事故になった (`docs/incidents/2026-06-02-coverage-drift-silent`): sprint flow 採用済みの repo に `block-unplanned-feature-build.sh` が未配備で (`.claude/hooks/` に 2 本だけ vendoring・settings 配線も無し)、advisory リマインダをモデルが無視した判断ミスを止める fail-closed の裏が物理的に存在しなかった。設計修正 (0002) は「現行 hook を走らせている repo」しか守らず、partial / stale な採用が無音で成立することが残った真因。`scripts/doctor.sh` は採用状態を `skip/unadopted/declined/partial/ok` に判定する単一エンジン (exit: partial=2、他=0)。partial の中核は **vendored-coverage gap** (= `.claude/hooks/` で vendoring しているのに採用機能に必要な hook が欠落 = incident そのものを repo 内から検証)。`bootstrap-session-doctor.sh` は session 起動時に doctor を回し、**actionable な状態のときだけ** context に注入する: `unadopted` → 導入を user に一度だけ尋ねる (勝手に作らない / 望まなければ `.bootstrap-declined` で黙る)、`partial` → 配備漏れを警告、`ok/declined/非 git` → 無音。これは advisory (= 強制ではない。採用は consent 必須) だが、本プラグインが否定する advisory は「強制すべき判定を逃がすこと」であって「強制不能な判定を**可視化する**こと」ではない (enforcement の本体は per-action gate のまま。0001/0002 の系)。設計は `docs/decisions/0003-sessionstart-adoption-doctor.md` に ADR 化、`tests/hooks/doctor.test.bash` + `tests/hooks/bootstrap-session-doctor.test.bash` で TDD。13 hook。
- **`templates/ci/bootstrap-doctor.yml` — plugin 非依存の採用 audit CI net**。SessionStart の採用 audit は **plugin が在る Claude session でしか発火しない** ため、plugin を入れず `.claude/hooks/` に subset だけ vendoring した repo (= まさに incident の repo) では session audit がそもそも走らない。CI なら plugin 非依存で必ず通り、partial を `exit 2` → bypass 不可で fail にする (未採用は fail させない = 採用を強制しない)。doctor は SessionStart / CI / 手動で共有する単一エンジン。`templates/ci/README.md` に導入手順を追記。

## [0.12.0] - 2026-05-31

### Added

- **`hooks/block-unplanned-feature-build.sh` (PreToolUse) — sprint 発火判定を advisory リマインダから fail-closed gate に作り替え**。0.11.0 で足した `sprint-trigger-reminder.sh` は checklist を context 注入する**だけ**で、判定も分解も逐次の決定もモデル任せ = advisory のままだった。しかも発火信号が判定対象 (feature 面を作る) の proxy である「user prompt の語彙 regex」で、登録外の言い回し (統合 / 移行 / 完成 / やれ) で沈黙する穴があり、実アプリ開発で sprint 分解が一度も発火せず事故になった (`docs/incidents/2026-05-31-sprint-advisory-silent`)。これはプラグインが他所で否定する「advisory は忘れられる」失敗モードが、唯一の例外箇所で的中したもの。新 hook は TDD/lane/arch と同型: hook は意味的な仕事 (正しい分解) を代行できないが**前進行為の precondition は強制できる**ため、**新規 source file を作ろうとした瞬間** (= 判定対象そのものを信号にする。語彙ではない) に、判定の記録 (`docs/sprint/.gate`) も進行中 sprint (`board.json`) も無ければ `exit 2` で blocking する。sprint を起動はしない (worktree 起動=人間 / disjoint 判定=モデルは ADR 0001 の既約な残余) —「判定を済ませた precondition」だけを強制する。`docs/sprint/` を採用した project でのみ発火 (opt-in)。既存 file 編集 / test / config / doc / 非 source / 非 git は fail-open (= 根拠不在は通す。bug fix / refactor は trip しない)。`.gate` 記録 scope 外の新規 source は再 block (= mid-session の新しい disjoint 面で再判定)。設計転換は `docs/decisions/0002-sprint-gate-fail-closed.md` に ADR 化、`tests/hooks/block-unplanned-feature-build.test.bash` で TDD。

### Changed

- **`sprint-trigger-reminder.sh` を強制本体から早期ヒントに降格**。強制は上記 gate が担うため、UserPromptSubmit リマインダの語彙 regex 取りこぼしはもう致命的でない (= 行為信号が最終的に必ず捕まえる)。`skills/project-bootstrap/SKILL.md` の並列開発フロー節 / `skills/sprint-plan/SKILL.md` / README / `templates/docs/sprint/README.md` を gate 中心に更新。memory `feedback_gate_signal_and_failmode` に「反 advisory 系の中の advisory 残置が穴。前進行為に precondition を課して fail-closed 化する」を昇格。

## [0.11.0] - 2026-05-29

### Added

- **`hooks/sprint-trigger-reminder.sh` (UserPromptSubmit) — sprint 自動分解の「判定し忘れ」を deterministic に塞ぐ**。sprint 自動分解は SKILL.md の advisory (= Claude が探索結果から自分で判定して `sprint-plan` をロードする) だったが、`hooks.json` には `PreToolUse` しか無く SessionStart も無いため、SKILL が context から抜ける / 長い会話で忘れられると判定そのものが走らず「全然起動しない」状態になっていた。これはプラグインが他所で否定する「advisory は忘れられる」失敗モードそのもの。sprint を hook で起動することはできない (worktree 起動は人間、判定は Claude) が、feature 実装っぽい user prompt のとき発火判定の 3 条件 checklist (① feature か ② scope 非重複 leaf 2 個以上か ③ ≤wip_limit) を毎ターン `additionalContext` に注入することで、判定の実行だけは deterministic に保証する。非該当 prompt では無音。over-trigger しても reminder 1 つで安く、3 条件 gate が bugfix/単一 file を弾くため害にならない (= false negative より false positive を許す設計)。`tests/hooks/sprint-trigger-reminder.test.bash` で TDD、`helper.bash` に stdout キャプチャ (`assert_stdout_contains` / `assert_stdout_empty`) を追加。

### Fixed

- **`block-cross-claude-wip.sh` の誤検知を根治 (信号を「他 session が編集したか」に反転)**。旧実装は self-edited set (= Edit/Write/MultiEdit/NotebookEdit の `file_path`) に**無い** staged file をすべて intruder としていた。しかし Bash tool は `file_path` を transcript に残さないため、`npm install` (package-lock.json) / generator / `sed -i` / `cp` / `mv` 等、当 session が正規に生成・変更した file がことごとく誤 block されていた。誤検知は「lockfile を gitignore」「migration SQL を untrack」といった**有害な回避策**や hook 無効化を誘発し、本来防ぎたい巻き込みすら防げなくなる (cry-wolf → 逆効果)。修正後は、同一 projects dir の *他* session transcript (= 同一 working tree を共有する別ターミナル) が編集した file だけを foreign-edited として識別し、staged file がそこに**ある**ものだけを block する。projects dir の hash は cwd 由来なので worktree 隔離下の別 session は sibling に現れず誤 block しない (= incident `2026-05-24-shared-index-amend-mixing` で確立した「worktree = lane = 1 index」と構造的に一致)。他 session の編集証拠が無い file は素通し (= fail-open。`.bootstrap-{protected,arch,lane}` 不在時の素通しと同じ「根拠が無ければ通す」原則)。コマンド解析不能時の fail-closed は不変。sibling の鮮度窓は `BOOTSTRAP_WIP_WINDOW_HOURS` (default 24h、`0` で無効化) で調整可。block メッセージから「artifact なら .gitignore」の有害な助言を削除し「lockfile / migration は commit すべき file。隠さず正規手順で対処」に差し替え。`tests/hooks/block-cross-claude-wip.test.bash` に誤検知回帰 (lockfile / no-sibling fail-open / 鮮度窓) を pin。

## [0.10.0] - 2026-05-29

### Changed

- **sprint 分解を default 挙動に格上げ (= 明示呼び出し待ちにしない)**。従来 `/sprint-plan` という slash command (= advisory) を起点にしていたが、これはプラグインの「advisory は忘れられるから不採用」方針と矛盾していた。`skills/project-bootstrap/SKILL.md` の並列開発フロー節に発火条件を明示し、feature の実装着手時に探索結果が「scope 非重複の leaf 2 個以上 (≤ `wip_limit`) に割れる」を満たしたら、「並列で」「スクラムで」と言われなくても自動で sprint 分解を起動する。bug fix / refactor / 単一 file / 自明な小変更には発火しない (= 逐次)。worker Claude の起動は従来どおり人間が行う (task = 1 worktree = 1 owner モデルは不変。1 session 内 subagent 並列実行は採らない)。`skills/sprint-plan/SKILL.md` の description を auto-load 寄りに更新、README も追従。
- **subagent を read-only 専用にし、TDD の mutation を main session に戻した**。一次ソース検証で「PreToolUse hook は subagent の tool 呼び出しでは発火しない」(upstream `#21460` OPEN・SECURITY、伝播 `#27533` は not_planned、plugin subagent では frontmatter `hooks:` も無視) と確定。従来 SKILL は TDD の Red/Green/Refactor を mutating subagent に委譲しており、**プラグインが推奨する経路で hook (test 先行 / lane / 依存方向 / commit gate) が静かに無効化**されていた。SKILL に「subagent は read-only 探索専用 / mutation はすべて main session / 並列は subagent でなく別 session の worker (各 worker が main session なので hook が効く)」を明文化。判断の一次ソースと採用しなかった代替案 (案B = 1 session 内 subagent 並列実行 等) は `docs/decisions/0001-subagent-hooks-not-enforced.md` に ADR 化。

### Removed

- **`agents/test-writer.md` / `implementer.md` / `refactorer.md` を削除**。これらは mutating subagent (テスト / 実装 / リファクタを書く) だが、subagent では hook が発火しないため「強制 = hook」を貫けない。TDD の Red/Green/Refactor は main session が直接担う設計に変更 (上記 Changed 参照)。

## [0.9.1] - 2026-05-29

### Fixed

- **hook の JSON コマンド解析を fail-open から fail-closed へ**。7 つの hook (`block-add-all` / `block-arch-violations` / `block-commit-if-lint-fails` / `block-commit-if-tests-fail` / `block-cross-claude-wip` / `block-dangerous-git-ops` / `block-push-to-protected`) がコピペ共有していた `grep -oE '"command"[^,}]*'` は**最初の `,` / `}` でコマンド文字列を切る**ため、`git commit -m "fix, bug" && git add -A` のような入力で後続の危険 op が解析対象から消え、gate が検出失敗時に**素通し (fail-open)** していた。解析を `hooks/lib/parse-command.sh` の共通関数 `parse_command` に集約 (末尾の未エスケープ `"` まで読み、`\" \\ \n \t` 等を 1 段デコード、jq 非依存)。各 hook は解析不能時に `exit 2` で**安全側に block (fail-closed)** する。`tests/hooks/parse-command.test.bash` で TDD、各 hook テストにコンマ/エスケープ regression を追加。

### Added

- **`.github/workflows/test.yml` — self-CI**。push / PR で `tests/hooks/*.test.bash` 全 suite を ubuntu-latest で実行。SKILL.md の唱える「最終砦 = server 側 gate」を harness 自身にも適用し、上記のような fail-open regression を二度とマージさせない。

## [0.9.0] - 2026-05-25

### Added

- **`scripts/arch-check.sh` — 依存方向の独立 CLI (Claude 非依存)**。`hooks/lib/arch-check.sh` エンジンを共有し、引数の file 群 (or staged) に `.bootstrap-arch` 契約を検査、違反で exit 1。Claude Code の PreToolUse hook は **Claude のセッションでしか発火しない**ため、人間の直 commit / plugin 未ロードのセッション / 別ツールでは強制が静かに消える。この CLI を CI と git-hook から呼ぶことで、同じ契約を「誰がどう変更しても通る場所」で強制する。`tests/hooks/arch-check-cli.test.bash` で TDD。
- **`templates/ci/bootstrap-arch.yml` — GitHub Actions workflow テンプレ**。PR の変更ファイルに arch-check を回す **bypass 不可のマージ gate**。PreToolUse 強制が環境事故で消えても CI は server 側で必ず効く「最終砦」。変更ファイルのみ検査するので既存 debt のあるリポにも段階導入できる。
- **`templates/hooks/pre-commit` — git native pre-commit hook テンプレ**。staged file に arch-check を回し、Claude を介さない人間のローカル commit も捕捉する。
- **`templates/ci/README.md`** — 3 層強制 (PreToolUse / pre-commit / CI) の解説と consumer repo への vendor 手順。

### Rationale

「クリーンアーキを本気で守りたい、二度と drift させたくない」という要件に対し、PreToolUse hook だけでは **Claude-scoped** で穴がある (環境依存で静かに消える)。同じ `.bootstrap-arch` 契約を CLI 化して **CI (bypass 不可の最終砦) + git pre-commit (ローカル全員) + PreToolUse (即時)** の 3 層で強制する。これで「Claude 経由でも人間経由でも、宣言した依存方向に反したら必ず止まる」状態を作る。

## [0.8.2] - 2026-05-25

### Changed

- **lint gate (`block-commit-if-lint-fails.sh`) を opt-in 化** (`.bootstrap-lint` マーカー)。always-on だと、lint script はあるが linter が未設定なリポ (例: `next lint` が ESLint 未設定で対話プロンプト→exit 1) を巻き込んで commit を壊す。`.bootstrap-arch` / `.bootstrap-lane` / `.bootstrap-protected` と同じ「project が明示宣言したら効く」思想に統一。雛形 `templates/.bootstrap-lint`。
- **arch commit gate (`block-arch-violations.sh`) を staged file のみ検査に変更**。従来は全 tracked file を scan していたため、既存の依存方向 debt があるリポでは無関係な commit まで全ブロックされ adopt 不能だった。`git diff --cached --name-only` の staged file だけ検査する正しい pre-commit セマンティクスにし、既存 debt は止めず新規/変更分の違反だけ捕まえる (全 repo 網羅 scan は CI の領分)。edit 時の早期 gate (`block-cross-layer-import.sh`) は従来どおり。

### Rationale

propagate-ai (運用中リポ) への 0.8.x 適用を検証する中で 2 つの adoption 阻害を発見: (1) lint gate が always-on で、ESLint 未設定の `next lint` を回して commit をブロックしてしまう。(2) arch commit gate が全 tracked を scan するため、既存 debt 13 件のあるリポでは全 commit がブロックされる。どちらも「既存リポに後から安全に adopt できない」問題で、opt-in 化 + staged-only で解消。プラグインの一貫した原則 (project-local 宣言で opt-in / 触ったものだけ gate) に揃えた。

## [0.8.1] - 2026-05-25

### Fixed

- **`plugin.json` の `"hooks": "./hooks/hooks.json"` を削除**。Claude Code (native 2.1.x) は標準パス `hooks/hooks.json` を**自動ロード**するため、`manifest.hooks` で同じファイルを明示参照すると二重ロードで `Hook load failed: Duplicate hooks file detected` エラーになる (`/doctor` で検出)。`manifest.hooks` は標準パス以外の追加 hook ファイル専用。標準パスは記述しなくても自動発火する。0.4.0 以降潜在していたが、CC が標準パス自動ロードに対応して顕在化した。

## [0.8.0] - 2026-05-24

### Added

- **`hooks/block-commit-if-lint-fails.sh`** (Hook J, Bash git commit) — commit 時に project の lint command を実行し fail なら `exit 2`。「綺麗なコード」のうち **linter が見る deterministic な層** (命名規約 / format / 未使用 / 複雑度しきい値) だけを強制する。命名の質・設計のセンスといった taste は対象外 (= metric で縛ると不自然な分割を誘発し逆効果。人間レビュー / `code-review` skill の領分)。プラグインが綺麗さを判断せず project の linter に委ねる (= depcruise を arch で使うのと同思想)
  - 検出: `package.json` の `"lint"` script (`npm run lint`) / `ruff` / `flake8` / `golangci-lint` / `cargo clippy` / `rubocop`。**全分岐に `command -v` ガード** (= 0.7.0 で踏んだ「runner 不在で誤 block」を最初から回避)。解決できなければ warn して素通し
  - `tests/hooks/block-commit-if-lint-fails.test.bash` で TDD

### Rationale

「綺麗なコードを書く最強プラグイン」かを精査した結果、命名/分割/可読性の**質 (taste)** は ① Claude が default で外さない ② deterministic に検査できない の両方で gate に不適 (= metric は逆効果) と確認。一方「綺麗さ」のうち **linter が見る層は deterministic で project-local**。test は gate していたのに lint は gate していなかった穴を埋める。taste は引き続き review に委ねる。

## [0.7.0] - 2026-05-24

並列開発を「防御 (= ぶつからない)」から「分業して組み戻す generative フロー」へ拡張し、さらに **依存方向 (architecture) の deterministic 強制** を追加。あわせて全 hook に bash テストを整備し、その過程で既存 hook の実バグ 3 件を修正した。

### Added

- **依存方向の強制 (architecture)** — 大規模化で壊滅的になるアーキ境界の侵食を deterministic に防ぐ。SOLID を散文で recite するのではなく、依存辺を hook で強制する (= 0.4.0 で消したのは「散文 advisory」で、これは「維持の gate」。establish と preserve を分離):
  - **`hooks/lib/arch-check.sh`** — 依存方向エンジン。project-local `.bootstrap-arch` (layer glob / alias / allow 辺) を parse し、layer 判定 / import specifier 解決 / 違反検出を行う。jq 非依存、pure bash。cross-layer は default-deny。対応言語 ts/tsx/js/jsx/mjs/cjs/py
  - **`hooks/block-cross-layer-import.sh`** (Hook I, Edit|Write|MultiEdit) — 禁止 import を書いた瞬間 `exit 2`。PreToolUse 時は新内容が disk に無いので hook input を unescape して検査
  - **`hooks/block-arch-violations.sh`** (Hook H, Bash git commit) — commit 時に宣言 layer 配下の全 tracked file を権威検証。どの commit も契約を満たすことを保証
  - **`templates/.bootstrap-arch`** — 依存方向契約の雛形。`.bootstrap-arch` 不在なら全 arch hook は fail-open
  - `SKILL.md` に「依存方向を強制する (architecture)」節 (establish vs preserve / port で依存反転 / 1 アーキ判断 = 1 ADR)

- **並列開発フロー (sprint)** — 1 feature を複数 Claude で安全に分業して統合する generative フロー。scrum の本質は「並列の最大化」でなく WIP 制限:
  - **`hooks/block-out-of-lane-edit.sh`** (Hook G) — 各ワーカーの worktree root の `.bootstrap-lane` (1 行 1 glob) 範囲外の編集を `exit 2`。「1 task = 1 owner = 1 worktree」を物理境界化。lane file 不在なら fail-open
  - **`hooks/block-push-to-protected.sh`** (Hook F) — `.bootstrap-protected` で宣言した branch への直接 push を block。feature branch + integrate 経由に矯正。**opt-in** (= `.bootstrap-protected` が無ければ発火しない。`.bootstrap-lane` / `.bootstrap-arch` と同じく project-local 宣言で発火する一貫性。solo / 個人 repo は妨げない)。glob 対応 (`release/*` 等)。雛形 `templates/.bootstrap-protected`
  - **`skills/sprint-plan/SKILL.md`** — feature を scope 非重複 task に分解、共有 interface を直列 spine (`depends_on`) に切り出し、`wip_limit` 個まで worktree + lane を用意、ワーカー起動文を出力。並列が得でないなら逐次を勧める
  - **`skills/integrate/SKILL.md`** — 依存順 merge + 統合 verify (全 suite) + claim close + worktree 撤去
  - **`docs/sprint/board.json`** schema + `templates/docs/sprint/` 一式 (board / WIP 制限 / 直列 spine)
  - `SKILL.md`「並列 Claude 安全運用」に「並列開発フロー (sprint)」節を追加。AI 癖 9 に対応する hook を拡充

- **`tests/hooks/` — 全 hook の bash テスト**。jq 非依存・bats 非依存の自作ハーネス (`helper.bash` / `run.sh`)。10 suite。「TDD を強制するプラグインが自分ではテスト皆無」だった穴を解消 (= 0.4.1 の Windows path 回帰も pin)。並列フローの dogfood (4 hook テストを 4 worktree で並列 backfill → integrate) で実証

### Fixed

- **`block-cross-claude-wip.sh` の `--amend` 丸ごと除外を撤廃**。実事故 (共有 index で別 Terminal の staged 14 file が `git commit --amend` に巻き込まれ origin/main へ push) の真因。共有 index では amend こそ他 session staged を最も巻き込む経路。message-only amend (index clean) は staged 空で素通しになり over-block しない
- **`block-dangerous-git-ops.sh` が `git clean -fd` / `-fx` を見逃していた**バグ。regex が `f` を flag cluster 末尾に固定していたため、canonical な destructive 形が素通しだった (header コメントは block と謳っており doc が嘘になっていた)。`f` を cluster 内の任意位置で検出するよう修正。**dogfood の特性テストが発見**
- **`block-add-all.sh` が `git stash push -m msg -- <pathspec>` を過剰 block**。`-m` 検出後に pathspec を再チェックせず block していた。`--` pathspec があれば通すよう修正。**dogfood が発見**
- **`block-commit-if-tests-fail.sh` の go/Cargo/Gemfile 分岐に `command -v` ガードが無く**、toolchain 不在マシンで存在しないコマンド実行 → 非ゼロ → commit を誤 block していた (pyproject 分岐だけガード有りで非一貫)。全分岐に runner 存在チェックを追加。**dogfood が発見**

### Changed

- **`hooks/hooks.json`**: hook を 5 → 9 に拡張。`Edit|Write|MultiEdit` に lane / 依存方向 edit / test 先行、`Bash` に bulk-stage / destructive / cross-session WIP / 直 push / 依存方向 commit / test の順で登録
- **`plugin.json` / `marketplace.json`** の `version` を 0.7.0 に、`description` に依存方向強制 / 並列開発フロー / sprint-plan・integrate skill を反映
- **`README.md`** の「何を強制するか」「提供物」を更新 (依存方向 / 並列フロー / 新 hook 9 個 / arch-check エンジン / tests/ / sprint-plan・integrate)
- **`hooks/README.md`** に Hook F / G / H / I を追記、発火順を Edit 系 / Bash 系に分けて再掲

### Rationale

propagate-ai の実運用で「共有 index + `--amend` で他 session の WIP が origin/main に混入」する事故が発生。現状の防御 hook は `--amend` を除外しており止められなかった。これを起点に、並列 Claude 支援を防御から **分業/統合フロー** へ拡張。worktree = lane = 1 owner を `.bootstrap-lane` + hook で物理境界化し、共有 index 事故を構造的に不可能にする。

また「大規模化でアーキテクチャが効く」のは確立 (establish) と維持 (preserve) を分けたとき。0.4.0 で SOLID 散文を消したのは正しい (Claude が既知、recite は advisory bloat) が、**依存方向の維持には deterministic な gate が要る**。これを project-local `.bootstrap-arch` + 汎用 hook で実装した (= propagate-ai 専用にせず、全 project が自分の契約を宣言する形)。

## [0.6.0] - 2026-05-23

### Added

- **`skills/handoff/SKILL.md` を新規追加** (= session の cold restore を default 挙動化)。session 終了前 / `/clear` 前 / 並走 Claude に context を渡す前に AI が default で呼ぶ。`docs/handoffs/<YYYY-MM-DD>-<topic>.md` を 7 節 (1 行サマリ / 残課題表 / バックグラウンドプロセス / 触ったファイル分類 / memory references / 検証手順 / コピペ起動文) で生成する規律。slash command `/handoff` でも明示呼び出し可能。AI が「次の Claude が cold restore できるか」を 1 回ごとに考える経路を default 化する。

- **`skills/incident/SKILL.md` を新規追加** (= 事故記録 + memory 昇格を default 挙動化)。fix / revert / hotfix commit / user 叱責 / 「やり直し」言及 / 同問題 2 回以上発生 の後に AI が default で呼ぶ。`docs/incidents/<YYYY-MM-DD>-<topic>/README.md` を 4 節 (ミス一覧 / 真因 / 構造的再発防止 / 関連 memory・docs) で生成。**書きっぱなしを禁止**し、memory `feedback_*.md` / `reference_*.md` への昇格まで責務に含める (= incident は session 開始時に load されないが memory は load される、これを欠くと再発抑止しない)。slash command `/incident` でも明示呼び出し可能。

- **`templates/docs/` 雛形を追加**。AI 駆動開発で本当にレバレッジが出る 3 ディレクトリのみ提供:
  - `templates/docs/README.md` — 採用 3 dir の歩き方、真実の所在表、失敗兆候 4 種 (権威分散 / handoff 重複化 / ADR 未定着 / business 固有名混入)、不採用 5 dir (current / exploring / reference / ops / archive) の理由
  - `templates/docs/handoffs/TEMPLATE.md` — 7 節 cold restore 骨格 (= 1 行サマリ / 残課題 / バックグラウンドプロセス / 触ったファイル / memory references / 検証手順 / コピペ起動文)
  - `templates/docs/decisions/TEMPLATE.md` — ADR template (Status / Date / Deciders / References / Context / Decision / Consequences)
  - `templates/docs/incidents/TEMPLATE.md` — incident template (ミス一覧 / 真因 / 構造的再発防止チェックリスト / 関連 memory)

- **`skills/project-bootstrap/SKILL.md` に新節「external memory として docs/ を整備」を追加**。採用 3 dir / 真実の所在表 / 失敗兆候 4 種 / 関連 skill リンクを規律として記述。CLAUDE.md / コード / memory との二重化を禁じる。

- **「迷ったとき」チェックリストを 8 → 11 項目に拡張**: handoff 書き残し / incident + memory 転記 / ADR 記述 を追加。

### Changed

- **`.claude-plugin/plugin.json` / `marketplace.json` の `description` を更新**: skills 4 個構成 (project-bootstrap / plan / handoff / incident) と「external memory として docs/ 整備」を明示。
- **`README.md` の「提供物」表を更新**: `skills/handoff/` / `skills/incident/` / `templates/docs/` の 3 行を追加、skill 一覧と install 手順を 4 skill 構成に書き直し。
- **`README.md` の「使い方」step 2 を更新**: `templates/docs/` のコピー手順を追記、3 dir 採用と 5 dir 不採用の方針を明示。

### Rationale

propagate-ai リポジトリの docs/ 8 ディレクトリ構造 (= current/ exploring/ decisions/ reference/ ops/ handoffs/ incidents/ archive/) を AI 駆動レバレッジ基準で精査した結果、`handoffs/` (= cold restore) と `decisions/` (= ADR) と `incidents/` (= 事故記録 + memory 昇格) の 3 dir が本当に効くと判定。残り 5 dir は CLAUDE.md / コード / memory で代替できるか graveyard 化する典型兆候 (= `archive/` 参照 2 hit / `decisions/` 1 件 / `exploring/` 肥大化 / `current/` と CLAUDE.md 重複) が出ており、雛形に含めないことで失敗を構造的に防ぐ。

handoff / incident は **slash command で起動する advisory 形式ではなく AI default 挙動として書く** ことが本旨 (= ルール = default + hook 強制原則)。skill description で「いつロードするか」を明示し、AI 自身が session 終了前 / 事故後に呼ぶ経路を作る。

## [0.5.0] - 2026-05-23

### Added

- **並列 Claude 安全運用の hook 3 個をデフォルト発火に追加** (= `plugin.json` の `hooks` フィールド経由)。AI 駆動開発で複数ターミナル / 別 session の Claude を並走させる場合に、互いの作業を消す / 巻き込む経路を default で blocking する規律。SKILL.md advisory ではなく hook で deterministic に強制する (= Anthropic 公式「Hooks are deterministic, CLAUDE.md is advisory」整合):
  - **Hook C** (`hooks/block-dangerous-git-ops.sh`): `PreToolUse on Bash`。destructive git op を `exit 2` で blocking。検出: `git reset --hard` (uncommitted 全消去) / `git push -f` / `--force` (remote の他人 commit 消去、ただし `--force-with-lease` は競合検出付きで素通し) / `git checkout -- .` / `<path>` (unstaged 消去) / `git restore .` / `--staged .` (全 restore) / `git clean -f` / `-fd` / `-fx` (untracked 消去) / `git branch -D` (未 merge branch 強制削除)
  - **Hook D** (`hooks/block-add-all.sh`): `PreToolUse on Bash`。bulk-staging を `exit 2` で blocking。検出: `git add -A` / `--all` / `.` / `-u` / `--update` (cwd 配下全 stage) / `git commit -a` / `-am` / `--all` (全 tracked auto-stage) / `git stash -u` / `--include-untracked` / `git stash` (path 指定なし、全 modified 退避)。**自分が編集した file を個別 path 指定で add する**規律を強制。`git add path/to/file` は素通し
  - **Hook E** (`hooks/block-cross-claude-wip.sh`): `PreToolUse on Bash` for `git commit`。当 session で編集していない file が staged にあれば `exit 2` で blocking。仕組み: hook input の `transcript_path` から JSONL を読み、`Edit` / `Write` / `MultiEdit` / `NotebookEdit` の `file_path` / `notebook_path` を抽出して self-edited set を build、`git diff --cached --name-only` の各 file が含まれているか check。`--amend` は対象外。transcript path 取得不能環境では fail-open (= 素通し + warning) で AI 有用性を優先

- **`skills/project-bootstrap/SKILL.md` の verification 章を 4 罠に具体化**。「実体を read-back で検証」だけでは AI が default で踏む 4 つの落とし穴を明示:
  - **罠 1 — silent failure を「正常」と読む**: ORM/SDK が missing field / drop 済 column を throw せず空返却する設計に依存して 0 件返却を success と読む。`count == expected` を必ず assert、200 OK だけでなく content-type / body 構造まで assert
  - **罠 2 — 既存リソースの actual capability を表記で推測する**: 資格情報 / token / API key / feature flag / 設定値の現在能力を、コメント / 変数名 / 定数で代用しない。新 code 追加判断の前に actual state を 1 query で確認
  - **罠 3 — escape 多段を脳内計算する**: shell → JSON → 言語 string → 外部 storage の多段 escape は書込後に必ず read-back し、stored 文字列と入力文字列の完全一致を assert
  - **罠 4 — pattern を広げる fix の cohort 副作用を測らない**: regex / filter / 集計範囲を拡張する fix は対象 cohort の前後数を取り、想定外の cohort 増加が無いか assert

- **AI の癖を 6 → 9 個に拡張**:
  - **7. 「ない / 不可能 / 該当なし」を grep の不一致で断定する** — app code grep が hit しない ≠ 機能不在 (= 設定 / 資格情報 / 外部リソース経由で可能なケースが残る)。外部 API の error code を即「権限不足」と一般化しない。不在主張の前に対象リソース自身への diagnostic を最低 1 回叩く
  - **8. ルール / memory / fix を射程外まで過剰一般化する** — 「X は NG」を文字通り全 X に適用、本来 OK だった subset まで潰す。ルール記述時は「射程: ~ のみ。~ は除外」を必ず添える
  - **9. 共有環境を独占資源として扱う** — `git add -A` で他 session の WIP を巻き込む、destructive git op で他人の commit / untracked を消す。commit は個別 path 指定 / destructive op は user 明示承認 / 並走は `git worktree add` で物理隔離

- **新節「並列 Claude 安全運用」を SKILL.md に追加**。同一 working tree 共有 vs `git worktree add` 物理隔離の選択表、hook で強制される事項のリスト、hook で強制しきれない手順 (= `git status --porcelain` 確認 / lock file diff 確認 / destructive op 前の user 確認)

- **新節「完遂責任 — bug fix と同 PR で cohort audit」を SKILL.md に追加**。問い合わせ件数は氷山の一角で同根 silent dropout が桁違いに居る前提、fix commit と同 PR に同根 cohort の SQL / grep / log scan 結果を含めることを規定

- **「迷ったとき」チェックリストを 6 → 8 項目に拡張** (= cohort audit / 巻き込み確認を追加)

### Changed

- **`hooks/hooks.json` の `PreToolUse on Bash` matcher 配下に新 hook 3 個を追加**。発火順は `block-add-all.sh` → `block-dangerous-git-ops.sh` → `block-cross-claude-wip.sh` → 既存 `block-commit-if-tests-fail.sh` (= 巻き込み block を test 実行より前に置く)
- **`.claude-plugin/plugin.json` / `marketplace.json` の `description` を更新**: 並列 Claude 安全運用 / verification 4 罠 / AI 癖 9 個 / cohort audit を明示
- **`hooks/README.md` を 50 行 → 100 行に拡張**: 新 hook 3 個の検出 pattern 表、発火順、bypass 手順を追記
- **`README.md` の「何を強制するか」を 4 項目 → 6 項目に拡張**: 並列 Claude 安全運用節、AI 癖 9 個への変更、bug fix 完遂責任を反映

## [0.4.1] - 2026-05-21

### Fixed

- **`hooks/require-test-companion.sh` の Windows path 正規化が壊れて全 skip 経路が機能不全だった bug を修正**。Claude Code は Windows 環境で `\` 区切りの絶対 path を JSON-escape 済 (= literal `\\`) で渡してくるが、旧実装は path 正規化を持たず `case` パターン (`*/tests/*` 等の skip ルール) が一切 match しなかった。`tr '\\\\' '/' | tr -s '/'` で確実に正規化する経路に置換 (= `sed -e 's|\\|/|g'` は Git Bash の GNU sed で「unterminated `s' command」を吐いて空文字列を返す)。Windows ユーザーが Edit/Write を呼ぶたびに「テスト書け」blocking が出続けていた重度の hook 誤動作。
- **`scripts/_*` skip ルールを追加**。`scripts/_foo.mjs` のような prefix `_` 付きスクリプトは慣行として ephemeral debug / one-shot recovery 用途 (= test companion を要求するのは過剰)、case パターンで素通しに。
- **`tests/` 配下の深い階層を recursive `find` で拾う fallback を追加**。既存 CANDIDATES は `tests/${NAME}.test.${EXT}` 直下のみだったため、`tests/unit/<layer>/foo.test.ts` のような層別構造で red test 済みでも hook が誤検知していた。

## [0.4.0] - 2026-05-13

### Changed (BREAKING)

- **`skills/project-bootstrap/SKILL.md` を 430 行 → 96 行に prune**。Anthropic 公式 best practice ([code.claude.com/docs/en/best-practices](https://code.claude.com/docs/en/best-practices)) の include/exclude 表に従い、exclude 該当節 (SOLID / KISS / YAGNI / DRY / Fail-fast / Root-cause / Composition over Inheritance / Law of Demeter / SOLID 5 原則詳細 / アーキテクチャ指針 / コード品質節) を全削除。これらは Anthropic の言う「Standard language conventions Claude already knows」「Self-evident practices like 'write clean code'」に該当し、bloated CLAUDE.md / SKILL.md は AI に instructions を無視させる ("Bloated CLAUDE.md files cause Claude to ignore your actual instructions")
- 新節「ルールとは」を追加: **ルール = AI が常にそう振る舞うこと**。slash command / 明示呼び出しは advisory にすぎず規律ではない、と明示
- 新節「最高レバレッジ — verification を必ず与える」を追加。Production-affecting な変更は return / commit 前に read-back / assert で実体検証することを要求 (= Anthropic の "single highest-leverage thing")
- AI の癖リストに 6 つ目「**抽象用語に逃げる**」を追加: 「構造」「パターン」「集約」「再設計」「反転」「Bottom-up」のような語を使うときは具体物 (ファイル + 行 + 引用) を必ず添える
- 「**同類のバグが 2 回以上出たら構造の症状を疑う**」を明示 (= Anthropic の "If you've corrected more than twice, A clean session with a better prompt outperforms a long session" のプロジェクトレベル翻訳)

### Removed (BREAKING)

- **`commands/red.md` / `green.md` / `refactor.md` を削除**。slash command は advisory (= ユーザーが叩かないと発動しない) なので規律として機能しない。TDD は hook で deterministic に強制する設計に変更。subagent (`agents/test-writer.md` / `implementer.md` / `refactorer.md`) は残し、SKILL.md から AI が default 経路として呼ぶ
- **`examples/` ディレクトリを削除** (README + TEMPLATE のみで収録 0 件、YAGNI 違反)。必要になった時点で再作成する
- **`hooks/hooks.example.json` を削除**。本番 `hooks/hooks.json` で代替

### Added

- **`hooks/hooks.json` + `.claude-plugin/plugin.json` の `hooks` フィールド登録**: プラグインインストール時にデフォルト発火する hook を 2 つ提供:
  - **Hook A** (`hooks/require-test-companion.sh`): `PreToolUse on Edit|Write|MultiEdit`。実装ファイルを編集する瞬間、対応する test ファイルが慣例パターン (`*.test.*` / `*.spec.*` / `*_test.*` / `test_*.py` / `_test.go` / `spec/*_spec.rb` / `tests/` / `__tests__/`) で見つからなければ `exit 2` で **blocking**。「テスト書かずに実装」を構造的に不可能にする (= Red phase 強制)
  - **Hook B** (`hooks/block-commit-if-tests-fail.sh`): `PreToolUse on Bash` for `git commit`。プロジェクトマーカー (`package.json` / `pyproject.toml` / `go.mod` / `Cargo.toml` / `Gemfile`) から test command を自動検出して実行、fail なら `exit 2` で **blocking**

### Pruned (non-breaking)

- `templates/CLAUDE.md` を 100 行 → 55 行に削減。ガイドライン要点 5 個 (Code is Truth / TDD / SOLID-KISS-YAGNI / 環境隔離 / AI 協働ルール) を削除 (= 詳細は SKILL.md にあり、CLAUDE.md には書き写さない)
- `README.md` を 147 行 → 60 行に削減。Phase 1-7 完了表、旧ディレクトリ構成図、ロードマップを削除
- `MAINTENANCE.md` を 126 行 → 28 行に削減。リリース手順のみ残し、定期レビュー観点 / 新プリミティブ判定基準 / 廃止フロー節を削除 (= YAGNI、必要になったら再導入)
- `hooks/README.md` を 80 行 → 46 行に削減。「なぜテンプレ止まりか」「3 通りの有効化方法」節を削除 (= hooks.json デフォルト発火化により不要)

## [0.3.0] - 2026-04-26

### Added

- `skills/project-bootstrap/SKILL.md` の Part 1 (憲法) に「**環境隔離 — プロジェクト単位で依存を閉じ込める**」原則を追加。グローバルにライブラリをインストールしないこと、CLI ツールは `uv tool install` / `pipx` / `cargo install` 等の isolated tool installer 経由で入れること、`.venv` / `node_modules` 等は必ず `.gitignore` で除外することを規定。Python / Node / Rust / Go / Ruby の言語別具体策を表で添付。
- `templates/CLAUDE.md` のガイドライン要点リストに環境隔離原則の bullet を 1 行追加。

## [0.2.0] - 2026-04-26

### Added

- `skills/plan/SKILL.md` — `/plan` skill (探索 → 計画 → 提示)。自明でないタスクの開始時に呼び出し、`Read` / `Grep` / `Glob` のみで探索し、構造化された計画書を出力する。`Edit` / `Write` は禁止。ユーザー承認後に TDD フロー (Red → Green → Refactor) へ移行する。
- `agents/test-writer.md` — TDD Red フェーズを担うサブエージェント。failing テストだけを書く。実装ファイルは触らない。テストを実行して fail を確認するまでが責務。
- `agents/implementer.md` — TDD Green フェーズを担うサブエージェント。failing テストを通す最小の実装だけを書く。テストファイルは編集しない。広めのテストスイートで regression がないことまで確認する。
- `agents/refactorer.md` — TDD Refactor フェーズを担うサブエージェント。テストが pass し続ける範囲で構造改善する。テストは変更しない。
- `commands/red.md`, `commands/green.md`, `commands/refactor.md` — `/red` / `/green` / `/refactor` slash command。それぞれ対応するサブエージェントを起動する thin wrapper。
- `.claude-plugin/marketplace.json` — このリポジトリを自己ホスティング marketplace 化する catalog。`rintaro-yamaoka` marketplace として `project-bootstrap` プラグインを listing する (github source は自リポジトリを指す)。
- `LICENSE` — MIT License。
- `plugin.json` に `homepage` / `repository` / `license` フィールドを追加。

- `hooks/README.md` — hook テンプレート集の運用ガイド。なぜテンプレート止まりか、どこで有効化するかの 3 通り、各テンプレートの意図とカスタマイズ箇所を解説。
- `hooks/hooks.example.json` — 3 つの hook 例 (git commit 前テスト / 実装 edit 後テスト companion 確認 / SessionStart reminder)。`plugin.json` の `hooks` フィールドには登録しないため、デフォルトでは発火しない。
- `examples/README.md` — TDD セッションログを蓄積する場所の運用ガイド。命名規則 / 追加方法 / 注意点を記述。
- `examples/TEMPLATE.md` — セッションログのフォーマット雛形 (タスク → /plan → Red → Green → Refactor → Close → 振り返り)。実プロジェクトで稼働した実例を後日蓄積する。
- `MAINTENANCE.md` — 運用ドキュメント。SemVer 方針 / リリース手順 / 定期レビューの観点 / 新プリミティブ追加の判断基準 / 廃止フロー を記述。プラグインを長く使えるものに育てるための保守規律。

### Changed

- README の install 手順を更新: `claude --plugin-dir` だけでなく `/plugin marketplace add` 経由の install を案内。
- README のライセンス節を「未定」から「MIT」に確定。

## [0.1.0] - 2026-04-25

### Added

- Claude Code プラグインとしての構造を確立
  - `.claude-plugin/plugin.json` — プラグインマニフェスト (name / version / description / author / keywords)
  - `skills/project-bootstrap/SKILL.md` — AI 駆動開発の憲法 (旧 root の SKILL.md を `git mv` で移動)
- `templates/CLAUDE.md` — 新規プロジェクトに配置する CLAUDE.md の雛形
  - プロジェクト概要 / 技術スタック / 開発コマンド / ディレクトリマップ / アーキテクチャ概略 / プロジェクト固有の規約 / 既知の地雷 / AI 作業時の特記事項のスロットを含む
- `README.md` — リポジトリの目的・哲学・使い方・ロードマップ
- `CHANGELOG.md` — このファイル

### Changed

- `SKILL.md` を三層構成 (憲法 / TDD ワークフロー / AI 協働ルール) に再編
  - 憲法層: SOLID / KISS / YAGNI / DRY (Rule of Three) / Fail-fast / Root-cause / Composition over Inheritance / Law of Demeter / アーキテクチャ指針
  - 開発フロー層: Red → Green → Refactor を軸とする TDD 中心のフロー (旧フローを TDD ループに統合)
  - AI 協働ルール層: AI の既定の癖の言語化 / Subagent によるフェーズ分離 / Plan-Execute 二段構え / AI 指示テンプレート / やってよいこと/やってはいけないことの整理

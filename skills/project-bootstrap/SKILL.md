---
name: project-bootstrap
description: 上位1％の AI 駆動開発を個人の規律でなく構造として default 化する規律。純粋な強制は到達不能なので強制を4つの設計判断に作り替える = ① 分解 (precondition を fail-closed で強制・判断は逃さない) / ② 信号選び (行為を信号に・fail-mode を選ぶ) / ③ 配備の可視化 (効いていない強制を無音にしない) / ④ 計測つきの取引 (緩めるなら戻る根拠を metric で持つ)。Anthropic 公式 best practice (verification 最高レバレッジ / hooks deterministic / CLAUDE.md advisory) に整合する。verification 4 罠 / AI の癖 9 個 / TDD ループ / 根本修正 / 並列 Claude 安全運用 / subagent の mutation は隔離 worktree + 統合関所つきで可 (hook は subagent にも効く: 2026-06-11 実測検証、ADR 0004) / 環境隔離 / external memory として docs/ 整備 (handoffs / decisions / incidents)。新機能・バグ修正・リファクタ・調査など、あらゆるコーディング作業で常にロードする。
---

# AI 駆動開発の規律

## ビジョン — 上位1％の AI 駆動開発

AI を使うこと自体はもう差別化にならない。本プラグインが目指すのは、AI の速度を壊さずに引き出しきる **上位1％の AI 駆動開発** を、個人の規律 (= 忘れられる) でなく **構造として default 化する** こと。その手段が以下の「強制の技芸」である。

## 強制の技芸

**規律 = AI が常にそう振る舞うこと**。明示コマンドで初めて発動する形式 (slash command / 明示 subagent 呼び出し) は advisory にすぎず、忘れられる。だから hook で deterministic に強制し、違反を blocking する。

> Anthropic 公式 (https://code.claude.com/docs/en/best-practices):
> "Hooks are deterministic and guarantee the action happens. Unlike CLAUDE.md instructions which are advisory."

ただし **純粋な強制はほとんどの実規律で到達不能** である (= 判断・配備・throughput は hook で縛りきれない)。諦めるのでなく、強制を以下4つの設計判断の連なりに作り替える。

### ① 分解 — precondition は強制し、判断は逃さない

規律を [強制可能な precondition] と [既約な判断] に割る。判断そのもの (= 良い test を書く / 並列が得かを見抜く) は強制できないが、**「判断を済ませた」という precondition は強制できる**。TDD hook が test の質を保証できなくても test の存在を強制するのと同型で、sprint 発火 gate (`hooks/block-unplanned-feature-build.sh`) も「sprint 判定の記録」を新規 source 面作成の precondition にする。判断を advisory に逃さない。

強制の射程は**外部前提に依存し、変わる**。かつて PreToolUse hook は subagent で発火せず (ADR 0001 / upstream `#21460`)、射程外で mutate しない設計に回避していた。upstream 修正 (2026-05-29 close) を**実測で検証**し (2026-06-11)、現在は subagent にも hook が届く — 回避は撤回し、関所は「どの方式でも必ず通る統合の入口」に置く (ADR 0004)。外部前提は閉じたら再検証する。

### ② 信号選び — 行為を信号にし、fail-mode を選ぶ

gate は **proxy でなく行為そのもの** を信号にする (= sprint gate は prompt の語彙ではなく「新規 source file を作る行為」を信号にする。語彙は言い回しに穴が空く proxy)。fail-mode は意図的に選ぶ: **解析不能 = fail-closed** (判定できないなら止める) / **根拠不在 = fail-open** (非対象 project を妨げない)。ephemeral state は「存在」でなく **「活性」** で読み (= board.json の有無でなく未完了 task の有無。実事故: `docs/incidents/2026-06-07-stale-board-gate-bypass`)、終端処理 (archive) を所有 skill の責務にする。

### ③ 配備の可視化 — 効いていない強制を無音にしない

**hook は消費先 repo で現行版が実際に走って初めて効く**。設計が正しい gate も未配備 / 部分 vendoring の repo では無音で効果ゼロになる (実事故: `docs/incidents/2026-06-02-coverage-drift-silent`。とりわけ sprint 発火 gate は build 前の判断ゆえ CI 後追いができず PreToolUse hook 以外に backstop が無い)。だから強制は自身の **配備カバレッジを可視化する meta 層** を持つ: SessionStart hook (`hooks/bootstrap-session-doctor.sh`) が起動時に採用状態を audit し、**未採用なら導入を一度だけ尋ね / 採用済みで配備漏れ (partial) なら警告** する (= 採用は consent ゆえ強制不能だが、状態の可視化はできる。enforcement の本体は per-action gate)。plugin 非依存の team-wide net は `templates/ci/bootstrap-doctor.yml`、判定エンジンは `scripts/doctor.sh` (ADR 0003)。同じ可視化原理を **repo drift** にも適用する (`hooks/lib/repo-drift.sh`、ADR 0003 の延長): 採用状態と独立に、`HEAD` の `origin/main` 遅れ (stale checkout = 本番操作前の追従確認漏れ) と **merge 済みなのに残っている worktree** (lane 撤去漏れ) を session 起動時に surface する — どちらも「どの checkout/lane が正しいか」は既約な判断なので強制せず事実だけ出す。

### ④ 計測つきの取引 — 緩めるなら戻る根拠を持つ

強制を **throughput と引き換えに意図的に緩める** 層がある。人間の全 diff 直列レビューはレビュー帯域が律速なので、一次レビューを read-only AI に移し人間は verdict + サンプルだけ読む (trust ladder Stage 2、`hooks/block-unreviewed-merge.sh`)。これは advisory への退行ではない — **客観 metric (`scripts/velocity.sh` の defect rate) で「いつ1段戻すか」を持つ管理された取引** である。計測なき緩和は盲信に戻る。

ただし**採点者が 1 人 (= 単一 orchestrator) の間は、この取引の限界を正直に名指しする**: defect rate を測る人とレビュー帯域の律速が同一人物なので、独立統制でなく **self-report に近い** (= 自己採点の円環の throughput 版)。2 人目の独立した採点者が出るまでは「速くした」を self-report として扱い過信しない (= dogfood の単一 orchestrator frontier。`velocity.sh` の冒頭にも明記)。これは取引を否定するのでなく、その**限界を無音にしない** (③ の自己適用)。

## 最高レバレッジ — verification を必ず与える

Production-affecting な変更 (= 外部 API write / DB write / repo push / 設定書込 / 公開サイトへの影響) を含む実装は、return / commit の前に **実体を read-back で検証** してから完了とする。これを欠くと「return value が success だが live は反映されていない」事故が起きる。

> Anthropic 公式:
> "Give Claude a way to verify its work. This is the single highest-leverage thing you can do. If you can't verify it, don't ship it."

**何を動作テストすべきかの設計は `verification` skill が担う (ADR 0007)**。コードレベルのバグは TDD hook が潰すが、残余リスクは**継ぎ目** (cross-repo 契約 / 要件 / 「実物を見ずの完了」/ 環境) に移動しており、それらは repo 内 unit test の射程外で、緑のテストが誤った契約を固定して false confidence を配る (mood incident)。原則 = **テストは実装からでなく意図と跨いだ境界から導く**。各行に**外部オラクル**を与え (オラクルが AI 内なら著者=採点者の円環)、最終オラクルが人間にしか出せない行は `HUMAN` でフラグする。各 PASS の前に kill-question「このテストが緑のまま、ユーザーが困る状態はありうるか?」を問う (Yes ならオラクルが誤り)。成果物 `docs/verification/<branch>.md` は lane merge の precondition (`block-merge-if-verification-unclosed.sh`)。

verification を「素朴な return チェック」で済ますと AI は以下 4 罠に default で落ちる:

### 罠 1 — silent failure を「正常」と読む

`200 OK` / 空配列 / `null` / 0 件返却を success とみなさない。多くの ORM/SDK は missing field / drop 済 column / 存在しない resource を **throw せず空返却する** 設計になっている。

実装パターン:

- `count == expected` を必ず assert (= 「0 件返ってきた = エラーなし」ではない)
- HTTP `200` だけでなく content-type / body の構造まで assert
- 「`success: true` が返った」だけで完了としない、書き込んだ key/id で実 read-back
- **同期の「自分の返答を読み返す」だけでは async / scheduled の無音 skip を捕まえられない** — cron が条件で 1 件を弾いて何もログを残さない (リマインダが永遠に飛ばない) / daemon の heartbeat は生きているのに work queue が stall する、には *読み返す自分の返答が存在しない*。これらは AI の外の本番計器 (アラート / 日次集計「CV>0 かつ予約=0」) をオラクルにする (verification skill `kind=monitor`、async 行は実 monitor で裏打ち)

### 罠 2 — 既存リソースの actual capability を表記で推測する

資格情報 / token / API key / feature flag / 環境変数 / 設定値の「現在の能力」を、ソース上のコメント / 変数名 / 定数で代用しない。実 capability と「過去に設定された意図」は乖離する。

実装パターン:

- 新 code 追加判断 (= 新資格情報 / 新 endpoint / 新 consent flow) の前に、actual state を 1 query で確認
- token の actual scope / DB の actual schema / API の actual rate limit を、対象リソース自身に query して確定させる
- 「コメントに書いてある」「変数名にある」「定数で定義されている」は verification ではない

### 罠 3 — escape 多段を脳内計算する

shell → JSON → 言語 string → 外部 storage の多段 escape を頭の中で組み立てない。regex / code 片 / SQL / config を API 経由で保存する経路は **すべて** 該当する。

実装パターン:

- 書込後に必ず read-back し、stored 文字列と入力文字列の **完全一致** を assert
- backslash / quote / 改行を含む文字列は、escape 段数ごとに 1 文字ずつ verify
- 「動いたっぽい」「目視で OK そう」では完了としない

### 罠 4 — pattern を広げる fix の cohort 副作用を測らない

regex / filter / pattern / 集計範囲を拡張する fix は、対象 cohort が本来意図より広がる。「網羅性」を増やす方向の修正は副作用測定が default の責務。

実装パターン:

- 広げる前後の対象 cohort 数 (= 件数 / id 集合) を取り、想定外の cohort が増えていないか assert
- 「test が pass する = OK」とせず、対象範囲拡張が semantic と一致しているか別 cohort sample で確認
- UI label / ドキュメント記述 / 既存集計と pattern semantics が乖離していないか確認

## AI の癖 — これらは default で起きる

AI コーディングエージェントは放っておくと以下をやる。本プラグインの hook と TDD ループはこれらを default で抑えるためにある。

1. **実装を先に書く** — テストは後付け。→ hook A が「対応 test なき実装ファイル編集」を blocking
2. **ハルシネーション** — 存在しない API / フィールドを使う。→ 書く前に対象コードを `Read` で確認
3. **スコープ拡大** — 依頼にない「ついでの改善」を加える。→ 1 PR = 1 責務
4. **症状を隠す** — fallback / try-except / retry でバグを覆う。→ Fail-fast / 根本修正
5. **既存パターン無視** — 新パターンを持ち込みたがる。→ 既存コードを先に読む
6. **抽象用語に逃げる** — 「構造」「パターン」「集約」「再設計」「反転」「Bottom-up」のような語で実体不在の発言をする。→ **抽象用語を使ったら同時に具体物 (ファイル + 行番号 + 引用) を 1 つ以上添える。添えられないなら「読んでいないので発言できない」と返す**
7. **「ない / 不可能 / 該当なし」を grep の不一致で断定する** — app code を grep して hit しない → 「機能不在」と結論する / 外部 API の error code を即座に「権限不足」「不可能」と一般化する。app code に無い ≠ 不可能 (= 設定 / 資格情報 / 外部リソース経由で可能なケースが残る)。→ **不在主張の前に、対象リソース自身への diagnostic を最低 1 回叩いてから断定する**。外部の事実 (3rd-party の挙動 / API 仕様 / 「X は可能か」) なら、その diagnostic は **`/deep-research`** (web を多角検索し相互照合する read-only の breadth 腕、ADR 0005) — オラクルを AI の外に置く同じ原理
8. **ルール / memory / fix を射程外まで過剰一般化する** — 一度立てた禁則を、本来除外すべき context まで適用してしまう (= 「X は NG」を文字通り全 X に適用、本来 OK だった subset まで潰す)。→ **ルールを記述するときは「射程: ~ のみ。~ は除外」を必ず添える。ルールを適用するときは射程条件を 1 文で読み返す**
9. **共有環境を独占資源として扱う** — 同一 working tree で並走する別 Claude / 別ターミナル / IDE の WIP を `git add -A` / `git commit -a` / `git stash` で巻き込んで commit する。`git reset --hard` / `git push --force` / `git restore .` / `git clean -fd` / `git branch -D` で他人の commit / untracked を消す。→ **commit は個別 path 指定で add する / destructive git op は user 明示承認なしに実行しない / 並走するなら `git worktree add` で物理隔離する**

## TDD は default 挙動

Red → Green → Refactor を作業の軸とする。**この 3 フェーズは main session が直接行う** (= subagent に委譲しない。理由は次節)。

- **Red**: 振る舞いを failing test として書く。pass してしまうテストは「まだその時期ではない」
- **Green**: failing test を通す最小実装だけ書く。要求されていない機能を加えない
- **Refactor**: テストが pass している状態で構造を改善する。テストは変更しない

hook A (`hooks/hooks.json`) が「対応 test 不在の実装ファイル編集」を default で blocking する。slash command で起動する形式は採用しない (= 規律ではなく option になるため)。commit 時には test (`block-commit-if-tests-fail.sh`) を hook が回す。lint (`block-commit-if-lint-fails.sh`) は `.bootstrap-lint` を置いた project だけ opt-in で回す。**綺麗さは linter が見る deterministic な層 (命名規約 / format / 複雑度) だけ gate する** — 命名の質・設計のセンスは taste なので gate にせず人間レビュー / `code-review` skill に委ねる (= metric で縛ると不自然な分割を誘発し逆効果)。

書くテストの順序:

1. 正常系の最小ケース
2. 境界条件 (空 / null / 最小 / 最大 / 上限)
3. 失敗パス (不正入力でどう fail するか)
4. **Verification observation** — production-affecting なら read-back / live assert を含むテスト

## subagent と並列開発 — 方式は選べる、統合の入口は必ず関所を通る

**PreToolUse hook は subagent の tool 呼び出しにも発火する** (upstream `#21460` は 2026-05-29 に修正済み。2026-06-11 に実測検証: subagent の新規 source Write を TDD hook が exit 2 で blocking)。かつては発火せず「subagent は read-only 専用」だった (ADR 0001) — この回避は **ADR 0004 で撤回**。外部前提 (upstream issue) は閉じたら再検証する。

帰結として、**subagent / Workflow による mutation (Edit / Write / git commit) は禁止ではなく、隔離 worktree + 統合関所つきで公認する** (ADR 0004/0005)。強制は「誰が書いたか」ではなく統合の入口 (merge / PR) に掛かるので、方式 (= 誰が mutate するか) を縛る必要がない。ただし main session が抱える task の TDD core loop (Red→Green→Refactor) は引き続き直接回す (= 自分の作業を subagent に丸投げしない。上記「TDD は default 挙動」)。

並列実装の形態は 3 つあり、**どれを選んでもよい** — 強制は方式ではなく統合の入口 (merge / PR) に掛かる:

| 形態 | 起動 | edit 時 gate | 統合関所 |
|---|---|---|---|
| ① 別ターミナル worker | `sprint-plan` の起動文を人間が貼る | 効く | `block-unreviewed-merge.sh` (board task branch) |
| ② branch 並走 + GitHub PR | 人間 / 各 session | 効く | **CI** `bootstrap-review-gate.yml` (手元 hook は PR merge に届かない) |
| ③ Workflow / subagent 並列実装 | main session が起動 | **効く** (実測検証済み) | `block-unreviewed-merge.sh` (worktree lane branch — board 不要) |

規律:

- **mutation を伴う subagent / Workflow lane は必ず隔離 worktree で走らせる** (= lane の物理分離。同一 tree での並走は引き続き禁止)
- **統合 (merge / PR) には AI レビュー記録が必須**: `docs/sprint/reviews/<branch の / → _>.md` + `verdict: approve`。手元 merge は hook が、PR は CI が fail-closed で要求する。worktree の撤去は**必ず merge の後** (先に撤去すると関所の信号が消える — 手順違反)。撤去を忘れて lane が滞留しても無音にしない: SessionStart の doctor (`bootstrap-session-doctor.sh` + `lib/repo-drift.sh`) が **merge 済みなのに残っている worktree** を session 起動時に surface する (= 終端処理の漏れの可視化。強制でなく advisory)
- 単発の read-only 探索・要約・計画下書きは従来通り subagent の主用途 (gate すべき操作がなく、context を節約できる)
- 最終砦として、hook を経由しない経路も `scripts/arch-check.sh` + CI + git pre-commit (server 側 net) が捕まえる

### ultracode / Workflow を使うとき (ADR 0005)

ハーネスの `ultracode` (= `xhigh` effort + Workflow の subagent 自動 orchestration) は**新しい並列方式ではなく形態 ③ の一級コマンド化**。独立した方式として扱わず、bootstrap が governance する**実行エンジン**として使う (bootstrap = 永続/lifecycle/強制/横断 memory の層、ultracode = 揮発的な実行エンジン)。2 つの顔を別 governance にする:

| 顔 | 用途 | governance |
|---|---|---|
| **breadth (read-only ファンアウト)** | 探索 / 監査 / 移行発見 / レビュー多レンズ | **無制限・隔離不要・`wip_limit` 非対象・gate 摩擦ゼロ** (lane でないので review 帯域も消費しない)。plan/sprint-plan の探索 Step・integrate のレビュー Step に置く |
| **mutation lane (source を書く subagent)** | 形態 ③ | **隔離 worktree 必須**・edit/merge/commit gate を terminal worker と同一に通過。**並列度は engine 上限 `min(16, cores-2)` 律速で `wip_limit` 非対象** (guard 3 は内部 spawn を観測できない — ADR 0006)。帯域は統合関所 (guard 1) が自動で守る |

- **WIP・隔離の強制は spawn 時でなく edit/merge/commit 時**。hook は Workflow 内部の `agent()` spawn を観測できない (内部 subagent は main session の tool 呼び出しでないため PreToolUse に届かない) — 見えるのは各 subagent の Edit/Bash と最上位 Workflow 呼び出しだけ。だから「16 並列を spawn で止める」は不可能で、統合の入口で縛る (ADR 0004 の関所を WIP と検証に一般化)。
- **agent 判定のレビューは実検証を代替しない**。`block-unreviewed-merge.sh` は `verdict: approve` を確認後、検出したテストスイートを関所自身が回し fail なら block する (自由文の証拠行を信じない)。`.bootstrap-wip` は guard 3 (`block-over-wip-parallel.sh`) が `git worktree add` で実強制 (従来は表示のみ)。
- mutation を伴う Workflow lane は `isolation:'worktree'` で走らせ、worktree は merge の**後**に撤去する (先に撤去すると関所信号が消える)。breadth ファンアウトは worktree 不要。隔離せず active lane 中に main tree で source を mutate すると `block-uniso-main-edit.sh` (guard 2) が block する (統合操作中の conflict 解決は通す)。

#### 各レーンで「自動で効く規律」と「条件つきの規律」を混同しない

ultracode を全開 (`/effort ultracode`) にすると各タスクが最大 `min(16, cores-2)` 並列のレーンにファンアウトする。だが「**各レーンが自動で規律を保つ**」は誤読 — 自動なのは 1 つだけ:

- **自動で各レーンに届く = TDD のみ**。`require-test-companion` は subagent の Edit/Write にも発火する (ADR 0004 実測) ので、test なき実装は各レーンで構造的に不可能。
- **"自動"でなく「良いワークフロー + 統合関所」依存 = 隔離・依存順・レビュー**:
    - **worktree 隔離**は spawn 時に強制できない (Claude が書くワークフローが `isolation:'worktree'` を使うか次第。使わず shared tree に書けば衝突しうる)
    - **依存順**は ultracode が sprint-plan を経由せず自前でワークフローを書くので、共有 spine を先に直列化するかはスクリプトの良し悪し次第 (自動保証なし)
    - **レビュー・検証**は spawn では効かず、merge の関所 (guard 1) が唯一の網
- 帰結: **spawn 時点で hook は内部を観測できない (ADR 0005) ため、16 並列の安全は統合の入口 (guard 1/2/3) が全面的に担う** — だからその関所の健全性が前提 (例: 複合 `git merge` の素通しは事故源)。よって **保証つきの規律が要るなら `sprint-plan`→`integrate`** (隔離・spine・関所を構造で保証)、**最速で雑が許せるなら生 ultracode** (Claude がその場で構造を書き、関所が網)。どちらでも TDD は各レーンに届く。

## バグは根本を修正する

1. **Red**: バグを再現する failing test を書く (= 回帰テスト)
2. **Green**: 原因の層 / 責務を特定し、根本を修正する
3. **Refactor**: 同類のバグが入りにくい構造に整える

症状対応の兆候 (検出したら止まる):

- 壊れた状態を隠すための sort / filter / retry / fallback の追加
- エラーを握り潰す catch
- 共通コードを触らないための処理の複製

**同類のバグが 2 回以上出たら構造の症状**を疑う。局所修正をやめて、port から destructive 経路を物理削除する / 判定境界を純関数に集約する / 不変条件を型として表現する、などの構造変更を検討する。

> Anthropic 公式:
> "If you've corrected Claude more than twice on the same issue, the context is cluttered with failed approaches. A clean session with a better prompt almost always outperforms a long session with accumulated corrections."

## 並列 Claude 安全運用

複数ターミナルで Claude Code を並走させる構成は AI 駆動開発で常用される。共有 working tree は **事故源** で、`git add -A` / destructive git op 経由で他 session の作業を消す事故が default で起きる。

### 構成の選択肢

| 構成 | 安全性 | 適用場面 |
|---|---|---|
| 同一 working tree を複数 Claude で共有 | 低 | 同じ tree で短時間並走 (= 同じ feature を別観点で進める) |
| `git worktree add ../wt-<topic>` で物理隔離 | 高 | 別 feature / 別 branch を独立 fs で進める (Anthropic 公式推奨パターン) |

並走を継続的にやるなら **worktree 分離が default**。同一 tree で並走するときは下記規律を hook で deterministic に強制する。

### 規律 (hook で強制)

本プラグインの hook 群が default で blocking する:

- **`git add -A` / `git add .` / `git add -u` / `git commit -a` / `git stash` (path 指定なし)** を blocking (= `hooks/block-add-all.sh`)。**自分が編集した file を個別 path 指定で add する**
- **`git reset --hard` / `git push -f` (※ `--force-with-lease` は除外) / `git checkout -- .` / `git restore .` / `git clean -fd` / `git branch -D`** を blocking (= `hooks/block-dangerous-git-ops.sh`)
- **`git commit` 直前に当 session で編集していない file が staged にあれば** blocking (= `hooks/block-cross-claude-wip.sh`)。session transcript と `git diff --cached --name-only` を照合する。**`--amend` も対象** (= 共有 index 構成では amend こそが他 session の staged を最も巻き込む経路。実事故あり)
- **`.bootstrap-protected` で宣言した branch への直接 push** を blocking (= `hooks/block-push-to-protected.sh`)。feature branch + 統合 (integrate skill) 経由に矯正し、混入 commit が共有 branch に lock-in する事故を塞ぐ。**opt-in** — `.bootstrap-protected` が無ければ発火しない (= solo / 個人 repo は妨げない)
- **自分の worktree の lane (`.bootstrap-lane`) 範囲外の file 編集** を blocking (= `hooks/block-out-of-lane-edit.sh`)。sprint 時のみ発火 (lane file 不在なら素通し)

### 規律 (手順として)

hook で完全には強制しきれない部分は AI default 経路に組み込む:

1. **commit 前に必ず `git status --porcelain` で staged / unstaged / untracked を確認**。自分が触っていない file が居る場合は別 session の WIP / 別の origin を確認するまで stage しない
2. **branch を分けるなら `git worktree add`**。`git checkout <branch>` で同一 tree を切り替えると uncommitted を引きずる
3. **`npm install` / `pip install` 等の lock file 書き換え操作後**は `git diff <lockfile>` を読んでから add (= 並走 session が並行で install した結果と衝突する可能性)
4. **destructive な必要性がある操作は、user に「~ を実行して良いか」と明示確認**してから /permissions で hook を一時 deny にする

### 並列開発フロー (sprint)

防御 (= ぶつからない) だけでなく、1 feature を複数 Claude で **分業して組み戻す** generative なフロー。scrum の本質は「並列の最大化」でなく **WIP の制限**。

| scrum | 本プラグインでの実体 |
|---|---|
| sprint planning | `sprint-plan` skill が feature を **scope 非重複 task** に分解、board.json 生成 |
| 担当 / commitment | task = 1 worktree = 1 owner。`.bootstrap-lane` が触れる範囲を宣言 |
| WIP 制限 | `wip_limit` 個までしか **terminal worker** worktree を作らない (= 人間のレビュー帯域律速の路を構造的に絞る)。既定は `.bootstrap-wip` (repo root、整数 1 行、opt-in) > **worker 3-4**。Workflow/subagent lane は engine 上限律速で `wip_limit` 非対象 (ADR 0006) |
| 担当境界 | lane 外編集を `block-out-of-lane-edit.sh` が hard block |
| Definition of Done | TDD + verification 4 罠 + cohort audit (既存) |
| integration / review | `integrate` skill が **adversarial AI レビュー (read-only agent) → verdict 記録 → 依存順 merge → 統合 verify** → claim close。レビュー記録は `block-unreviewed-merge.sh` が merge の precondition として fail-closed 強制。人間は verdict + サンプル + 統合境界のみ読む (全 diff 目視はレビュー帯域が律速になり lane を増やしても throughput が増えない) |
| retrospective | `incident` skill → memory 昇格 (既存) |

**sprint 分解は default 挙動 (= 指示待ちにしない)**。単一タスクで `/plan` を default で回すのと同じく、並列が得な feature では `/sprint-plan` や「並列で」「スクラムで」を**言われるのを待たず**、探索 (`/plan` 相当の read-only) の直後に自動で sprint 分解 (`sprint-plan` skill をロード) を起動する。advisory な明示呼び出しは忘れられる (= プラグインの不採用方針)。判定はあくまで Claude が探索結果から下す。

**自動分解の発火条件 (= 全部満たすときだけ)**:
1. 作業が **feature** (= 新規/拡張の実装)。bug fix / refactor / 単一 file / 自明な小変更は対象外 → 逐次 (`/plan` → TDD)
2. **scope 非重複の leaf が 2 個以上**に割れる (= 各 task の owned file glob が重ならない)
3. 同時 lane 数 ≤ `wip_limit` (= `.bootstrap-wip` が在ればその値、なければ **worker 3-4**)。これは terminal worker 路の cap。Workflow/subagent 路は engine 上限 (~`min(16, cores-2)`) で走り wip 非対象 (ADR 0006)。超えるなら lane を減らすか逐次

**1 つでも欠けたら自動分解しない**。共有 interface / 型 / 契約があるなら、それを `depends_on` の **直列 spine** に切り出して先に 1 レーンで済ませ、その後に下流 leaf を並列化する (= Amdahl: 直列部分が speedup の上限)。disjoint に割れない feature は無理に刻まず逐次でやる (= 協調コストが利得を食う)。並列の収益は凹型だが、変曲点は**実行形態で違う** (ADR 0006): terminal worker 路は人間のレビュー帯域律速で低め (worker 3-4)、main session が orchestrate する Workflow/subagent 路は帯域を統合関所が自動で守るので engine 上限 (~`min(16, cores-2)`) まで伸ばせる。「2-3 が全形態の天井」ではない — その誤読が「並列が少ない」体感の正体。

自動分解した結果は**人間に提示する** (board.json + 各 lane の worker 起動文)。lane の実行形態は worker ターミナル (人間が起動) でも Workflow / subagent (main session が起動、隔離 worktree 必須) でもよい — どちらでも edit 時 gate は効き、統合は同じ関所 (レビュー記録) を通る (ADR 0004)。task = 1 worktree = 1 owner は不変。

> **この判定は advisory ではなく fail-closed gate で強制する** (= `hooks/block-unplanned-feature-build.sh`, PreToolUse)。sprint 自体は hook で起動できない (worktree 起動は人間、disjoint 判定は Claude — ADR 0001 の既約な残余) が、**「判定を済ませた」という precondition は強制できる**。TDD hook が「良い test」を書かせられなくても test の存在は強制するのと同型。`docs/sprint/` を採用した project で、**新規 source file を作ろうとした瞬間** (= feature 面を作る行為そのものを信号にする。prompt の語彙ではない — 語彙は proxy で言い回しに穴が空く)、sprint 判定の記録 (`docs/sprint/.gate`) も進行中 sprint (`board.json`) も無ければ blocking する。bug fix / refactor / 既存 file 編集は新規 source 面でないので素通し。
>
> 逐次でよいと判断したら、その scope・今日の日付・理由を `docs/sprint/.gate` に 1 行記録して続行する: `printf '%s\n' "src/<area>/<feature>/**  $(date +%F)  sequential: <理由>" >> docs/sprint/.gate`。entry は記録から 3 日で失効し、glob は feature-scoped (exact path か wildcard 前に 2 階層以上の prefix) のみ有効 — `src/**` のような全域 glob は 1 行で gate を恒久 fail-open にした実事故があり無効。失効したら日付を更新して再記録する (= 再記録が「まだ同一 feature 面か」の再判定)。記録 scope 外の新規 source を作ると再び止まる (= 新しい disjoint 面 → 再判定)。
>
> `hooks/sprint-trigger-reminder.sh` (UserPromptSubmit) は早期ヒントとして残るが、強制本体は上記 gate。語彙 regex の取りこぼしはもう致命的ではない (= 行為信号が最終的に必ず捕まえる)。

- 分解 = `skills/sprint-plan/SKILL.md`
- 統合 = `skills/integrate/SKILL.md`
- 発火 gate (強制) = `hooks/block-unplanned-feature-build.sh` / 早期ヒント = `hooks/sprint-trigger-reminder.sh`

## 依存方向を強制する (architecture)

大規模化するほど、アーキテクチャの境界 (= layer / 依存方向) が壊れると壊滅的になる。ただし **SOLID やクリーンアーキテクチャを散文で recite しても効かない** (= Claude は既に知っており、毎 session 唱えても挙動は変わらない advisory bloat)。効くのは 2 つを分けること:

| | 仕事 | 手段 |
|---|---|---|
| **確立** (establish) | project 開始時に層を切る (一度きり) | 設計判断 / scaffolding |
| **維持** (preserve) | 境界の侵食を恒常的に防ぐ | **deterministic な gate (hook)** |

advisory (= CLAUDE.md に「core は infra を import するな」と書くだけ) は、疲れた人間 / 並列 Claude が `import { x } from '@/infrastructure/...'` を core に書いた瞬間に**何も止めない**。lint は通常 import 方向を見ない。これが維持の穴。

### 強制の仕組み

依存方向は **project-local** な `.bootstrap-arch` で宣言する (= layer の glob / alias / 許可する依存辺)。本プラグインの hook は汎用で、project 固有ルールは一切持たない (= lane hook が `.bootstrap-lane` を読むのと同思想)。**cross-layer は default-deny**、明示した `allow` 辺だけ通す。

```
layer app   = app/**, middleware.ts
layer infra = infrastructure/**
layer core  = core/**
alias @/ => ./
allow app   -> infra, core
allow infra -> core
# core に allow 行なし = core は他 layer を import 禁止 (純 domain)
```

2 層で強制する (TDD 強制の edit+commit と同型):

- **`block-cross-layer-import.sh`** (Edit|Write 時) — 禁止 import を**書いた瞬間** blocking。手戻りを防ぐ
- **`block-arch-violations.sh`** (commit 時) — 宣言 layer 配下の**全 file を権威検証**。どの commit も契約を満たすことを保証する網

`.bootstrap/arch` が無ければ fail-open (= 非アーキ project は影響なし)。雛形は `templates/.bootstrap/arch`。

> **opt-in マーカーの所在 (ADR 0015)**: arch / protected / lint / wip / actions / lane は repo root の **`.bootstrap/` フォルダ配下** (`.bootstrap/arch` 等) に集約する。直下の散らかりを避けつつ「存在=有効・各 hook は自分のマーカーだけ読む」思想は不変 (単一設定ファイル化は fail-mode SPOF になるので不採用)。解決は単一権威 `hooks/lib/resolve-marker.sh` が `.bootstrap/<name>` (新) > `.bootstrap-<name>` (旧) の順で行い後方互換を保つ。本 doc 中の `.bootstrap-xxx` 表記は `.bootstrap/xxx` と読み替え可。

### 規律

- **1 不可逆なアーキ判断 = 1 ADR** (`docs/decisions/`) + `.bootstrap-arch` の更新。契約変更は「意図的に」行う (= hook が止めたから黙って allow 辺を足す、は症状隠蔽)
- 内側の層の機能が要るのに依存方向が許さない → **port (interface) を内側に定義して依存を反転**する。allow 辺を足して済ませない
- 共有したい型/定数が cross-layer を誘発する → その型の置き場所 (= どの layer の責務か) を問い直す

## external memory として docs/ を整備

CLAUDE.md / SKILL.md / memory で代替できないものだけを `docs/` に置く。AI 駆動開発の context 経済 (= cold restore / 再発防止 / 不可逆判断の永続化) はここで支える。

### 採用する 3 ディレクトリ

| dir | 用途 | 賞味期限 |
|---|---|---|
| `docs/handoffs/` | 並走 Claude / 別ターミナル / 翌日の自分 が cold restore するための状態スナップショット | 1-2 週間 |
| `docs/decisions/` | ADR (= 不可逆判断の理由 Context / Decision / Consequences) | 永続 |
| `docs/incidents/` | AI / 人間が踏んだ事故と再発防止策。memory `feedback_*` の昇格元 | 永続 |

雛形は `templates/docs/` を参照。`current/` / `exploring/` / `reference/` / `ops/` / `archive/` は **採用しない** (= CLAUDE.md / コード / memory で代替できるか graveyard 化する)。

並列開発をするときだけ `docs/sprint/board.json` を使う (= sprint runtime state。上記 3 dir のような永続 memory ではなく、sprint 終了で archive/破棄する ephemeral な真実)。`sprint-plan` skill が生成・`integrate` skill が消費する。

### 真実の所在 — docs に書かないもの

| 種別 | 真実 |
|---|---|
| コードの動作 | コード本体 + `tests/` |
| 規律 / AI 協働ルール | `skills/<name>/SKILL.md` |
| プロジェクト固有指示 | `CLAUDE.md` |
| AI に再注入したい教訓 | `~/.claude/projects/<project>/memory/` |
| 設定値 / 環境変数 | `.env.example` / framework 設定 |
| DB schema | migration ファイル |

二重化は **権威の分散**を招く。同じ事実が docs と上記の正本に両方あると AI がどちらを信じるか判別できなくなる。

### 失敗兆候 — テンプレ化しても無効化する典型

1. **権威の分散**: 同じ進行 (= phase / step 番号) が複数 doc で別記法 → 最新だけ正本 / 旧記述に `SUPERSEDED` 明示
2. **handoff の重複化**: handoff → handoff → incident の 3 hop → 1 handoff = 1 hop で完結、関連 doc は references にだけ書く
3. **ADR 習慣未定着**: `decisions/` が空 or 1 件しかない = 判断していない signal → 1 不可逆判断 = 1 ADR を default 挙動化
4. **business 固有名混入**: 顧客名 / 識別子が本文に直接書かれる → `<customer-A>` `<account-X>` の placeholder で

### 関連 skill

- `skills/handoff/SKILL.md` — handoff doc を書く規律 (session 終了前 / `/clear` 前 / 並走連携前にロード)
- `skills/incident/SKILL.md` — incident doc + memory `reference_*` への昇格 (fix / revert / hotfix / user 叱責後にロード)

## 環境隔離

プロジェクトが import するライブラリは project-local に閉じる。グローバルにインストールしない。

| 言語 | ライブラリ依存 | CLI ツール |
|---|---|---|
| Python | `.venv` + `pyproject.toml` | `uv tool install` / `pipx` |
| Node | `package.json` + `node_modules` | `npm i -g` (CLI のみ) |
| Rust | `Cargo.toml` | `cargo install` |
| Go | `go.mod` | `go install` |
| Ruby | `Gemfile` + bundler | `gem install` (CLI のみ) |

隔離環境ディレクトリ (`.venv/`, `node_modules/`, `target/`, `vendor/` 等) は `.gitignore` で除外する。新規環境で宣言された手順 (`uv venv && uv pip install -r requirements.txt` 等) のみで再現できることを完了条件とする。

## 完遂責任 — bug fix と同 PR で cohort audit

user-facing bug を fix したら **同根 cohort を必ず audit する**。問い合わせ件数は氷山の一角で、報告が 2 件でも同根 silent dropout が桁違いに多いケースは珍しくない。

実装パターン:

- fix commit と同 PR に同根 cohort の SQL / grep / log scan 結果を含める
- 「同根 N 件、内 K 件は既に自然解消、L 件は手動救済必要」を PR description に貼る
- audit を欠くと「user が気付いた範囲だけ fix」が default になり、silent victim を放置する

> この規律は決定論 hook で強制できない (= 「cohort audit を済ませたか」は確率判断)。**opt-in の確率 gate pilot** (`templates/hooks/cohort-audit-pilot.json`、ADR 0008 #2) が `Stop` prompt hook として warn-only で nudge する — default の 19 hook には入れず、誤検知率を測ってから昇格を判断する (初の非決定論 gate ゆえ慎重に)。

## 迷ったとき

1. タスクを 1 文で述べられるか
2. 責務は 1 つに絞れるか
3. failing test を書けるか
4. 結果を **verification (read-back / assert)** で確認できるか (= 4 罠を踏んでいないか)
5. これは根本修正か (= 症状対応の兆候はないか)
6. 既存パターンに合わせているか
7. user-facing bug なら **同根 cohort audit** を PR に含めているか
8. 並走 session の作業を **巻き込んで** いないか (= `git status --porcelain` で確認)
9. session を切る / `/clear` する / 並走する なら **handoff doc** を書き残したか (= `skills/handoff/`)
10. 自分のミス / 事故が起きたら **incident doc + memory 転記** したか (= `skills/incident/`)
11. 不可逆な判断をしたら **ADR** を書いたか (= `docs/decisions/`)

---
name: project-bootstrap
description: 上位1％の AI 駆動開発を個人の規律でなく構造として default 化する規律。純粋な強制は到達不能なので強制を4つの設計判断に作り替える = ① 分解 (precondition を fail-closed で強制・判断は逃さない) / ② 信号選び (行為を信号に・fail-mode を選ぶ) / ③ 配備の可視化 (効いていない強制を無音にしない) / ④ 計測つきの取引 (緩めるなら戻る根拠を metric で持つ)。Anthropic 公式 best practice (verification 最高レバレッジ / hooks deterministic / CLAUDE.md advisory) に整合する。verification 4 罠 / AI の癖 9 個 / TDD ループ / 根本修正 / 並列 Claude 安全運用 / subagent の mutation は隔離 worktree + 統合関所つきで可 (hook は subagent にも効く: 2026-06-11 実測検証、ADR 0004) / 環境隔離 / external memory として docs/ 整備 (handoffs / decisions / incidents)。新機能・バグ修正・リファクタ・調査など、あらゆるコーディング作業で常にロードする。
---

# AI 駆動開発の規律

## 強制の技芸 — 上位1％を構造で default 化する

本プラグインは、AI の速度を壊さずに引き出しきる **上位1％の AI 駆動開発** を、個人の規律 (= 忘れられる) でなく **構造として default 化する**。**規律 = AI が常にそう振る舞うこと** — 明示コマンドで初めて発動する形式 (slash command / 明示 subagent 呼び出し) は advisory にすぎず忘れられる。だから hook で deterministic に強制し、違反を blocking する (Anthropic 公式 https://code.claude.com/docs/en/best-practices: "Hooks are deterministic ... Unlike CLAUDE.md instructions which are advisory.")。

ただし**純粋な強制はほとんどの実規律で到達不能** (判断・配備・throughput は hook で縛りきれない)。諦めず、強制を以下 4 つの設計判断に作り替える。

### ① 分解 — precondition は強制し、判断は逃さない

規律を [強制可能な precondition] と [既約な判断] に割る。判断 (良い test を書く / 並列が得か) は強制できないが、**「判断を済ませた」という precondition は強制できる** (TDD hook が test の質でなく存在を強制するのと同型。sprint 発火 gate `hooks/block-unplanned-feature-build.sh` も「sprint 判定の記録」を新規 source 面作成の precondition にする)。判断を advisory に逃さない。

強制の射程は**外部前提に依存し、変わる**。かつて PreToolUse hook は subagent で発火せず (ADR 0001 / upstream `#21460`)、射程外で mutate しない設計に回避していた。upstream 修正 (2026-05-29 close) を**実測で検証**し (2026-06-11)、現在は subagent にも hook が届く — 回避は撤回、関所は「どの方式でも必ず通る統合の入口」へ (ADR 0004)。**外部前提は閉じたら再検証する**。

### ② 信号選び — 行為を信号にし、fail-mode を選ぶ

gate は **proxy でなく行為そのもの** を信号にする (sprint gate は prompt の語彙でなく「新規 source file を作る行為」を信号に — 語彙は穴が空く proxy)。fail-mode は意図的に選ぶ: **解析不能 = fail-closed** / **根拠不在 = fail-open** (非対象 project を妨げない)。ephemeral state は「存在」でなく **「活性」** で読み (= board.json の有無でなく未完了 task の有無。実事故: `docs/bootstrap/incidents/2026-06-07-stale-board-gate-bypass`)、終端処理 (archive) を所有 skill の責務にする。

### ③ 配備の可視化 — 効いていない強制を無音にしない

**hook は消費先 repo で現行版が実際に走って初めて効く**。正しい gate も未配備 / 部分 vendoring では無音で効果ゼロ (実事故: `docs/bootstrap/incidents/2026-06-02-coverage-drift-silent`。sprint 発火 gate は build 前の判断ゆえ CI 後追い不能)。だから強制は**配備カバレッジを可視化する meta 層**を持つ: SessionStart hook (`hooks/bootstrap-session-doctor.sh`) が採用状態を audit し、未採用なら導入を一度だけ尋ね / 配備漏れ (partial) なら警告 (採用は consent ゆえ強制不能)。team-wide net は `templates/ci/bootstrap-doctor.yml`、判定エンジンは `scripts/doctor.sh` (ADR 0003)。同じ原理を **repo drift** にも適用 (`hooks/lib/repo-drift.sh`): `HEAD` の `origin/main` 遅れ (stale checkout) と **merge 済みなのに残っている worktree** (lane 撤去漏れ) を session 起動時に surface する (どれが正しいかは既約な判断 — 強制せず事実だけ出す)。

### ④ 計測つきの取引 — 緩めるなら戻る根拠を持つ

強制を **throughput と引き換えに意図的に緩める** 層がある。人間の全 diff 直列レビューは帯域律速なので、一次レビューを read-only AI に移し人間は verdict + サンプルだけ読む (trust ladder Stage 2、`hooks/block-unreviewed-merge.sh`)。これは advisory への退行でなく、**客観 metric (`scripts/velocity.sh` の defect rate) で「いつ1段戻すか」を持つ管理された取引**。計測なき緩和は盲信。ただし**採点者が 1 人 (単一 orchestrator) の間は限界を正直に名指しする**: 測る人と律速が同一人物なので **self-report に近い**。2 人目の独立採点者が出るまで「速くした」を過信しない (`velocity.sh` 冒頭にも明記。限界を無音にしない = ③ の自己適用)。

## 最高レバレッジ — verification を必ず与える

Production-affecting な変更 (= 外部 API write / DB write / repo push / 設定書込 / 公開サイトへの影響) を含む実装は、return / commit の前に **実体を read-back で検証** してから完了とする。これを欠くと「return value が success だが live は反映されていない」事故が起きる (Anthropic 公式: "Give Claude a way to verify its work. This is the single highest-leverage thing you can do. If you can't verify it, don't ship it.")。

**何を動作テストすべきかの設計は `verification` skill が権威 (ADR 0007)** — テストは実装からでなく**意図と跨いだ境界**から導く / 各行に**外部オラクル** / 人間しか採点できない行は `HUMAN` / 各 PASS の前に kill-question。成果物 `docs/bootstrap/verification/<branch>.md` は lane merge の precondition (`block-merge-if-verification-unclosed.sh`)。継ぎ目の型 (async / 契約 / 緑の嘘 / オラクル捕獲 等) の詳細は `skills/verification/SKILL.md` を参照。

verification を「素朴な return チェック」で済ますと AI は以下 4 罠に default で落ちる:

### 罠 1 — silent failure を「正常」と読む

`200 OK` / 空配列 / `null` / 0 件返却を success とみなさない。多くの ORM/SDK は missing field / drop 済 column / 不在 resource を **throw せず空返却する**。→ `count == expected` を必ず assert (「0 件 = エラーなし」ではない) / HTTP `200` だけでなく content-type / body 構造まで assert / 「`success: true`」で完了とせず書き込んだ key/id で実 read-back。**async / scheduled の無音 skip は「自分の返答を読み返す」では捕まらない** (読み返す返答が存在しない) — AI の外の本番計器をオラクルにする (権威 = verification skill の async seam / `kind=monitor`)。

### 罠 2 — 既存リソースの actual capability を表記で推測する

資格情報 / token / API key / feature flag / 環境変数 / 設定値の「現在の能力」を、コメント / 変数名 / 定数で代用しない (実 capability と「過去に設定された意図」は乖離する)。→ 新 code 追加判断 (新資格情報 / 新 endpoint / 新 consent flow) の前に、token の actual scope・DB の actual schema・API の actual rate limit 等の actual state を、対象リソース自身への 1 query で確定させる。

### 罠 3 — escape 多段を脳内計算する

shell → JSON → 言語 string → 外部 storage の多段 escape を頭の中で組み立てない。regex / code 片 / SQL / config を API 経由で保存する経路は**すべて**該当。→ 書込後に必ず read-back し stored 文字列と入力文字列の**完全一致**を assert / backslash・quote・改行を含む文字列は escape 段数ごとに 1 文字ずつ verify。「目視で OK そう」では完了としない。

### 罠 4 — pattern を広げる fix の cohort 副作用を測らない

regex / filter / pattern / 集計範囲を拡張する fix は対象 cohort が意図より広がる。「網羅性」を増やす修正は副作用測定が default の責務。→ 広げる前後の対象 cohort 数 (件数 / id 集合) を取り想定外の増加が無いか assert / 「test が pass = OK」とせず拡張が semantic と一致するか別 cohort sample で確認 / UI label・ドキュメント・既存集計との semantics 乖離も確認。

## AI の癖 — これらは default で起きる

放っておくと以下が起きる — hook と TDD ループが default で抑える。

1. **実装を先に書く** — テストは後付け。→ hook A が blocking (下記 TDD 節)
2. **ハルシネーション** — 存在しない API / フィールドを使う。→ 書く前に対象コードを `Read` で確認
3. **スコープ拡大** — 依頼にない「ついでの改善」を加える。→ 1 PR = 1 責務
4. **症状を隠す** — fallback / try-except / retry でバグを覆う。→ Fail-fast / 根本修正
5. **既存パターン無視** — 新パターンを持ち込みたがる。→ 既存コードを先に読む
6. **抽象用語に逃げる** — 「構造」「パターン」「集約」等で実体不在の発言をする。→ **抽象用語には具体物 (ファイル + 行番号 + 引用) を 1 つ以上添える。添えられないなら「読んでいないので発言できない」と返す**
7. **「ない / 不可能」を grep の不一致で断定する** — app code に無い ≠ 不可能 (設定 / 資格情報 / 外部リソース経由の可能性が残る)。→ **不在主張の前に対象リソース自身への diagnostic を最低 1 回叩く**。外部の事実 (3rd-party の挙動 / API 仕様) なら diagnostic は **`/deep-research`** (read-only の breadth 腕、ADR 0005) — オラクルを AI の外に置く同じ原理
8. **ルール / memory / fix を射程外まで過剰一般化する** — 禁則を本来除外すべき context まで適用する。→ **ルール記述には「射程: ~ のみ。~ は除外」を必ず添え、適用時に射程条件を 1 文で読み返す**
9. **共有環境を独占資源として扱う** — 並走 session の WIP を `git add -A` / `git commit -a` / `git stash` で巻き込む、destructive git op で他人の commit / untracked を消す。→ **commit は個別 path 指定で add / destructive git op は user 明示承認なしに実行しない / 並走は `git worktree add` で物理隔離** (具体 op は下記 hook 一覧)

## TDD は default 挙動

Red → Green → Refactor を作業の軸とする。**この 3 フェーズは main session が直接行う** (= subagent に委譲しない。理由は次節)。**Red** = 振る舞いを failing test として書く (pass してしまうテストは「まだその時期ではない」) → **Green** = それを通す最小実装だけ書く (要求されていない機能を加えない) → **Refactor** = テストが pass している状態で構造を改善する (テストは変更しない)。

hook A (`hooks/hooks.json`) が「対応 test 不在の実装ファイル編集」を default で blocking する。slash command 起動形式は採用しない (規律でなく option になる)。commit 時には test (`block-commit-if-tests-fail.sh`) を hook が回す。lint (`block-commit-if-lint-fails.sh`) は `.bootstrap/lint` を置いた project だけ opt-in で回す。**綺麗さは linter が見る deterministic な層 (命名規約 / format / 複雑度) だけ gate し**、命名の質・設計のセンスは taste なので人間レビュー / `code-review` skill に委ねる。

書くテストの順序: 1. 正常系の最小ケース → 2. 境界条件 (空 / null / 最小 / 最大 / 上限) → 3. 失敗パス → 4. **Verification observation** (production-affecting なら read-back / live assert)

## subagent と並列開発 — 方式は選べる、統合の入口は必ず関所を通る

**PreToolUse hook は subagent の tool 呼び出しにも発火する** (①の実測検証 2026-06-11。ADR 0001 の read-only 回避は撤回済み)。帰結: **subagent / Workflow による mutation (Edit / Write / git commit) は禁止でなく、隔離 worktree + 統合関所つきで公認** (ADR 0004/0005)。強制は「誰が書いたか」でなく統合の入口 (merge / PR) に掛かるので方式を縛る必要がない。ただし main session が抱える task の TDD core loop は直接回す (丸投げしない)。

並列実装は 3 形態、どれを選んでもよい:

| 形態 | 起動 | edit 時 gate | 統合関所 |
|---|---|---|---|
| ① 別ターミナル worker | `sprint-plan` の起動文を人間が貼る | 効く | `block-unreviewed-merge.sh` (board task branch) |
| ② branch 並走 + GitHub PR | 人間 / 各 session | 効く | **CI** `bootstrap-review-gate.yml` (手元 hook は PR merge に届かない) |
| ③ Workflow / subagent 並列実装 | main session が起動 | **効く** (実測検証済み) | `block-unreviewed-merge.sh` (worktree lane branch — board 不要) |

規律:

- **統合 (merge / PR) には AI レビュー記録が必須**: `docs/bootstrap/sprint/reviews/<branch の / → _>.md` + `verdict: approve`。手元 merge は hook が、PR は CI が fail-closed で要求する
- 単発の read-only 探索・要約・計画下書きは従来通り subagent の主用途
- 最終砦として、hook を経由しない経路も `scripts/arch-check.sh` + CI + git pre-commit (server 側 net) が捕まえる

**「並列が得か」の判定・wip_limit・実行形態ごとの並列上限 (ADR 0006) は `skills/sprint-plan/SKILL.md` が権威**: `wip_limit` (`.bootstrap/wip`、既定 worker 3-4) は **terminal worker lane の cap** (人間のレビュー帯域律速)。Workflow/subagent lane は engine 上限 (~`min(16, cores-2)`) 律速で wip 非対象 — 帯域は統合関所が自動で守る。「2-3 が全形態の天井」は誤読。

### ultracode / Workflow を使うとき (ADR 0005)

ハーネスの `ultracode` (= `xhigh` effort + Workflow の subagent 自動 orchestration) は**新方式でなく形態 ③ の一級コマンド化**。bootstrap が governance する**実行エンジン**として使い、2 つの顔を別 governance にする:

| 顔 | 用途 | governance |
|---|---|---|
| **breadth (read-only ファンアウト)** | 探索 / 監査 / レビュー多レンズ | **無制限・隔離不要・`wip_limit` 非対象・gate 摩擦ゼロ** (lane でないので review 帯域も消費しない) |
| **mutation lane (source を書く subagent)** | 形態 ③ | **隔離 worktree 必須** (`isolation:'worktree'`)・edit/merge/commit gate は terminal worker と同一。並列度は engine 上限律速で `wip_limit` 非対象 (ADR 0006) |

- **WIP・隔離の強制は spawn 時でなく edit/merge/commit 時**。hook は Workflow 内部の `agent()` spawn を観測できないため spawn では止められず、統合の入口で縛る (ADR 0004 の関所を WIP と検証に一般化)。実強制: `.bootstrap/wip` は guard 3 (`block-over-wip-parallel.sh`) が `git worktree add` で / 未隔離の main tree source mutate は guard 2 (`block-uniso-main-edit.sh`) が block (統合操作中の conflict 解決は通す)
- **agent 判定のレビューは実検証を代替しない**: `block-unreviewed-merge.sh` (guard 1) は `verdict: approve` 確認後、検出したテストスイートを関所自身が回し fail なら block (自由文の証拠行を信じない)
- worktree の撤去は**必ず merge の後** (先に撤去すると関所の信号が消える)。撤去漏れは SessionStart doctor が surface する (③)
- **「自動で効く規律」と「条件つきの規律」を混同しない**: 自動で各レーンに届くのは **TDD のみ** (`require-test-companion` は subagent の Edit/Write にも発火)。worktree 隔離 (spawn 時に強制不能)・依存順 (spine を直列化するか次第)・レビュー/検証 (guard 1 が唯一の網) は「良いワークフロー + 統合関所」依存。帰結: **保証つきの規律が要るなら `sprint-plan`→`integrate`**、**最速で雑が許せるなら生 ultracode** (関所が網)。16 並列の安全は統合の入口 (guard 1/2/3) が全面的に担う — 関所の健全性が前提

## バグは根本を修正する

**Red** = バグを再現する failing test (= 回帰テスト) → **Green** = 原因の層 / 責務を特定し根本を修正 → **Refactor** = 同類のバグが入りにくい構造に整える。

症状対応の兆候 (検出したら止まる): 壊れた状態を隠す sort / filter / retry / fallback の追加 / エラーを握り潰す catch / 共通コードを触らないための処理の複製。

**同類のバグが 2 回以上出たら構造の症状**を疑う。局所修正をやめて、destructive 経路の物理削除 / 判定境界の純関数集約 / 不変条件の型表現などの構造変更を検討する。同じ issue で 2 回以上訂正されたら context は失敗案で汚れている — clean session + より良い prompt が長い session に勝つ (Anthropic 公式: "A clean session with a better prompt almost always outperforms a long session with accumulated corrections.")。

## 並列 Claude 安全運用

共有 working tree は**事故源**で、`git add -A` / destructive git op 経由で他 session の作業を消す事故が default で起きる。並走を継続的にやるなら **`git worktree add ../wt-<topic>` での物理隔離が default** (Anthropic 公式推奨。同一 tree 共有は短時間並走に限る)。

### 規律 (hook で強制)

- **`git add -A` / `git add .` / `git add -u` / `git commit -a` / `git stash` (path 指定なし)** を blocking (`hooks/block-add-all.sh`)。編集した file を個別 path 指定で add する
- **`git reset --hard` / `git push -f` (※ `--force-with-lease` は除外) / `git checkout -- .` / `git restore .` / `git clean -fd` / `git branch -D`** を blocking (`hooks/block-dangerous-git-ops.sh`)
- **`git commit` 直前に当 session で編集していない file が staged にあれば** blocking (`hooks/block-cross-claude-wip.sh`)。session transcript と `git diff --cached --name-only` を照合。**`--amend` も対象** (amend は他 session の staged を最も巻き込む経路 — 実事故あり)
- **`.bootstrap/protected` で宣言した branch への直接 push** を blocking (`hooks/block-push-to-protected.sh`)。feature branch + integrate skill 経由に矯正 (**opt-in** = マーカー不在なら発火しない)
- **自分の worktree の lane (`.bootstrap/lane`) 範囲外の file 編集** を blocking (`hooks/block-out-of-lane-edit.sh`。lane file 不在なら素通し)

### 規律 (手順として)

1. **commit 前に必ず `git status --porcelain`** を確認し、自分が触っていない file は別 session の WIP か確認するまで stage しない
2. **branch を分けるなら `git worktree add`** (`git checkout <branch>` は uncommitted を引きずる)
3. **lock file 書き換え操作 (`npm install` 等) の後**は `git diff <lockfile>` を読んでから add
4. **destructive な操作が必要なら user に明示確認**してから /permissions で hook を一時 deny にする

### 並列開発フロー (sprint)

防御だけでなく、1 feature を複数 Claude で**分業して組み戻す** generative なフロー。scrum の本質は「並列の最大化」でなく **WIP の制限**。分解と WIP は `sprint-plan` skill、統合は `integrate` skill (adversarial AI レビュー → verdict 記録 → 依存順 merge → 統合 verify → claim close) が権威。不変条件: **task = 1 worktree = 1 owner** (`.bootstrap/lane` が範囲宣言) / DoD = TDD + verification 4 罠 + cohort audit / retrospective は `incident` skill → memory 昇格。

**sprint 分解は default 挙動 (= 指示待ちにしない)**。並列が得な feature では「並列で」と言われるのを待たず、探索の直後に自動で `sprint-plan` skill をロードする。**発火条件 (feature / disjoint leaf ≥ 2 / ≤ wip_limit) と逐次判定の記録手順は `skills/sprint-plan/SKILL.md` が権威**。disjoint に割れない feature は無理に刻まず逐次 (共有 interface は `depends_on` の直列 spine に切り出す — Amdahl: 直列部分が speedup の上限)。分解結果 (board.json + 各 lane の起動文) は人間に提示する。

> **この判定は advisory でなく fail-closed gate で強制する** (`hooks/block-unplanned-feature-build.sh`, PreToolUse): `docs/bootstrap/sprint/` 採用 project で**新規 source file を作ろうとした瞬間** (②の適用)、sprint 判定の記録 (`docs/bootstrap/sprint/.gate`) も進行中 sprint (`board.json`) も無ければ blocking (既存 file 編集 / bug fix は素通し)。逐次判定の記録手順・TTL・glob 有効条件は sprint-plan skill §大前提 が権威。`hooks/sprint-trigger-reminder.sh` (UserPromptSubmit) は早期ヒントで、強制本体はこの gate。統合 = `skills/integrate/SKILL.md`。

## 依存方向を強制する (architecture)

大規模化するほど layer / 依存方向の崩壊は壊滅的になる。ただし **SOLID を散文で recite しても効かない** (advisory bloat) — CLAUDE.md に「core は infra を import するな」と書いても、疲れた人間 / 並列 Claude が禁止 import を書いた瞬間に**何も止めない**し、lint は通常 import 方向を見ない。効くのは**確立** (project 開始時に層を切る = 一度きりの設計判断) と**維持** (境界侵食を恒常的に防ぐ = **deterministic な gate**) を分けること。

### 強制の仕組み

依存方向は project-local な `.bootstrap/arch` で宣言する (layer glob / alias / 許可依存辺)。hook は汎用で project 固有ルールを持たない。**cross-layer は default-deny**、明示した `allow` 辺だけ通す。

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

- **`block-cross-layer-import.sh`** (Edit|Write 時) — 禁止 import を**書いた瞬間** blocking
- **`block-arch-violations.sh`** (commit 時) — 宣言 layer 配下の**全 file を権威検証**

`.bootstrap/arch` が無ければ fail-open (非アーキ project は影響なし)。雛形は `templates/.bootstrap/arch`。

> **opt-in マーカーの所在 (ADR 0015)**: arch / protected / lint / wip / actions / lane は repo root の **`.bootstrap/` フォルダ配下**に集約 (「存在=有効・各 hook は自分のマーカーだけ読む」思想は不変。単一設定ファイル化は fail-mode SPOF ゆえ不採用)。解決は単一権威 `hooks/lib/resolve-marker.sh` が `.bootstrap/<name>` (新) > `.bootstrap-<name>` (旧 flat、repo root 直下) の順で行い後方互換を保つ。

### 規律

- **1 不可逆なアーキ判断 = 1 ADR** (`docs/decisions/`) + `.bootstrap/arch` の更新。契約変更は「意図的に」行う (hook が止めたから黙って allow 辺を足す、は症状隠蔽)
- 内側の層の機能が要るのに依存方向が許さない → **port (interface) を内側に定義して依存を反転**。allow 辺を足して済ませない
- 共有したい型/定数が cross-layer を誘発する → その型の置き場所 (どの layer の責務か) を問い直す

## external memory として docs/ を整備

CLAUDE.md / SKILL.md / memory で代替できないものだけを `docs/` に置く (cold restore / 再発防止 / 不可逆判断の永続化)。二重化は**権威の分散**を招く (同じ事実が docs と正本に両方あると、どちらが真実か判別できない)。

| dir | 用途 | 賞味期限 |
|---|---|---|
| `docs/bootstrap/handoffs/` | 並走 Claude / 翌日の自分が cold restore する状態スナップショット | 1-2 週間 |
| `docs/decisions/` | ADR (不可逆判断の Context / Decision / Consequences) | 永続 |
| `docs/bootstrap/incidents/` | 事故と再発防止策。memory `feedback_*` の昇格元 | 永続 |

雛形は `templates/docs/`。`current/` / `exploring/` / `reference/` / `ops/` / `archive/` は**採用しない** (CLAUDE.md / コード / memory で代替できるか graveyard 化する)。並列開発時のみ `docs/bootstrap/sprint/board.json` を使う (sprint runtime state = sprint 終了で archive する ephemeral な真実。`sprint-plan` が生成・`integrate` が消費)。handoff を書く規律 = `skills/handoff/SKILL.md`、incident + memory 昇格 = `skills/incident/SKILL.md`。

### 真実の所在 — docs に書かないもの

コードの動作 = コード本体 + `tests/` / 規律・AI 協働ルール = `skills/<name>/SKILL.md` / プロジェクト固有指示 = `CLAUDE.md` / AI に再注入したい教訓 = `~/.claude/projects/<project>/memory/` / 設定値・環境変数 = `.env.example` / framework 設定 / DB schema = migration ファイル。

### 失敗兆候 — テンプレ化しても無効化する典型

1. **権威の分散**: 同じ進行が複数 doc で別記法 → 最新だけ正本 / 旧記述に `SUPERSEDED` 明示
2. **handoff の重複化**: handoff → handoff → incident の 3 hop → 1 handoff = 1 hop、関連 doc は references にだけ
3. **ADR 習慣未定着**: `decisions/` が空 or 1 件 = 判断していない signal → 1 不可逆判断 = 1 ADR を default 化
4. **business 固有名混入**: 顧客名 / 識別子は `<customer-A>` `<account-X>` の placeholder で

## 環境隔離

プロジェクトが import するライブラリは project-local に閉じ、グローバルにインストールしない: Python = `.venv` + `pyproject.toml` (CLI は `uv tool install` / `pipx`) / Node = `package.json` + `node_modules` (`npm i -g` は CLI のみ) / Rust = `Cargo.toml` / Go = `go.mod` / Ruby = `Gemfile` + bundler (`gem install` は CLI のみ)。隔離環境ディレクトリ (`.venv/`, `node_modules/`, `target/`, `vendor/` 等) は `.gitignore` で除外する。新規環境で宣言された手順のみで再現できることを完了条件とする。

## 完遂責任 — bug fix と同 PR で cohort audit

user-facing bug を fix したら**同根 cohort を必ず audit する**。問い合わせは氷山の一角 (報告 2 件でも同根 silent dropout は桁違いに多い)。fix commit と同 PR に同根 cohort の SQL / grep / log scan 結果と「同根 N 件、内 K 件は自然解消、L 件は手動救済必要」を含める。audit を欠くと「user が気付いた範囲だけ fix」が default になり silent victim を放置する。

> この規律は決定論 hook で強制できない (「audit を済ませたか」は確率判断)。**opt-in の確率 gate pilot** (`templates/hooks/cohort-audit-pilot.json`、ADR 0008 #2) が `Stop` prompt hook として warn-only で nudge する — default hook 群には入れず、誤検知率を測ってから昇格を判断する。

## 迷ったとき

1. タスクを 1 文で述べられるか
2. 責務は 1 つに絞れるか
3. failing test を書けるか
4. 結果を **verification (read-back / assert)** で確認できるか (4 罠を踏んでいないか)
5. これは根本修正か (症状対応の兆候はないか)
6. 既存パターンに合わせているか
7. user-facing bug なら **同根 cohort audit** を PR に含めているか
8. 並走 session の作業を**巻き込んで**いないか (`git status --porcelain`)
9. session を切る / `/clear` する / 並走するなら **handoff doc** を書いたか (`skills/handoff/`)
10. ミス / 事故が起きたら **incident doc + memory 転記**したか (`skills/incident/`)
11. 不可逆な判断をしたら **ADR** を書いたか (`docs/decisions/`)

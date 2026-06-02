---
name: project-bootstrap
description: AI 駆動開発の規律。ルール = AI の default 挙動 + hook 強制。Anthropic 公式 best practice (verification 最高レバレッジ / hooks deterministic / CLAUDE.md advisory) に整合する。verification 4 罠 / AI の癖 9 個 / TDD ループ / 根本修正 / 並列 Claude 安全運用 / subagent は read-only (mutation は main session、hook が subagent で効かないため) / 環境隔離 / external memory として docs/ 整備 (handoffs / decisions / incidents)。新機能・バグ修正・リファクタ・調査など、あらゆるコーディング作業で常にロードする。
---

# AI 駆動開発の規律

## ルールとは

**ルール = AI が常にそう振る舞うこと**。

ユーザーが明示的にコマンドを叩いて初めて発動する形式 (slash command / 明示 subagent 呼び出し) は advisory にすぎず、忘れられる。本プラグインのルールは hook で deterministic に強制される。違反は blocking される。

> Anthropic 公式 (https://code.claude.com/docs/en/best-practices):
> "Hooks are deterministic and guarantee the action happens. Unlike CLAUDE.md instructions which are advisory."

**ただし hook は消費先 repo で現行版が実際に走って初めて効く**。設計が正しい gate も、未配備 / 部分 vendoring の repo では無音で効果ゼロになる (実事故: `docs/incidents/2026-06-02-coverage-drift-silent`。とりわけ sprint 発火 gate は build 前の判断ゆえ CI 後追いができず PreToolUse hook 以外に backstop が無い)。そこで SessionStart hook (`hooks/bootstrap-session-doctor.sh`) が session 起動時に採用状態を audit し、**未採用なら導入を一度だけ尋ね / 採用済みで gate 配備漏れ (partial) なら警告**する (= 採用は consent ゆえ強制不能だが「状態を可視化する」ことはできる。enforcement の本体は per-action gate)。plugin 非依存の team-wide net は `templates/ci/bootstrap-doctor.yml`。判定エンジンは `scripts/doctor.sh` (ADR 0003)。

## 最高レバレッジ — verification を必ず与える

Production-affecting な変更 (= 外部 API write / DB write / repo push / 設定書込 / 公開サイトへの影響) を含む実装は、return / commit の前に **実体を read-back で検証** してから完了とする。これを欠くと「return value が success だが live は反映されていない」事故が起きる。

> Anthropic 公式:
> "Give Claude a way to verify its work. This is the single highest-leverage thing you can do. If you can't verify it, don't ship it."

verification を「素朴な return チェック」で済ますと AI は以下 4 罠に default で落ちる:

### 罠 1 — silent failure を「正常」と読む

`200 OK` / 空配列 / `null` / 0 件返却を success とみなさない。多くの ORM/SDK は missing field / drop 済 column / 存在しない resource を **throw せず空返却する** 設計になっている。

実装パターン:

- `count == expected` を必ず assert (= 「0 件返ってきた = エラーなし」ではない)
- HTTP `200` だけでなく content-type / body の構造まで assert
- 「`success: true` が返った」だけで完了としない、書き込んだ key/id で実 read-back

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
7. **「ない / 不可能 / 該当なし」を grep の不一致で断定する** — app code を grep して hit しない → 「機能不在」と結論する / 外部 API の error code を即座に「権限不足」「不可能」と一般化する。app code に無い ≠ 不可能 (= 設定 / 資格情報 / 外部リソース経由で可能なケースが残る)。→ **不在主張の前に、対象リソース自身への diagnostic を最低 1 回叩いてから断定する**
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

## subagent は read-only — 強制が効かない場所で mutate しない

**PreToolUse hook は subagent (= Task / Agent ツールで起動する子エージェント) の tool 呼び出しでは発火しない。** これは Claude Code の未修正の既知問題 (upstream `anthropics/claude-code#21460`「[SECURITY] PreToolUse hooks not enforced on subagent tool calls」OPEN) で、伝播オプションの追加も却下済 (`#27533` not planned)。plugin が配る subagent では frontmatter の `hooks:` も**無視される** (公式: "plugin subagents do not support the `hooks` ... field")。一次ソース検証は `docs/decisions/0001-subagent-hooks-not-enforced.md`。

帰結として本プラグインは「強制 = hook」を貫くため、**実体を書き換える作業 (Edit / Write / git commit) を subagent に委譲しない**:

- **subagent は read-only 探索専用**。`Read` / `Grep` / `Glob` での調査・要約・計画の下書きに使う (= context を節約しつつ gate すべき操作が存在しない)
- **mutation はすべて main session が行う** (= TDD の Red/Green/Refactor、bug fix、refactor)。ここでだけ hook が test 先行 / lane / 依存方向 / commit gate を deterministic に強制できる
- **並列開発は subagent ではなく別 session の worker** で行う。`sprint-plan` が吐く worker 起動文を**人間が別ターミナル / 別 worktree に貼って起動**する (= 各 worker はそれ自身が main session なので hook が普通に効く)。1 session 内で subagent を並列に走らせて実装させる方式は、gate が消えるため**採らない**
- 最終砦として、subagent や人間の直 commit など hook を経由しない経路も `scripts/arch-check.sh` + CI + git pre-commit (server 側 net) が捕まえる

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
| WIP 制限 | `wip_limit` (既定 2-3) 個までしか worktree を作らない (= 構造的に並列度を絞る) |
| 担当境界 | lane 外編集を `block-out-of-lane-edit.sh` が hard block |
| Definition of Done | TDD + verification 4 罠 + cohort audit (既存) |
| integration / review | `integrate` skill が依存順 merge + **統合 verify** + claim close |
| retrospective | `incident` skill → memory 昇格 (既存) |

**sprint 分解は default 挙動 (= 指示待ちにしない)**。単一タスクで `/plan` を default で回すのと同じく、並列が得な feature では `/sprint-plan` や「並列で」「スクラムで」を**言われるのを待たず**、探索 (`/plan` 相当の read-only) の直後に自動で sprint 分解 (`sprint-plan` skill をロード) を起動する。advisory な明示呼び出しは忘れられる (= プラグインの不採用方針)。判定はあくまで Claude が探索結果から下す。

**自動分解の発火条件 (= 全部満たすときだけ)**:
1. 作業が **feature** (= 新規/拡張の実装)。bug fix / refactor / 単一 file / 自明な小変更は対象外 → 逐次 (`/plan` → TDD)
2. **scope 非重複の leaf が 2 個以上**に割れる (= 各 task の owned file glob が重ならない)
3. 同時 lane 数 ≤ `wip_limit` (既定 2-3)。超えるなら lane を減らすか逐次

**1 つでも欠けたら自動分解しない**。共有 interface / 型 / 契約があるなら、それを `depends_on` の **直列 spine** に切り出して先に 1 レーンで済ませ、その後に下流 leaf を並列化する (= Amdahl: 直列部分が speedup の上限)。disjoint に割れない feature は無理に刻まず逐次でやる (= 協調コストが利得を食う)。並列の収益は凹型で変曲点は低い (ソロで実質 2-3)。

自動分解した結果は**人間に提示する** (board.json + 各 lane の worker 起動文)。worker Claude の起動は人間が行う (= task = 1 worktree = 1 owner、レビューは人間で直列。1 session 内での subagent 並列実行は別物で、ここでは採らない)。

> **この判定は advisory ではなく fail-closed gate で強制する** (= `hooks/block-unplanned-feature-build.sh`, PreToolUse)。sprint 自体は hook で起動できない (worktree 起動は人間、disjoint 判定は Claude — ADR 0001 の既約な残余) が、**「判定を済ませた」という precondition は強制できる**。TDD hook が「良い test」を書かせられなくても test の存在は強制するのと同型。`docs/sprint/` を採用した project で、**新規 source file を作ろうとした瞬間** (= feature 面を作る行為そのものを信号にする。prompt の語彙ではない — 語彙は proxy で言い回しに穴が空く)、sprint 判定の記録 (`docs/sprint/.gate`) も進行中 sprint (`board.json`) も無ければ blocking する。bug fix / refactor / 既存 file 編集は新規 source 面でないので素通し。
>
> 逐次でよいと判断したら、その scope と理由を `docs/sprint/.gate` に 1 行記録して続行する (1 列目 = この作業の scope glob): `printf '%s\n' "src/<area>/**  sequential: <理由>" >> docs/sprint/.gate`。記録 scope 外の新規 source を作ると再び止まる (= 新しい disjoint 面 → 再判定)。
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

`.bootstrap-arch` が無ければ fail-open (= 非アーキ project は影響なし)。雛形は `templates/.bootstrap-arch`。

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

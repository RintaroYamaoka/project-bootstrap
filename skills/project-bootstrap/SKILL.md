---
name: project-bootstrap
description: AI 駆動開発の規律。ルール = AI の default 挙動 + hook 強制。Anthropic 公式 best practice (verification 最高レバレッジ / hooks deterministic / CLAUDE.md advisory) に整合する。verification 4 罠 / AI の癖 9 個 / TDD ループ / 根本修正 / 並列 Claude 安全運用 / 環境隔離 / external memory として docs/ 整備 (handoffs / decisions / incidents)。新機能・バグ修正・リファクタ・調査など、あらゆるコーディング作業で常にロードする。
---

# AI 駆動開発の規律

## ルールとは

**ルール = AI が常にそう振る舞うこと**。

ユーザーが明示的にコマンドを叩いて初めて発動する形式 (slash command / 明示 subagent 呼び出し) は advisory にすぎず、忘れられる。本プラグインのルールは hook で deterministic に強制される。違反は blocking される。

> Anthropic 公式 (https://code.claude.com/docs/en/best-practices):
> "Hooks are deterministic and guarantee the action happens. Unlike CLAUDE.md instructions which are advisory."

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

Red → Green → Refactor を作業の軸とする。

- **Red**: 振る舞いを failing test として書く。pass してしまうテストは「まだその時期ではない」。`agents/test-writer.md` の subagent が担う
- **Green**: failing test を通す最小実装だけ書く。要求されていない機能を加えない。`agents/implementer.md` の subagent が担う
- **Refactor**: テストが pass している状態で構造を改善する。テストは変更しない。`agents/refactorer.md` の subagent が担う

hook A (`hooks/hooks.json`) が「対応 test 不在の実装ファイル編集」を default で blocking する。slash command で起動する形式は採用しない (= 規律ではなく option になるため)。

書くテストの順序:

1. 正常系の最小ケース
2. 境界条件 (空 / null / 最小 / 最大 / 上限)
3. 失敗パス (不正入力でどう fail するか)
4. **Verification observation** — production-affecting なら read-back / live assert を含むテスト

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
- **`git commit` 直前に当 session で編集していない file が staged にあれば** blocking (= `hooks/block-cross-claude-wip.sh`)。session transcript と `git diff --cached --name-only` を照合する

### 規律 (手順として)

hook で完全には強制しきれない部分は AI default 経路に組み込む:

1. **commit 前に必ず `git status --porcelain` で staged / unstaged / untracked を確認**。自分が触っていない file が居る場合は別 session の WIP / 別の origin を確認するまで stage しない
2. **branch を分けるなら `git worktree add`**。`git checkout <branch>` で同一 tree を切り替えると uncommitted を引きずる
3. **`npm install` / `pip install` 等の lock file 書き換え操作後**は `git diff <lockfile>` を読んでから add (= 並走 session が並行で install した結果と衝突する可能性)
4. **destructive な必要性がある操作は、user に「~ を実行して良いか」と明示確認**してから /permissions で hook を一時 deny にする

## external memory として docs/ を整備

CLAUDE.md / SKILL.md / memory で代替できないものだけを `docs/` に置く。AI 駆動開発の context 経済 (= cold restore / 再発防止 / 不可逆判断の永続化) はここで支える。

### 採用する 3 ディレクトリ

| dir | 用途 | 賞味期限 |
|---|---|---|
| `docs/handoffs/` | 並走 Claude / 別ターミナル / 翌日の自分 が cold restore するための状態スナップショット | 1-2 週間 |
| `docs/decisions/` | ADR (= 不可逆判断の理由 Context / Decision / Consequences) | 永続 |
| `docs/incidents/` | AI / 人間が踏んだ事故と再発防止策。memory `feedback_*` の昇格元 | 永続 |

雛形は `templates/docs/` を参照。`current/` / `exploring/` / `reference/` / `ops/` / `archive/` は **採用しない** (= CLAUDE.md / コード / memory で代替できるか graveyard 化する)。

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

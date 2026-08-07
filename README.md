# project-bootstrap

**上位1％の AI 駆動開発を、個人の規律でなく構造として default 化する** Claude Code プラグイン。AI の速度を壊さずに引き出しきるための「強制の技芸」を hook で deterministic に効かせる。**担当範囲は発注 (上流) から実装・統合を経て検収まで** — AI が実装・試験・修正を自律的に繰り返すループでは、渡す前に目的・作業範囲・変更禁止範囲・検証方法・完了条件・停止条件を確定させておく必要があり、その事前条件を作る工程と、返ってきた物を意図と突合する工程まで含めて 1 つの規律にしている (ADR 0022)。

純粋な強制はほとんどの実規律で到達不能 (判断・配備・throughput は hook で縛りきれない) なので、強制を4つの設計判断の連なりに作り替える: **① 分解** (強制可能な precondition と既約な判断に割り、precondition を fail-closed で課す) / **② 信号選び** (proxy でなく行為を信号に、fail-mode を意図的に選ぶ) / **③ 配備の可視化** (効いていない強制を無音にしない) / **④ 計測つきの取引** (throughput と引き換えに緩めるなら戻る根拠を metric で持つ)。明示コマンドで発動する advisory 形式は採用しない (= 忘れられるため)。Anthropic 公式 best practice ([code.claude.com/docs/en/best-practices](https://code.claude.com/docs/en/best-practices)) と整合: verification 最高レバレッジ / hooks deterministic / CLAUDE.md は prune して短く保つ。

## これをどう使うか — 開発者向け運用ガイド

**ひとことで言うと**: あなたは普段どおり Claude Code に頼むだけ。このプラグインは「上手い開発者なら自然にやる規律」(テスト先行・本番前の確認・並列作業の安全・事故の記録) を、AI が忘れても**自動で効くガードレール**にして背後で回す。あなたが覚えることはほとんど無い。下の表は「何が勝手に効くか」と「あなたが手で触れる所」の地図。

### あなたが打てるコマンド (slash)

必要なときに自分で打てる。ただし多くは AI が状況を見て**勝手に呼ぶ**ので、覚えなくても困らない。

| コマンド | 何をしてくれる | いつ自分で打つか |
|---|---|---|
| `/charter` | プロジェクトの**不可逆な判断だけ**を 1 ファイルに固める (目的 / 不変のコア / 制約 / 決定ログ / 未決台帳) | 立ち上げ時。方針が変わったとき |
| `/order` | AI に渡す作業を**引き渡し契約 (作業指示書)** として確定させ発注する。停止条件・エスカレーション条件まで書き切る | まとまった作業を AI に自律で任せる前 |
| `/pre-review` | 独立コンテキストの AI を**仮想下流リーダー**として使い、実装前に仕様を壊しにかからせる | 発注の直前 (`/order` が自動で呼ぶ) |
| `/accept` | 実装差分と完了条件を 1 行ずつ突合して**検収**し、実績 (エスカレーション・再試行・差し戻し・停止条件の突合・人間時間) を記録する | 統合の後 |
| `/plan <タスク>` | 実装の前に「何を・どこを・どうテストするか」の計画書を出して**止まる**。承認するまでコードを書かない | 大きめ/曖昧な作業の前。スコープを固めたいとき (※ 発注済み作業指示書がある場合は不要) |
| `/sprint-plan` | 1 つの機能を**重ならない複数レーン**に割り、並列で進める段取り (worktree + 起動文) を作る | 大きい機能を複数ターミナル/並列で一気に進めたいとき |
| `/integrate` | 並列レーンを依存順に統合し、AI レビュー + 全体テストを通してから合流させる | 並列作業を合流させるとき |
| `/verification` | 「コードの正しさ」でなく**継ぎ目** (他システム連携・要件・本番の実体・環境) の動作テストを設計し、人間が確認する行を切り出す | 抽象的な指示で作った直後・統合前 |
| `/handoff <topic>` | 今の状態を「次のセッション/別の人が冷えた状態から再開できる」スナップショットに残す | 中断前・`/clear` 前・別 Claude に渡す前 |
| `/incident <topic>` | 事故・やり直し・叱責を記録し、**次回 AI が同じ轍を踏まないよう memory に昇格**させる | 何かをやらかした/やり直した直後 |

### 勝手に動くもの (あなたは呼ばない)

「言わなくてもやる」のがこのプラグインの肝。advisory (気をつけてね) は忘れられるので採らない。

| 契機 | 自動で起きること |
|---|---|
| **セッション開始時** | 採用状態の点検 + 「checkout が古い」「使い終わった worktree が残ってる」「テスト要否が未判断の変更がある」を**画面に出す** (止めはしない、見せるだけ) |
| **機能っぽい依頼** | AI が「並列に割れるか」を判定し、割れるなら自分で `/sprint-plan` に入る |
| **抽象的な依頼で実装した後** | AI が `/verification` を呼んで「何を人間が確かめるべきか」の骨子を作る |
| **作業指示書を発注しようとしたとき** | AI が `/pre-review` を呼び、**別コンテキストで自分の書いた仕様を壊しにかかる**。出た指摘は「直す」か「未決として名前をつける」のどちらかにしないと発注できない |
| **やり直し/叱責の後** | AI が `/incident` を呼んで教訓を memory に残す |
| **本番デプロイ・データ修復・本番 DB migration を打つ瞬間** | 過去の教訓メモが**目の前に出る** (例: 「本番前に各指示文言と実装を逐語照合したか」「この欠落はバグか仕様か」) |

### あなたを止める hook (止まったら、の対処)

危ない操作は **AI もあなたも** 一旦止まる。理不尽に見えたら理由文を読めば、たいてい正しく止めている。

- **未完成の作業指示書を「発注済み」にして commit しようとした** → 空欄の節・完了条件と検証方法の数の不一致・未決着の事前レビュー指摘・OPEN な未決への依存を指摘して止める (下書きのままなら止めない)
- **発注された作業指示書が無いまま新しい実装ファイルを作ろうとした** → 先に `/order` で契約を作る (既存ファイルの修正・バグ修正は止めない)
- **テストの無い実装ファイルを触ろうとした** → 対応するテストを先に書く (TDD 強制)
- **テストや lint が落ちたまま commit** → 直してから commit
- **`git add -A` / `git commit -a` / `git reset --hard` / `git push -f`** など巻き込み・破壊系 → 個別 path 指定や `--force-with-lease` に矯正 (※このセッションでも実際にこの 2 つが私を止めて、安全な手順に直しました)
- **保護ブランチへの直 push / 古い checkout からの push / レビュー無しのレーン合流 / 動作テスト未クローズの合流** → PR 経路・最新化・レビュー記録・verification を要求

止める必要が本当に無いと確信できる場合だけ、`/permissions` で一時的に該当 hook を deny にできる。

### あなたが手で叩く CLI

`scripts/` に、AI を介さず直接回せるツールがある。

```bash
scripts/doctor.sh                 # この repo に bootstrap がちゃんと効いてるか点検 (CI でも使える)
scripts/velocity.sh [repo ...]    # 週次の commit数・defect率を複数repo横断で集計 (レビューを薄くした後の"壊れてない"判定)
scripts/wo-metrics.sh [repo ...]  # 作業指示書ごとの実績を集計。「AIが止まったとき穴は指示書の何節にあったか」を出す
scripts/arch-check.sh [file ...]  # 依存方向(レイヤ)違反を検査。Claude非依存なので pre-commit/CI で全員に効かせられる
scripts/retired-check.sh <base>   # 引退した名前が追加行に混入していないか検査 (PR は origin/main...HEAD を渡す)
scripts/setup-server-enforcement.sh --check   # GitHub側の保護設定を監査 (admin素通りの穴を検出)
scripts/setup-server-enforcement.sh           # 保護設定を適用 (下記「サーバ側」参照)
```

### opt-in 設定ファイル (使う分だけ repo root の `.bootstrap/` フォルダに置く)

**何も置かなければ何も強制されない**。欲しい規律のファイルだけ置く (雛形フォルダごと `cp -r templates/.bootstrap your-project/.bootstrap` でコピーし、要らないファイルを消す)。マーカーは repo root の **`.bootstrap/` フォルダ配下**に集約する (直下が散らからない)。

| ファイル | 置くと効くもの | 中身 |
|---|---|---|
| `.bootstrap/arch` | レイヤ依存方向の強制 | `layer app = app/**` / `allow app -> lib` |
| `.bootstrap/protected` | 宣言ブランチへの直 push 禁止 | `main` (1 行 1 パターン) |
| `.bootstrap/lint` | commit 前の lint gate | 空ファイル (在るだけで有効) |
| `.bootstrap/wip` | 並列 worker 数の上限 | 整数 1 行 (例 `4`) |
| `.bootstrap/actions` | 本番操作の瞬間に出すプロジェクト固有メモ | `prod-deploy \| <memo-slug> \| <一行メモ>` |
| `.bootstrap/retired` | 改名で引退した名前の混入を commit で blocking | `typeNo \| typeId \| <射程 glob> \| <note>` |
| `docs/bootstrap/sprint/` (ディレクトリ) | 並列開発フロー一式の有効化 | 採用マーカー |
| `docs/bootstrap/verification/` (ディレクトリ) | 動作テスト計画の merge gate | 採用マーカー |
| `docs/bootstrap/commission/` (ディレクトリ) | 上流工程 (発注 → 検収) 一式の有効化 | 採用マーカー。`templates/docs/bootstrap/commission/` を丸ごとコピー |

> **後方互換 (本 README で唯一の注記)**: マーカーの解決は単一権威 `hooks/lib/resolve-marker.sh` が担い、`.bootstrap/<name>` (新フォルダ) を優先し旧 flat path `.bootstrap-<name>` (repo root 直下) に fallback する。両方在れば新が勝つ。既存採用 repo は移行不要。本 README / skills 内の表記は新フォルダ形に統一してある。

### 知っておくと得する仕組み (見落としがちな機能)

- **上流の質を下流の実測で測る** (ADR 0024): 「この作業指示は良かったか」を勘で振り返らない。`/accept` が指示書ごとに**エスカレーション・再試行・差し戻し・トークン・停止条件が守られたか・人間時間**を記録し、`scripts/wo-metrics.sh` が「AI が止まったとき穴は指示書の何節にあったか」「人間時間がどの工程に溶けているか (= 次の自動化投資先)」を集計する。テンプレートのどこが薄いかがデータで分かる。**エスカレーション 0 は良い値とは限らない** (事前条件が過剰な可能性と区別がつかないので `[ズレ]` 件数と並べて読む)
- **レビューを薄くする trust ladder**: 全 diff を人間が目視するのが本当の律速。AI が一次レビューして `approve/reject` を記録 → 人間は**verdict とサンプルだけ**読む。安全網は `scripts/velocity.sh` の defect率 — 跳ねたらレビューを 1 段濃く戻す、という客観データで運用する。
- **本番操作メモの自動表示** (ADR 0010/0013/0014): 過去にハマった操作 (本番デプロイ・データ修復) を**打つ瞬間**に教訓が出る。「メモはあったのに事故った」を構造的に潰す。`prod-deploy` と `data-backfill` は arm 不要で普遍メモが出る。
- **複数 repo にまたがる契約の保護** (ADR 0011): フロントとバックなど別 repo の共有スキーマを `docs/bootstrap/verification/contracts` に登記しておくと、片側を変えたとき相手側のテストを通すまで合流できない (無音で割れる事故を防ぐ)。
- **verification の `HUMAN` 行**: AI が確かめられない「これがユーザーの欲しかった物か」は人間に手渡される。あなたが実機で確認して `PASS/FAIL` を記録するまで統合が閉じない。
- **AI の「ハードコード / テスト決め打ち」への備え** (ADR 0016): AI が生成コードで陥りがちな失敗は 2 種ある。① 能力限界の決め打ち (例に合わせた固定値・中身のない stub・secrets/env 埋め込み) と ② テストを通すためだけのごまかし (テスト入力を検知して期待値を返す・採点コードを書き換える)。②は「もっと厳しくレビュー」では消えない (AI が採点表を触れるのが原因) ので、`verification` skill は**判定に使うテストを実装者の手の届かない所に置く (held-out oracle)** ことと、**入力を少しずらすと決め打ちが壊れる metamorphic テスト**を緩和として教える。①の secrets/env は gitleaks 等を `.bootstrap/lint`+CI に足すのが定石 (独自スキャナは作らない)。
- **サーバ側の恒久ガード** (ADR 0012): 手元の hook は GitHub の「Merge」ボタンを止められない。`scripts/setup-server-enforcement.sh` で branch protection + required check + merge queue を 1 コマンド設定すれば、Web からのマージや admin の素通りも塞げる (下記)。

### サーバ側 enforcement を有効化する (任意・チーム/恒久向け)

手元の hook を「速い feedback」、GitHub 側を「恒久の関所」に二層化する。

```bash
# 1) CI workflow を配置 (plugin を pin ref で checkout して同じ判定を回す)
cp templates/github/workflows/verification-gate.yml .github/workflows/
#    → ファイル内の PLUGIN_REF をリリースtag/shaに固定

# 2) branch protection を設定 (required checks + enforce_admins=true + PR必須・人間承認0)
scripts/setup-server-enforcement.sh --check    # まず現状監査
scripts/setup-server-enforcement.sh            # 適用
scripts/setup-server-enforcement.sh --merge-queue   # (任意) 古いレーンの統合破壊を再検証
```

`enforce_admins=true` がポイント — 1 人で回していても自分の関所を素通りできないようにする。人間承認は 0 件に設定するので、ソロ開発をロックアウトはしない。

---

## 何を強制するか

- **自律稼働の事前条件 (上流・commission, ADR 0022-0024)**: AI に仕事を渡す行為 (= 作業指示書を `status: ordered` にして commit する) を信号に、12 節 (目的 / 作業範囲 / **変更禁止範囲** / 守るべき既存条件 / **優先順位** / **例外時の判断方法** / 継ぎ目 / 完了条件 / 検証方法 / **停止条件** / 決めてよい・いけない / 事前レビュー) の記入・**完了条件と検証方法の 1 対 1 検算**・事前レビューの全件決着・`retry_limit`/`budget_tokens` の数値・**OPEN な未決への依存**を fail-closed 検査 (`block-commit-if-wo-incomplete.sh`)。新規 source 面の作成には、それをカバーする発注済み指示書を要求 — 編集時 (`block-impl-without-wo.sh`) と、Edit ツールを通らない書き込みを拾う commit 側 (`block-commit-if-impl-uncovered.sh`) の二層 (ADR 0017 と同型)。下書き段階は止めない。上流の決定は新しい機構でなく既存 gate に翻訳して効かせる (2 節 → `.bootstrap/lane` / 3 節 → `arch`・`retired` / 8+9 節 → verification plan)
- **テスト先行**: 実装ファイルを編集する瞬間、対応する test ファイルが無ければ blocking (Red phase 強制)
- **failing test での commit 禁止**: `git commit` 前に test 実行、fail なら blocking
- **依存方向の強制 (architecture)**: project-local の `.bootstrap/arch` で宣言した layer 依存方向に反する import を blocking。edit 時に早期 block (`block-cross-layer-import.sh`)、commit 時に全 file を権威検証 (`block-arch-violations.sh`)。cross-layer は default-deny。SOLID を散文で recite するのではなく、依存辺を deterministic に強制する
- **引退した名前の混入を止める (ADR 0021)**: 改名で引退した語を `.bootstrap/retired` に登記しておくと、**その commit が新しく足した行**に旧称が混ざったとき blocking する (`block-commit-if-retired-term.sh`)。改名は「改名した PR の自己申告」では原理的に漏れる — 改名の *後に* 書く人は、grep すべき語が在ることを知らないから (実例: `Intent.typeNo` 改名の 1h12m 後にマージされた別 PR が旧称を参照し続け、常に `undefined` のまま 3 日以上 UI が壊れた)。検査は追加行だけ (既存の残存で無関係な commit を止めない)。旧称を**説明するために**書いた行 (改名コメント・test fixture・旧 column を読む migration) は、その行に `bootstrap-retired-ok` と書けば 1 行だけ除外できる (marker を消す/パスごと外すより狭く、diff に残るのでレビューで見える)。蓄積した残存は SessionStart の doctor が件数で可視化する。CI net = `scripts/retired-check.sh`
- **lint gate**: commit 前に project の linter (`npm run lint` / `ruff` / `clippy` / `rubocop` 等) を実行、fail なら blocking (`block-commit-if-lint-fails.sh`)。「綺麗さ」のうち linter が見る deterministic な層 (命名規約 / format / 複雑度) だけ gate し、taste (命名の質・設計のセンス) は review に委ねる
- **並列 Claude 安全運用 + 並列開発フロー (sprint)**: 防御 (= 作業を消す/巻き込む経路の blocking) に加え、1 feature を複数 Claude で分業して組み戻す generative フロー
    - `git add -A` / `git commit -a` / `git stash` (path 指定なし) 等の bulk-staging を blocking
    - `git reset --hard` / `git push -f` / `git restore .` / `git clean -fd` / `git branch -D` を blocking (※ `--force-with-lease` は除外)
    - `git commit` 直前に **他 session (= 同一 working tree を共有する別ターミナル) が編集した** file が staged にあれば blocking (`--amend` 含む)。判定は同一 projects dir の sibling transcript を根拠にするので、worktree 隔離下の別 session や同一 session の Bash 生成物 (lockfile / generated) は誤 block しない
    - `.bootstrap/protected` で宣言した branch への直接 push を blocking (opt-in、feature branch + PR / integrate skill 経由に矯正)
    - `sprint-plan` で scope 非重複 task に分解 → worktree の lane (`.bootstrap/lane`) 範囲外の編集 / commit を blocking (ADR 0017) → `integrate` で依存順 merge + 統合 verify
- **verification 最高レバレッジ**: production-affecting な変更は read-back / live assert で実体確認してから完了とする。silent failure / 既存リソース表記推測 / escape 多段 / pattern 拡張 cohort 副作用の 4 罠を `SKILL.md` で明示
- **AI の癖を抑止**: 実装先行 / ハルシネーション / スコープ拡大 / 症状隠蔽 / 既存パターン無視 / 抽象用語に逃げる / 不在を grep 断定 / ルール過剰一般化 / 共有環境独占 / 改名後も旧称で書く の 10 癖を `SKILL.md` で明示
- **bug fix 完遂責任**: user-facing bug の fix は同 PR で同根 cohort audit を要求 (= 報告 N 件の裏で silent dropout が桁違いに居る前提)
- **external memory として docs/ 整備**: `docs/bootstrap/handoffs/` (cold restore) / `docs/decisions/` (ADR) / `docs/bootstrap/incidents/` (事故記録 + memory 昇格) の 3 dir に絞る。`current/` `exploring/` `reference/` `ops/` `archive/` は採用しない (= CLAUDE.md / コード / memory で代替できるか graveyard 化する)。`skills/handoff/` `skills/incident/` が AI の default 経路で書く

## 提供物

各行は 1 行要約 + 正本へのポインタ。**規範の権威は各ファイル本文** (skill / ADR / hook ヘッダコメント) にあり、この表は目次にすぎない。

### skills (規律の正本)

| 提供物 | 要約 |
|---|---|
| `skills/project-bootstrap/SKILL.md` | 規律本体 — 強制の技芸 4 判断 / 上流 (commission) / verification 4 罠 / AI 癖 10 / TDD / 並列 3 形態と統合関所 / 依存方向強制 / docs 整備 / cohort audit。常時ロード |
| `skills/charter/SKILL.md` | `/charter` — 不可逆な判断だけを `docs/bootstrap/commission/charter.md` 1 ファイルに固める。成果物カタログは作らない |
| `skills/order/SKILL.md` | `/order` — 作業指示書 (WO) を 12 節で確定させ発注。lane / verification plan / sprint 判定を WO から生成する |
| `skills/pre-review/SKILL.md` | `/pre-review` — 実装**前**に独立コンテキストの AI を仮想下流リーダーとして使い、5 観点 (曖昧さ / 矛盾 / 未定義の異常系 / DoD の抜け道 / 停止条件の過不足) で仕様を壊させる |
| `skills/accept/SKILL.md` | `/accept` — 検収 (DoD 突合・検算・越境検査・定義ドリフト) と実績記録。`[ズレ]`/`[要判断]` が 1 行でもあれば差し戻し |
| `skills/plan/SKILL.md` | `/plan` — 探索 → 計画 → 提示。実装前に計画書を出して停止 (発注済み WO がある場合は発火しない — WO が計画書そのもの) |
| `skills/handoff/SKILL.md` | `/handoff` — cold restore 用スナップショットを `docs/bootstrap/handoffs/` に残す |
| `skills/incident/SKILL.md` | `/incident` — 事故を `docs/bootstrap/incidents/` に記録し memory `feedback_*`/`reference_*` へ昇格 |
| `skills/sprint-plan/SKILL.md` | `/sprint-plan` — feature を scope 非重複 task に分解し worktree + lane を用意。発火条件 (disjoint leaf ≥ 2 等) を満たすと明示呼び出しを待たず自動起動。並列判定・wip_limit の権威 |
| `skills/integrate/SKILL.md` | `/integrate` — 並列 branch を依存順 merge + 統合 verify + claim close + 終端処理 (board/plan の archive) |
| `skills/verification/SKILL.md` | `/verification` — 動作テストを意図と跨いだ境界から設計し、外部オラクル + `HUMAN` 行で `docs/bootstrap/verification/<branch>.md` に記録・クローズ (ADR 0007)。継ぎ目 7 種 (緑の嘘 / オラクル捕獲 = held-out oracle + metamorphic、ADR 0016 含む) の権威 |

### ADR (不可逆判断の記録、`docs/decisions/`)

| 提供物 | 要約 |
|---|---|
| `0001-subagent-hooks-not-enforced.md` | subagent で hook が発火しなかった時代の「read-only 専用」doctrine (**0004 が部分 supersede**) |
| `0004-parallel-mode-integration-gate.md` | upstream `#21460` 修正の実測確認と並列 3 形態の公認 — 関所は方式でなく統合の入口に |
| `0005-ultracode-execution-engine-governed-by-bootstrap.md` | ultracode/Workflow を bootstrap 統治の実行エンジンに — breadth は無制限 / mutation lane は隔離 + 実検証 |
| `0006-parallel-default-by-execution-form.md` | `wip_limit` は terminal worker lane のみ、Workflow lane は engine 上限 `min(16, cores-2)` 律速 |
| `0007-verification-plan-as-merge-precondition.md` | verification plan (意図アンカー / kill-question / 外部オラクル / `HUMAN`) を統合の precondition に |
| `0008-claude-code-new-primitive-adoption.md` | 新 primitive 採用方針 — `/deep-research` 編入 / cohort-audit prompt hook は opt-in pilot (default 19 hook 外、当時) / exec-form・saved workflow 却下 |
| `0009-stale-trunk-push-freshness-gate.md` | stale checkout からの trunk push を freshness gate (fetch + behind > 0) で block |
| `0010-inject-memory-at-repeat-prone-action.md` | 再発しやすい ACTION の瞬間に記録済み memo を注入 (block しない・CLOSED action-key enum) |
| `0011-cross-repo-contract-drift-gate.md` | cross-repo 契約を `docs/bootstrap/verification/contracts` に登記し、触れた lane に CLOSED plan 行 + consumer スイート緑を要求 |
| `0012-server-side-enforcement-durable-layer.md` | enforcement をローカル hook (速い feedback) + サーバ側 (required check / `enforce_admins=true` / merge queue) に二層化 |
| `0013-surface-repair-vs-spec-intent-at-data-write.md` | data 修復の瞬間に「修復か仕様か」を表面化 (`data-backfill` は arm 不要の普遍 floor) |
| `0014-surface-completion-verification-at-prod-deploy.md` | 本番デプロイの瞬間に完了照合 (逐語照合 / 再解釈はモック確認) を表面化 (`prod-deploy` floor) |
| `0016-hardcode-two-classes-and-held-out-oracle.md` | ハードコード 2 クラス (能力限界 / テストゲーミング) と held-out oracle — 7 番目の seam。secrets は gitleaks を lint+CI へ |
| `0021-retired-name-gate-at-commit-chokepoint.md` | 引退した名前の混入を「commit が足した行」で blocking し、蓄積した残存は doctor で可視化。重複検出は実例が出るまで作らない |
| `0022-upstream-merged-into-bootstrap.md` | 上流工程を別プラグインでなく bootstrap のサブシステムに統合 — 独立を保つと強制層に届かず advisory に戻る (前身 2 実装の敗因) |
| `0023-autonomy-preconditions-as-ordering-gate.md` | 自律稼働の事前条件 12 節を「発注 commit」の precondition に。draft は止めない・tree でなくこの commit が運ぶ WO だけ見る |
| `0024-upstream-quality-measured-by-downstream-telemetry.md` | 上流の品質はエスカレーション / 再試行 / 差し戻し / トークンで測る — 「判断ミスは機械検出できない」は誤りで、曖昧さは下流へ移動して観測される |

### hooks / lib (強制の実体)

| 提供物 | 要約 |
|---|---|
| `hooks/block-commit-if-wo-incomplete.sh` + `hooks/lib/wo.sh` | 発注 (作業指示書を `status: ordered` で commit) に 12 節の記入・DoD⇔検証方法の 1 対 1 検算・事前レビューの全件決着・停止条件の数値・OPEN 未決への非依存を fail-closed 要求 (ADR 0023)。様式の権威は `templates/.../wo/TEMPLATE.md`、判定は lib に集約 |
| `hooks/block-impl-without-wo.sh` | 新規 source 面の作成に、その path をカバーする発注済み作業指示書を要求。sprint gate と信号は同じだが問いが違う (「並列に割れるか判定したか」vs「作ってよいと発注したか」) |
| `hooks/hooks.json` | 24 hook を `plugin.json` 経由でデフォルト発火 — SessionStart doctor / test 先行 / commit 前 lint+test / destructive git op・bulk-stage・cross-session WIP / 保護 branch 直 push・stale push (ADR 0009) / lane 外の編集と commit (ADR 0017) / 未隔離 main tree 編集 (guard 2)・wip 超過 worktree (guard 3) / 依存方向 edit+commit / sprint 発火 gate + reminder / merge 関所 (review + verification) / 引退名の混入 (ADR 0021) / inject-action-memory |
| `hooks/block-merge-if-verification-unclosed.sh` + `hooks/lib/verification-plan.sh` | lane merge に plan の存在・OPEN 行ゼロ・理由なき DROP ゼロを fail-closed 要求 (ADR 0007)。format 権威は lib に集約。ローカルは速い feedback 層 — 恒久は CI twin (ADR 0012) |
| `hooks/lib/verification-ci-check.sh` | 上記のサーバ側 (CI) twin。required status check `verification-closed` として全マージ経路 (Merge ボタン含む) を覆う |
| `hooks/bootstrap-session-doctor.sh` + `scripts/doctor.sh` + `hooks/lib/repo-drift.sh` + `hooks/lib/verification-drift.sh` | SessionStart で 3 軸を可視化 — 採用状態 audit (ADR 0003) / repo drift (stale checkout・merge 済み残置 worktree) / 未判断 trunk 変更 (逐次経路、ADR 0007 委任。source 面判定は `lib/source-face.sh` を再利用)。強制でなく可視化 |
| `hooks/block-unplanned-feature-build.sh` | 新規 source file 作成を信号に、sprint 判定記録 (`docs/bootstrap/sprint/.gate` or 活性 board) を fail-closed 要求 |
| `hooks/sprint-trigger-reminder.sh` | feature っぽい prompt への早期ヒント (強制本体は上記 gate) |
| `hooks/block-unreviewed-merge.sh` | lane branch の merge にレビュー記録 `verdict: approve` + 検出スイートの実走を要求。PR 経路は `templates/ci/bootstrap-review-gate.yml` が CI で同等要求 |
| `hooks/lib/gate-entry.sh` | `.gate` entry の活性判定 (TTL 3 日 / feature-scoped glob のみ有効) |
| `hooks/lib/board-liveness.sh` | 「sprint 進行中か」の共通判定 (存在でなく活性 = 未完了 task の有無) |
| `hooks/lib/arch-check.sh` | 依存方向強制エンジン (`.bootstrap/arch` の parse / layer 判定 / import 解決) |
| `hooks/lib/parse-command.sh` | hook 入力 JSON の string field 抽出の単一権威 (`command` / `file_path` / `cwd` 等。解析不能は呼び出し側が fail-closed に倒せる) |
| `hooks/lib/git-invocation.sh` | git 呼び出し検出の単一権威 (ADR 0019) — グローバルオプション skip + path-prefix + compound command の token walk。全 Bash gate (commit 系 5 / push 2 / merge 2 / add-all) がこれに載る |
| `hooks/lib/lane-set.sh` | lane 集合 (活性 board ∪ linked worktree) 組み立ての単一権威 — 2 つの merge 関所で共有 |
| `hooks/lib/resolve-wip-limit.sh` | `wip_limit` の共通 resolver (`.bootstrap/wip` > form-aware 既定、ADR 0006) |
| `hooks/lib/action-gate.sh` | inject-action-memory の単一権威 — CLOSED action-key enum (`prod-deploy`/`prod-db-migrate`/`data-backfill`) + 普遍 floor memo (ADR 0010/0013/0014)。正規化は `merge-targets.sh` と共有 |
| `hooks/lib/cross-repo-contract.sh` | cross-repo 契約宣言の単一権威 (ADR 0011) — lane の OWN delta を offline 計算し touched 契約 id を返す。consumer 側のみ |
| `hooks/block-commit-if-retired-term.sh` + `hooks/lib/retired-terms.sh` | 引退した名前 (`.bootstrap/retired`) が **この commit の追加行**に混入したら blocking (ADR 0021)。判定エンジンは gate / CI net / doctor の 3 消費者で共有 |
| `hooks/lib/commit-files.sh` | 「この commit が運ぶ file」と `-a` 判定 (`commit_stages_all`) の単一権威 — lane / lint / retired の 3 gate で共有 |
| `hooks/lib/resolve-marker.sh` | opt-in マーカー解決の単一権威 (新フォルダ優先・旧 flat 後方互換、ADR 0015。上記「opt-in 設定ファイル」の注記参照) |
| `tests/hooks/` | 全 hook の bash テスト (jq 非依存ハーネス)。`.github/workflows/test.yml` が self-CI |

### scripts (AI 非依存 CLI) / templates (配布雛形)

| 提供物 | 要約 |
|---|---|
| `scripts/velocity.sh` | 週次 throughput / defect rate の複数 repo 横断計測 — trust ladder の安全網 |
| `scripts/wo-metrics.sh` | 作業指示書ごとの実績集計 (ADR 0024)。節別エスカレーションが「事前条件テンプレートのどこが薄いか」を名指しする。self-report の限界も出力に明記 |
| `scripts/arch-check.sh` | 依存方向検査 CLI (pre-commit / CI 用) |
| `scripts/retired-check.sh` | 引退名検査 CLI (CI 用)。PR は三点差分 `origin/<base>...HEAD` を渡す — 二点だと base 側の改名をこの branch のせいにする |
| `scripts/setup-server-enforcement.sh` | branch protection (required checks / `enforce_admins=true` / PR 必須・人間承認 0) の冪等設定 + `--check` 監査 + `--merge-queue` (ADR 0012) |
| `templates/CLAUDE.md` | 新規プロジェクト用 CLAUDE.md 雛形 (prune 済) |
| `templates/.bootstrap/` | opt-in マーカー雛形一式 (arch / protected / lint / wip / actions.example / retired.example)。フォルダごとコピーして不要分を消す |
| `templates/docs/` | 採用 dir (handoffs / decisions / incidents / sprint / commission) の README + TEMPLATE 一式 |
| `templates/docs/bootstrap/commission/` | 上流工程の雛形 — `charter.md` (不可逆判断 1 ファイル) + `wo/TEMPLATE.md` (作業指示書 12 節) + README (採用マーカー兼運用ガイド) |
| `templates/docs/bootstrap/verification/contracts.example` | cross-repo 契約宣言の雛形 (ADR 0011)。1 行 = `id \| local_face_glob \| peer_repo \| peer_face \| note` |
| `templates/github/workflows/verification-gate.yml` | サーバ側 verification gate の配布雛形 (ADR 0012)。plugin を pin ref で checkout し `verification-ci-check.sh` を実行 |
| `templates/github/workflows/secret-scan.yml` | gitleaks secret-scan の配布雛形 (ADR 0016 Class A の静的半分。独自 matcher は持たない) |
| `templates/github/ruleset.json` | repository ruleset 雛形 — `bypass_actors: []` + required check + merge queue (ADR 0012) |
| `templates/ci/bootstrap-doctor.yml` / `templates/ci/bootstrap-review-gate.yml` / `templates/ci/bootstrap-retired.yml` | plugin 非依存の team-wide CI net (採用 audit / PR レビュー gate / 引退名検査) |

## 使い方

### 1. プラグイン install

```bash
/plugin marketplace add RintaroYamaoka/project-bootstrap
/plugin install project-bootstrap@rintaro-yamaoka
```

検証用に都度ロード:

```bash
claude --plugin-dir /path/to/project-bootstrap
```

### 2. 新規プロジェクトに CLAUDE.md と docs/ を置く

`templates/CLAUDE.md` をプロジェクト root にコピーして、各スロットを埋める。規律は本プラグインが提供するので CLAUDE.md には書き写さない。

```bash
cp /path/to/project-bootstrap/templates/CLAUDE.md /path/to/your-project/CLAUDE.md
cp -r /path/to/project-bootstrap/templates/docs /path/to/your-project/docs
```

`docs/` は 3 dir 構成 (handoffs / decisions / incidents)。上流工程を使うなら `docs/bootstrap/commission/` を足す (`cp -r templates/docs/bootstrap/commission docs/bootstrap/`)。`current/` `exploring/` `reference/` `ops/` `archive/` 等は **採用しない** (= CLAUDE.md / コード / memory で代替できるか graveyard 化する)。必要になったら個別に作る。

### 3. Claude Code でそのプロジェクトを開く

- `CLAUDE.md` が自動ロード
- 実装ファイルを編集しようとすると hook A が対応 test を要求 (= Red phase 強制)
- commit 前に hook B が test 実行
- bulk-stage / destructive git op / cross-session WIP 混入を hook C-E が blocking
- `project-bootstrap` / `plan` / `handoff` / `incident` skill が必要に応じて参照される
- session 終了前 / `/clear` 前は `handoff` skill が `docs/bootstrap/handoffs/` に状態を残す
- 事故 / fix / revert / user 叱責の後は `incident` skill が `docs/bootstrap/incidents/` + memory に教訓を残す

## バージョン / 保守

[CHANGELOG.md](./CHANGELOG.md) / [MAINTENANCE.md](./MAINTENANCE.md) を参照。SemVer に従う。

## ライセンス

MIT License — [LICENSE](./LICENSE) を参照。

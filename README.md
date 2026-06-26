# project-bootstrap

**上位1％の AI 駆動開発を、個人の規律でなく構造として default 化する** Claude Code プラグイン。AI の速度を壊さずに引き出しきるための「強制の技芸」を hook で deterministic に効かせる。

純粋な強制はほとんどの実規律で到達不能 (判断・配備・throughput は hook で縛りきれない) なので、強制を4つの設計判断の連なりに作り替える: **① 分解** (強制可能な precondition と既約な判断に割り、precondition を fail-closed で課す) / **② 信号選び** (proxy でなく行為を信号に、fail-mode を意図的に選ぶ) / **③ 配備の可視化** (効いていない強制を無音にしない) / **④ 計測つきの取引** (throughput と引き換えに緩めるなら戻る根拠を metric で持つ)。明示コマンドで発動する advisory 形式は採用しない (= 忘れられるため)。Anthropic 公式 best practice ([code.claude.com/docs/en/best-practices](https://code.claude.com/docs/en/best-practices)) と整合: verification 最高レバレッジ / hooks deterministic / CLAUDE.md は prune して短く保つ。

## これをどう使うか — 開発者向け運用ガイド

**ひとことで言うと**: あなたは普段どおり Claude Code に頼むだけ。このプラグインは「上手い開発者なら自然にやる規律」(テスト先行・本番前の確認・並列作業の安全・事故の記録) を、AI が忘れても**自動で効くガードレール**にして背後で回す。あなたが覚えることはほとんど無い。下の表は「何が勝手に効くか」と「あなたが手で触れる所」の地図。

### あなたが打てるコマンド (slash)

必要なときに自分で打てる。ただし多くは AI が状況を見て**勝手に呼ぶ**ので、覚えなくても困らない。

| コマンド | 何をしてくれる | いつ自分で打つか |
|---|---|---|
| `/plan <タスク>` | 実装の前に「何を・どこを・どうテストするか」の計画書を出して**止まる**。承認するまでコードを書かない | 大きめ/曖昧な作業の前。スコープを固めたいとき |
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
| **やり直し/叱責の後** | AI が `/incident` を呼んで教訓を memory に残す |
| **本番デプロイ・データ修復・本番 DB migration を打つ瞬間** | 過去の教訓メモが**目の前に出る** (例: 「本番前に各指示文言と実装を逐語照合したか」「この欠落はバグか仕様か」) |

### あなたを止める hook (止まったら、の対処)

危ない操作は **AI もあなたも** 一旦止まる。理不尽に見えたら理由文を読めば、たいてい正しく止めている。

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
scripts/arch-check.sh [file ...]  # 依存方向(レイヤ)違反を検査。Claude非依存なので pre-commit/CI で全員に効かせられる
scripts/setup-server-enforcement.sh --check   # GitHub側の保護設定を監査 (admin素通りの穴を検出)
scripts/setup-server-enforcement.sh           # 保護設定を適用 (下記「サーバ側」参照)
```

### opt-in 設定ファイル (使う分だけ repo root に置く)

**何も置かなければ何も強制されない**。欲しい規律のファイルだけ置く (雛形は `templates/`)。

| ファイル | 置くと効くもの | 中身 |
|---|---|---|
| `.bootstrap-arch` | レイヤ依存方向の強制 | `layer app = app/**` / `allow app -> lib` |
| `.bootstrap-protected` | 宣言ブランチへの直 push 禁止 | `main` (1 行 1 パターン) |
| `.bootstrap-lint` | commit 前の lint gate | 空ファイル (在るだけで有効) |
| `.bootstrap-wip` | 並列 worker 数の上限 | 整数 1 行 (例 `4`) |
| `.bootstrap-actions` | 本番操作の瞬間に出すプロジェクト固有メモ | `prod-deploy \| <memo-slug> \| <一行メモ>` |
| `docs/sprint/` (ディレクトリ) | 並列開発フロー一式の有効化 | 採用マーカー |
| `docs/verification/` (ディレクトリ) | 動作テスト計画の merge gate | 採用マーカー |

### 知っておくと得する仕組み (見落としがちな機能)

- **レビューを薄くする trust ladder**: 全 diff を人間が目視するのが本当の律速。AI が一次レビューして `approve/reject` を記録 → 人間は**verdict とサンプルだけ**読む。安全網は `scripts/velocity.sh` の defect率 — 跳ねたらレビューを 1 段濃く戻す、という客観データで運用する。
- **本番操作メモの自動表示** (ADR 0010/0013/0014): 過去にハマった操作 (本番デプロイ・データ修復) を**打つ瞬間**に教訓が出る。「メモはあったのに事故った」を構造的に潰す。`prod-deploy` と `data-backfill` は arm 不要で普遍メモが出る。
- **複数 repo にまたがる契約の保護** (ADR 0011): フロントとバックなど別 repo の共有スキーマを `docs/verification/contracts` に登記しておくと、片側を変えたとき相手側のテストを通すまで合流できない (無音で割れる事故を防ぐ)。
- **verification の `HUMAN` 行**: AI が確かめられない「これがユーザーの欲しかった物か」は人間に手渡される。あなたが実機で確認して `PASS/FAIL` を記録するまで統合が閉じない。
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

- **テスト先行**: 実装ファイルを編集する瞬間、対応する test ファイルが無ければ blocking (Red phase 強制)
- **failing test での commit 禁止**: `git commit` 前に test 実行、fail なら blocking
- **依存方向の強制 (architecture)**: project-local の `.bootstrap-arch` で宣言した layer 依存方向に反する import を blocking。edit 時に早期 block (`block-cross-layer-import.sh`)、commit 時に全 file を権威検証 (`block-arch-violations.sh`)。cross-layer は default-deny。SOLID を散文で recite するのではなく、依存辺を deterministic に強制する
- **lint gate**: commit 前に project の linter (`npm run lint` / `ruff` / `clippy` / `rubocop` 等) を実行、fail なら blocking (`block-commit-if-lint-fails.sh`)。「綺麗さ」のうち linter が見る deterministic な層 (命名規約 / format / 複雑度) だけ gate し、taste (命名の質・設計のセンス) は review に委ねる
- **並列 Claude 安全運用 + 並列開発フロー (sprint)**: 防御 (= 作業を消す/巻き込む経路の blocking) に加え、1 feature を複数 Claude で分業して組み戻す generative フロー
    - `git add -A` / `git commit -a` / `git stash` (path 指定なし) 等の bulk-staging を blocking
    - `git reset --hard` / `git push -f` / `git restore .` / `git clean -fd` / `git branch -D` を blocking (※ `--force-with-lease` は除外)
    - `git commit` 直前に **他 session (= 同一 working tree を共有する別ターミナル) が編集した** file が staged にあれば blocking (`--amend` 含む)。判定は同一 projects dir の sibling transcript を根拠にするので、worktree 隔離下の別 session や同一 session の Bash 生成物 (lockfile / generated) は誤 block しない
    - `.bootstrap-protected` で宣言した branch への直接 push を blocking (opt-in、feature branch + PR / integrate skill 経由に矯正)
    - `sprint-plan` で scope 非重複 task に分解 → worktree の `.bootstrap-lane` 範囲外編集を blocking → `integrate` で依存順 merge + 統合 verify
- **verification 最高レバレッジ**: production-affecting な変更は read-back / live assert で実体確認してから完了とする。silent failure / 既存リソース表記推測 / escape 多段 / pattern 拡張 cohort 副作用の 4 罠を `SKILL.md` で明示
- **AI の癖を抑止**: 実装先行 / ハルシネーション / スコープ拡大 / 症状隠蔽 / 既存パターン無視 / 抽象用語に逃げる / 不在を grep 断定 / ルール過剰一般化 / 共有環境独占 の 9 癖を `SKILL.md` で明示
- **bug fix 完遂責任**: user-facing bug の fix は同 PR で同根 cohort audit を要求 (= 報告 N 件の裏で silent dropout が桁違いに居る前提)
- **external memory として docs/ 整備**: `docs/handoffs/` (cold restore) / `docs/decisions/` (ADR) / `docs/incidents/` (事故記録 + memory 昇格) の 3 dir に絞る。`current/` `exploring/` `reference/` `ops/` `archive/` は採用しない (= CLAUDE.md / コード / memory で代替できるか graveyard 化する)。`skills/handoff/` `skills/incident/` が AI の default 経路で書く

## 提供物

| 提供物 | 内容 |
|---|---|
| `skills/project-bootstrap/SKILL.md` | 規律本体 (ルール = default 挙動 / verification 4 罠 / TDD / AI 癖 9 個 / バグ根本修正 / 依存方向の強制 / 並列開発フロー / **並列 3 形態と統合関所** (subagent にも hook は効く: 2026-06-11 実測) / 環境隔離 / docs 整備 / cohort audit) |
| `skills/plan/SKILL.md` | `/plan` — 探索 → 計画 → 提示。実装前に計画書を出力 |
| `skills/handoff/SKILL.md` | `/handoff` — session の cold restore に必要な状態を `docs/handoffs/` に書き残す |
| `skills/incident/SKILL.md` | `/incident` — 事故を `docs/incidents/` に記録し、memory `feedback_*` / `reference_*` に昇格させる |
| `skills/sprint-plan/SKILL.md` | `/sprint-plan` — feature を scope 非重複 task に分解し worktree + lane を用意 (並列開発の計画)。**default 発火**: feature が scope 非重複の leaf 2 個以上 (≤ `wip_limit`) に割れると判断したら、明示呼び出しを待たず自動で分解する (= advisory 不採用方針の徹底)。bug fix / refactor / 単一 file / 自明な変更には発火しない |
| `skills/integrate/SKILL.md` | `/integrate` — 並列 branch を依存順 merge + 統合 verify + claim close + verification plan の終端処理 |
| `skills/verification/SKILL.md` | `/verification` — 動作テストを**意図と跨いだ境界から**設計し (実装からでなく)、各行に外部オラクルを与え `docs/verification/<branch>.md` に記録、人間と共同でクローズ (ADR 0007)。継ぎ目 (cross-repo 契約 / 要件 / 「実物を見ずの完了」/ 環境) を担う |
| `docs/decisions/0001-subagent-hooks-not-enforced.md` | ADR (**0004 が部分 supersede**) — かつて hook が subagent で発火しなかった時代の「subagent は read-only」doctrine |
| `docs/decisions/0004-parallel-mode-integration-gate.md` | ADR — upstream `#21460` 修正の実測確認と**並列 3 形態 (terminal worker / PR / Workflow worktree) の公認**。関所は方式でなく統合の入口 (手元 merge は worktree 痕跡、PR は CI) に置く |
| `docs/decisions/0005-ultracode-execution-engine-governed-by-bootstrap.md` | ADR — ハーネスの `ultracode`/Workflow を独立方式でなく **bootstrap が governance する実行エンジン**と位置づけ (0004 を一般化)。breadth (read-only) は無制限・gate ゼロ / mutation lane は隔離 + `wip_limit` + 実検証。hook は内部 spawn を見ないので WIP・隔離は merge/commit 時に縛る。4 設計判断は 5 にしない |
| `docs/decisions/0006-parallel-default-by-execution-form.md` | ADR — 並列 default を**実行形態で分離** (0005 の `wip_limit` 適用範囲を精緻化)。`wip_limit` は terminal worker lane (= 帯域律速・`git worktree add`) の cap のみ、Workflow/subagent lane は engine 上限 `min(16, cores-2)` 律速で `wip_limit` 非対象・帯域は統合関所が自動で守る。worker 既定を 2-3 → 3-4。「2-3 が全形態の天井」という誤読 (= 体感「並列が少ない」の正体) を断つ。④ の適用であって新軸ではない |
| `docs/decisions/0007-verification-plan-as-merge-precondition.md` | ADR — **動作テスト設計を「意図アンカーの verification plan」として構造化し統合の precondition にする**。コードバグは TDD で潰れ残余は継ぎ目に移動 (mood incident: 緑の unit test が誤契約を固定し全予約 reject)。原則=テストは実装でなく意図と境界から導く。`docs/verification/<branch>.md` を lane merge の precondition に。kill-question / 外部オラクル / `HUMAN` フラグ。④ の適用であって新軸ではない |
| `docs/decisions/0008-claude-code-new-primitive-adoption.md` | ADR — **Claude Code 新 primitive の採用方針**。`/deep-research` を read-only 外部オラクル腕として skills に編入 (#1) / advisory 規律を確率 gate 化する `prompt` hook を **opt-in pilot** 化 (#2、初の非決定論 gate、warn-only、default 19 hook 外) / exec-form は untrusted 入力が無く rent を払わず却下 (#3) / saved workflow は plugin 配布不可で却下 (#4)。版番号は信頼せず機能の存在で判断 (`hooks/README.md` の harness contract と同規律) |
| `docs/decisions/0009-stale-trunk-push-freshness-gate.md` | ADR — **stale な checkout からの trunk push を freshness gate で止める**。stale-checkout 由来の本番化事故 2 件 (24 commit 遅れの prod migration / 進んだ remote を取りこぼす push) を根に、`git push` という決定論的行為だけを信号に、fetch 後 behind > 0 なら block。block-push-to-protected (PR-flow) と直交し freshness を守る。staleness 判定は online/offline で `lib/repo-drift.sh` の単一権威 |
| `docs/decisions/0010-inject-memory-at-repeat-prone-action.md` | ADR — **再発しやすい ACTION の瞬間に記録済み memo を注入する** (inject-at-action)。fix が memory に在っても操作の瞬間に目の前に無く deploy-author bug が ~7 回再発した穴を、PreToolUse(Bash) の visibility で埋める (block しない・ack も取らない、ADR 0001 の「理解は強制不能」に従う)。マッチャは plugin 所有の CLOSED な action-key enum (per-entry regex でない)、registry は opt-in marker |
| `docs/decisions/0011-cross-repo-contract-drift-gate.md` | ADR — **cross-repo 契約ズレを「登記された継ぎ目」として統合の precondition にする**。ADR 0007 の cross-repo 拡張。mood 型 (片側 relax の無音破壊) を根に、`docs/verification/contracts` に共有面を登記し、lane の OWN delta (base..lane を offline 計算) が登記面を触ったら、その契約の CLOSED plan 行 + consumer スイート実走 (緑) を merge の precondition にする。gate は相手 repo を読まない (consumer 側のみ) |
| `docs/decisions/0012-server-side-enforcement-durable-layer.md` | ADR — **enforcement をローカル hook (速い feedback 層) とサーバ側 (恒久 enforcement 層) に二層化する**。deep-research で外部一次資料化した 3 穴を根に: ローカル merge hook は GitHub の Merge ボタン (サーバ側) を捕まえられない / branch protection はデフォルト admin 非適用で単一 orchestrator が自分の関所を素通り / lane 限定 pre-merge は stale 統合破壊を見逃す。同じ判定 (verification-plan.sh 単一権威) を CI で再実行し required status check + `enforce_admins=true` + merge queue に登録。契約方式は変えず (Pact の中央 Broker は並列開発の直列化点なので採らない) |
| `docs/decisions/0013-surface-repair-vs-spec-intent-at-data-write.md` | ADR — **データ修復 (backfill/UPDATE/migration) の瞬間に「修復か仕様か」の意図確認を表面化する**。inject-at-action (ADR 0010) 拡張。AI が「値が欠けている=バグ」と推測し domain owner 確認前に多段 backfill を組んだ incident を根に (100% 系統的 = defect でなく spec の徴候・同じ値でもレーンで妥当性が真逆・オラクルは data でなく人間)。`data-backfill` を CLOSED enum に追加し、plugin 所有のデフォルト doctrine を **registry 未 arm でも常時発火** (普遍安全則ゆえ opt-in を 1 キーだけ緩和)。block しない可視化 (意図確認は既約 = ADR 0001) |
| `docs/decisions/0014-surface-completion-verification-at-prod-deploy.md` | ADR — **本番デプロイの瞬間に「完了照合 (逐語照合 + 再解釈はモック確認)」を表面化する**。inject-at-action (ADR 0010/0013) 拡張。AI が複数文言の明示指示を自分の都合のよい解釈に置換し、各文言と実装の照合をせず「完了」と虚偽報告して誤仕様を本番デプロイした incident (appo-followup `2026-06-26-premature-completion-and-misimplemented-reservation-notify`) と、逆に明示指示を実行せず質問で押し返した裏面 incident を根に。既存 `prod-deploy` キーの `action_default_memo` 空欄を埋め、(1) 各指示文言を実装と逐語照合 (2)「〜のような既存機能」は実データ挙動を先に確認 (3) 解釈を置換した重要機能は二択メニューでなく出力モックで確認、を **registry 未 arm でも常時発火** (data-backfill に続く 2 つ目の普遍 floor、ADR 0013:46 の「prod-deploy は opt-in」を更新)。block しない可視化 (完了照合は既約 = ADR 0001) |
| `hooks/hooks.json` | 19 hook を `plugin.json` 経由でデフォルト発火 (SessionStart 採用 audit + repo drift 可視化 + 未判断 trunk 変更の可視化 / test 先行 / commit 前 lint+test / destructive git op / bulk-stage / cross-session WIP / 宣言 branch 直 push / trunk への stale push の freshness block (fetch+behind、ADR 0009) / lane 外編集 / active lane 中の main tree 未隔離 source 編集の block (ADR 0005 guard 2) / `wip_limit` 超過の `git worktree add` の block (guard 3) / 依存方向 edit+commit / sprint 発火判定 gate + reminder / レビューなき並列 lane branch merge の block + approve 後の検出スイート実行 (guard 1) / verification plan が閉じていない lane branch merge の block (ADR 0007) / 再発しやすい action 直前に該当 memory を additionalContext 注入 (block しない、ADR 0010/0013/0014)) |
| `hooks/block-merge-if-verification-unclosed.sh` + `hooks/lib/verification-plan.sh` | PreToolUse hook (opt-in: `docs/verification/` 採用 project) + フォーマット権威 lib。lane branch の `git merge` を信号に、`docs/verification/<branch>.md` の存在・非空・OPEN 行 (TODO/FAIL/HUMAN) ゼロ・理由なき DROP ゼロを fail-closed で要求 (ADR 0007 guard)。plan 不在は fail-open に逃さず block。format 権威 (status 語彙 + branch→plan パス導出 `vplan_path_for_branch`) は lib に集約 (gate/doctor/skill 共有 = drift 防止)。**ただしこのローカル hook は速い feedback 層であって権威ではない (ADR 0012)** — GitHub の Merge ボタンは素通りするので恒久 enforcement は下記 CI twin + サーバ側に置く |
| `hooks/lib/verification-ci-check.sh` | block-merge-if-verification-unclosed の **サーバ側 (CI) twin** (ADR 0012)。同じ判定 (verification-plan.sh 単一権威) を CI で再実行し、branch を stdin の hook JSON でなく `git`/`GITHUB_HEAD_REF` から解決する点だけが違う。required status check (`verification-closed`) として全マージ経路 (ローカル merge / GitHub Merge ボタン / API) を覆う。CI を偽 red で止めないため、未採用/plan 不在/branch 不解決は neutral pass。`templates/github/workflows/verification-gate.yml` (配布) と `.github/workflows/verification-gate.yml` (dogfood) が回す |
| `hooks/bootstrap-session-doctor.sh` + `scripts/doctor.sh` + `hooks/lib/repo-drift.sh` + `hooks/lib/verification-drift.sh` | SessionStart hook + 判定エンジン。session 起動時に (1) **採用状態を audit** (未採用なら導入を一度だけ尋ね / 採用済みで gate 配備漏れ partial なら警告、ADR 0003)、(2) **repo drift を可視化** — `HEAD` が `origin/main` より遅れている (stale checkout: 本番操作前の追従確認漏れ) / **merge 済みなのに残っている worktree** (lane 撤去漏れ)、(3) **未判断の trunk 変更を可視化** — 逐次の source 変更があるのに動作テストの要否判断 (`docs/verification/<branch>.md`) が無い状態 (merge gate は lane branch の merge しか見ないので逐次作業はその射程外。ADR 0007 が doctor に委ねた半分) を surface する。3 軸は独立 (採用が ok でも drift / 未判断は出す)。fetch しない (offline/高速) ので遅れは過小報告側に倒れ誤警告しない。強制でなく可視化 (判断は既約)。plugin 非依存の team-wide net は `templates/ci/bootstrap-doctor.yml` |
| `hooks/block-unplanned-feature-build.sh` | PreToolUse hook (opt-in: `docs/sprint/` 採用 project)。**新規 source file を作ろうとした瞬間** (= feature 面を作る行為そのものを信号にする)、sprint 発火判定の記録 (`docs/sprint/.gate`) も進行中 sprint (`board.json`) も無ければ `exit 2`。sprint を起動はせず「判定を済ませた precondition」だけを fail-closed で強制する (TDD hook と同型)。advisory な語彙 reminder の穴を根治する |
| `hooks/sprint-trigger-reminder.sh` | UserPromptSubmit hook。feature 実装っぽい prompt のとき sprint 発火判定 3 条件を context 注入する**早期ヒント**。強制本体は上記 gate なので、語彙 regex の取りこぼしは致命的でない |
| `hooks/block-unreviewed-merge.sh` | PreToolUse hook (opt-in: `docs/sprint/` 採用 project)。**AI レビューを統合の precondition に強制** — 並列 lane の branch (= 活性 board の task branch ∪ **linked worktree に checkout された branch**、board 不要) の `git merge` 時、レビュー記録 (`docs/sprint/reviews/`) の `verdict: approve` が無ければ `exit 2`、`reject` はより強く block。GitHub PR 画面の merge は手元 hook を通らないため、PR 経路は `templates/ci/bootstrap-review-gate.yml` が CI で同じ記録を要求する。人間の全 diff 直列レビュー (throughput の律速) を verdict + サンプル監査に置き換える trust ladder の Stage 2 |
| `hooks/lib/gate-entry.sh` | `.gate` entry の活性判定 (日付 + TTL 3 日 / feature-scoped glob)。1 行の全域 glob が gate を恒久 fail-open にした実事故の根治 |
| `hooks/lib/board-liveness.sh` | 「sprint が進行中か」の共通判定 (= board.json の存在でなく**活性** = 未完了 task の有無)。sprint gate と review gate が共有 — gate 信号の drift 防止 |
| `scripts/velocity.sh` | 週次 throughput / defect rate の**複数 repo 横断**計測 CLI。レビューを trust ladder で薄くしたとき「壊れていない」を判定する客観データ (defect rate が跳ねたら 1 段戻す) |
| `hooks/lib/arch-check.sh` | 依存方向強制エンジン (`.bootstrap-arch` parse / layer 判定 / import 解決)。jq 非依存 |
| `hooks/lib/parse-command.sh` | Bash tool の `command` 値を JSON から取り出す共通 parser。コンマ/エスケープで切れない、解析不能時は呼び出し側が fail-closed に倒せる。jq 非依存 |
| `hooks/lib/resolve-wip-limit.sh` | `wip_limit` 表示値の共通 resolver。repo root の `.bootstrap-wip` (整数 1 行、opt-in) を読んで sprint 系 hook の checklist を実値化、不在/解析不能は **form-aware な既定 (worker 3-4・Workflow lane は wip 非対象、ADR 0006)** に fail-open (解析不能の可視化は doctor)。board.json は per-sprint ephemeral なので既定の正本にしない。jq 非依存 |
| `hooks/lib/repo-drift.sh` | SessionStart doctor の **repo drift 判定**エンジン。`HEAD` の `origin/main` 遅れ commit 数 (stale checkout 類) と **merge 済み worktree の残骸** (lane 撤去漏れ) を返す純関数群。fetch しない (offline/高速、遅れは過小報告側に倒れ誤警告ゼロ)。jq 非依存 |
| `hooks/lib/verification-drift.sh` | SessionStart doctor の **未判断 trunk 変更 判定**エンジン。`docs/verification/` 採用済み repo で、current branch に source-face 変更 (未コミット ∪ main ref より先行 commit) があるのに verification 判断が記録されていない (plan 不在/空) 状態を surface する純関数。merge gate が捕まえない逐次経路を可視化 (ADR 0007 の委任)。可視化のみ (block しない)、要否判断の**不在**だけを対象 (OPEN plan の closure は merge gate / 将来の push-time 拡張)。fetch しない・opt-in・jq 非依存。`is_source_path`/`drift_main_ref`/`vplan_*` を再利用 |
| `hooks/lib/action-gate.sh` | inject-action-memory の **「この command は再発しやすい ACTION か、どれか」の単一権威** (D2、ADR 0010/0013)。command をトークナイズし plugin 所有の **CLOSED な action-key enum** (`ACTION_KEY_ENUM` = `prod-deploy` / `prod-db-migrate` / `data-backfill`) に写す。`merge-targets.sh` と同じ正規化 (env-prefix 除去 / path-prefixed bin / `npx`・`bash -c` unwrap / compound walk)。per-entry user regex を排し未レビュー matcher 事故を構造的に締め出す (hook と doctor が共有 = drift 防止)。`action_default_memo` が plugin 所有の普遍 doctrine を返す (registry 未 arm でも出る 2 つの floor: `data-backfill` = 修復か仕様か (ADR 0013) / `prod-deploy` = 完了照合・再解釈モック確認 (ADR 0014))。jq 非依存 |
| `hooks/lib/cross-repo-contract.sh` | cross-repo 契約宣言の **単一権威** (D3、ADR 0011)。merge gate と doctor が共有 (信号 drift 防止)。`docs/verification/contracts` (行指向 `id \| local_face_glob \| peer_repo \| peer_face \| note`) を parse し、中核 `branch_changed_sources` が **lane の OWN delta (base..lane) を offline 計算** (PreToolUse 時 HEAD=main で空になる罠を回避)、登記 glob と交差させ touched 契約 id を返す。consumer 側のみ — 相手 repo を読まない・diff しない。jq 非依存 |
| `tests/hooks/` | 全 hook の bash テスト (jq 非依存ハーネス、TDD で自己検証)。`.github/workflows/test.yml` が push / PR で全 suite を回す (self-CI) |
| `templates/CLAUDE.md` | 新規プロジェクト用 CLAUDE.md 雛形 (Anthropic exclude 表で prune 済) |
| `templates/.bootstrap-arch` | 依存方向契約の雛形 (layer / alias / allow 辺) |
| `templates/.bootstrap-wip` | project 既定 `wip_limit` 宣言の雛形 (整数 1 行) |
| `templates/docs/` | 採用 dir (handoffs / decisions / incidents / sprint) の README + TEMPLATE 一式 |
| `templates/bootstrap-actions.example` | inject-action-memory 用の opt-in registry 雛形 (ADR 0010/0013)。repo root に `.bootstrap-actions` としてコピー。1 行 = `<action-key> \| <memory-slug-or-path> \| <note>`、action-key は plugin の CLOSED enum (`prod-deploy`/`prod-db-migrate`/`data-backfill`) から選ぶだけ (match pattern は書かない)。無ければ project 固有メモは無音 (ただし `data-backfill` (ADR 0013) と `prod-deploy` (ADR 0014) の普遍 doctrine は arm せずとも出る) |
| `templates/docs/verification/contracts.example` | cross-repo 契約宣言の雛形 (ADR 0011)。各参加 repo の `docs/verification/contracts` に置く。1 行 = `id \| local_face_glob \| peer_repo \| peer_face \| note`。宣言なき共有スキーマの無音破壊 (mood incident) を observable な FACT にする。plan 行は `[contract:<id>]` タグで参照、gate は相手 repo を読まない |
| `templates/github/workflows/verification-gate.yml` | サーバ側 verification gate の配布雛形 (ADR 0012)。adopting repo の `.github/workflows/` にコピーし、plugin を pin ref で checkout して `verification-ci-check.sh` を回す (判定の単一権威を plugin に残しローカル hook と drift させない)。`verification-closed` を required status check に登録する |
| `templates/github/ruleset.json` | GitHub repository ruleset 雛形 (ADR 0012)。複数 repo 横展開用。`gh api -X POST repos/OWNER/REPO/rulesets --input` で適用。`bypass_actors: []` (admin も含め誰も素通りしない = 穴 2) + required check + merge queue + non_fast_forward を集約 (「最も制限的版が勝つ」) |
| `scripts/setup-server-enforcement.sh` | `gh` で branch protection (required checks = `verification-closed` + `hooks` / **`enforce_admins=true`** / PR 必須・人間承認 0 = solo を lock out しない) を冪等設定する再利用スクリプト (ADR 0012)。`--merge-queue` で merge queue、`--check` で現状監査 (admin 素通り検出)。サーバ側恒久層の配備を 1 コマンド化 |

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

`docs/` は 3 dir 構成 (handoffs / decisions / incidents)。`current/` `exploring/` `reference/` `ops/` `archive/` 等は **採用しない** (= CLAUDE.md / コード / memory で代替できるか graveyard 化する)。必要になったら個別に作る。

### 3. Claude Code でそのプロジェクトを開く

- `CLAUDE.md` が自動ロード
- 実装ファイルを編集しようとすると hook A が対応 test を要求 (= Red phase 強制)
- commit 前に hook B が test 実行
- bulk-stage / destructive git op / cross-session WIP 混入を hook C-E が blocking
- `project-bootstrap` / `plan` / `handoff` / `incident` skill が必要に応じて参照される
- session 終了前 / `/clear` 前は `handoff` skill が `docs/handoffs/` に状態を残す
- 事故 / fix / revert / user 叱責の後は `incident` skill が `docs/incidents/` + memory に教訓を残す

## バージョン / 保守

[CHANGELOG.md](./CHANGELOG.md) / [MAINTENANCE.md](./MAINTENANCE.md) を参照。SemVer に従う。

## ライセンス

MIT License — [LICENSE](./LICENSE) を参照。

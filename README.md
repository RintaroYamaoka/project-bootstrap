# project-bootstrap

**上位1％の AI 駆動開発を、個人の規律でなく構造として default 化する** Claude Code プラグイン。AI の速度を壊さずに引き出しきるための「強制の技芸」を hook で deterministic に効かせる。

純粋な強制はほとんどの実規律で到達不能 (判断・配備・throughput は hook で縛りきれない) なので、強制を4つの設計判断の連なりに作り替える: **① 分解** (強制可能な precondition と既約な判断に割り、precondition を fail-closed で課す) / **② 信号選び** (proxy でなく行為を信号に、fail-mode を意図的に選ぶ) / **③ 配備の可視化** (効いていない強制を無音にしない) / **④ 計測つきの取引** (throughput と引き換えに緩めるなら戻る根拠を metric で持つ)。明示コマンドで発動する advisory 形式は採用しない (= 忘れられるため)。Anthropic 公式 best practice ([code.claude.com/docs/en/best-practices](https://code.claude.com/docs/en/best-practices)) と整合: verification 最高レバレッジ / hooks deterministic / CLAUDE.md は prune して短く保つ。

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
| `hooks/hooks.json` | 17 hook を `plugin.json` 経由でデフォルト発火 (SessionStart 採用 audit + repo drift 可視化 + 未判断 trunk 変更の可視化 / test 先行 / commit 前 lint+test / destructive git op / bulk-stage / cross-session WIP / 宣言 branch 直 push / lane 外編集 / active lane 中の main tree 未隔離 source 編集の block (ADR 0005 guard 2) / `wip_limit` 超過の `git worktree add` の block (guard 3) / 依存方向 edit+commit / sprint 発火判定 gate + reminder / レビューなき並列 lane branch merge の block + approve 後の検出スイート実行 (guard 1) / verification plan が閉じていない lane branch merge の block (ADR 0007)) |
| `hooks/block-merge-if-verification-unclosed.sh` + `hooks/lib/verification-plan.sh` | PreToolUse hook (opt-in: `docs/verification/` 採用 project) + フォーマット権威 lib。lane branch の `git merge` を信号に、`docs/verification/<branch>.md` の存在・非空・OPEN 行 (TODO/FAIL/HUMAN) ゼロ・理由なき DROP ゼロを fail-closed で要求 (ADR 0007 guard)。plan 不在は fail-open に逃さず block。format 権威 (status 語彙 + branch→plan パス導出 `vplan_path_for_branch`) は lib に集約 (gate/doctor/skill 共有 = drift 防止) |
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
| `tests/hooks/` | 全 hook の bash テスト (jq 非依存ハーネス、TDD で自己検証)。`.github/workflows/test.yml` が push / PR で全 suite を回す (self-CI) |
| `templates/CLAUDE.md` | 新規プロジェクト用 CLAUDE.md 雛形 (Anthropic exclude 表で prune 済) |
| `templates/.bootstrap-arch` | 依存方向契約の雛形 (layer / alias / allow 辺) |
| `templates/.bootstrap-wip` | project 既定 `wip_limit` 宣言の雛形 (整数 1 行) |
| `templates/docs/` | 採用 dir (handoffs / decisions / incidents / sprint) の README + TEMPLATE 一式 |

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

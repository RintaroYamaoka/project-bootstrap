# hooks/

`project-bootstrap` の規律を **deterministic に強制する hook 集**。`plugin.json` の `hooks` フィールド経由でデフォルト発火する (= ユーザーが叩かなくても常に動く)。

## 提供する hook

### A. PreToolUse on `Edit | Write | MultiEdit` — テスト先行強制

実装ファイルを編集しようとした瞬間、対応 test ファイルが無ければ `exit 2` で **blocking**。これで「テスト書かずに実装」が default で構造的に不可能になる (Red phase 強制)。

- 実装ファイル: `.ts/.tsx/.js/.jsx/.mjs/.cjs/.py/.go/.rs/.rb/.php/.java/.cs/.cpp/.c/.swift/.kt/.scala/.ex/.exs/.clj/.hs/.ml`
- test ファイル自身 / markdown / config / settings は素通し
- **`scripts/_*` も素通し** — `scripts/_foo.mjs` のような prefix `_` 付きは ephemeral debug / one-shot recovery script の慣行 namespace。test companion を要求するのは過剰なので除外する
- 対応 test の検出は慣例パターン (`foo.test.ts` / `foo.spec.ts` / `foo_test.go` / `test_foo.py` / `spec/foo_spec.rb` / `tests/` 配下 / `__tests__/` 配下) を順次探索
- `tests/` の深い階層 (例: `tests/unit/<layer>/foo.test.ts`) も再帰的に検索する

#### Windows path 対応

Claude Code は Windows 環境で `\` 区切り絶対 path を JSON-escape 済 (= literal `\\`) で渡してくる。hook 内で `tr` 経路により forward slash に正規化してから case パターン判定する (= `tr '\\\\' '/' | tr -s '/'`、`sed` は Git Bash の GNU sed で「unterminated `s' command」を吐くため使えない)。

スクリプト: [`require-test-companion.sh`](./require-test-companion.sh)

### G. PreToolUse on `Edit | Write | MultiEdit` — 並列 lane 強制

並列開発 (sprint) で各ワーカーが自分の git worktree でだけ作業するよう、worktree root の `.bootstrap-lane` (1 行 1 glob、`#` コメント可) が宣言した範囲外の file 編集を `exit 2` で blocking。これで「1 task = 1 owner = 1 worktree」が決定論的な境界になる。

- `.bootstrap-lane` が **無ければ素通し** (= sprint を使っていない通常作業は一切妨げない)
- glob は bash `[[ ]]` パターン。`*` が `/` も跨ぐので `src/auth/**` も `src/auth/*` も nested path に効く
- worktree 外の絶対 path は判断不能として fail-open
- jq 非依存。hook が読むのは worktree-local な `.bootstrap-lane` だけ (= board.json の rich な真実は lead / skill が読み書きする)

スクリプト: [`block-out-of-lane-edit.sh`](./block-out-of-lane-edit.sh)

### K. PreToolUse on `Edit | Write | MultiEdit` — sprint 発火判定を fail-closed 強制

**新規 source file を作ろうとした瞬間**、sprint 自動分解の発火判定が記録されていなければ `exit 2` で blocking。かつて sprint 発火は `sprint-trigger-reminder.sh` (UserPromptSubmit) の **advisory** だけで担保され、判定も実行もモデル任せだった (= 長い会話で忘れられ一度も発火しない実事故あり: [`docs/incidents/2026-05-31-sprint-advisory-silent/`](../docs/incidents/2026-05-31-sprint-advisory-silent/README.md))。本 hook は TDD/lane/arch と同型に、その判定を precondition として強制する。

- **信号は prompt の語彙ではなく「新規 source file を作る行為そのもの」**。語彙 regex は proxy で自然言語の言い回しに穴があったが、行為信号は言い方に依存しない
- hook は **sprint を起動しない** (worktree 起動=人間 / disjoint 判定=モデル。ADR 0001 の既約な残余)。「gate 判定を済ませた」ことだけを強制する
- **opt-in**: `docs/sprint/` が在る project でのみ発火 (= `.bootstrap-arch`/`-lane`/`-protected` と同じ採用宣言)。無ければ fail-open
- **fail-open (根拠不在)**: file_path 不在 / 非 git / 既存 file の編集・上書き / test・config・doc / 非 source 拡張子 / `scripts/_*`。bug fix / refactor は一切 trip しない
- gate を通す記録 = `docs/sprint/.gate` (gitignore, ephemeral)。各行 `<scope-glob>  <理由>` (1 列目が glob)。記録 scope 内の新規 source は素通し、scope 外は再 block (= 新しい disjoint 面 → 再判定)。進行中 sprint (`board.json` 非空) なら lane hook が scope を握るので素通し
- checklist の `wip_limit` 表示は repo root の **`.bootstrap-wip`** (整数 1 行、opt-in) を読んで実値化する (エンジン = [`lib/resolve-wip-limit.sh`](./lib/resolve-wip-limit.sh)、`sprint-trigger-reminder.sh` と共有)。不在・解析不能なら「既定 2-3」に fail-open (= 表示であって blocking 信号ではない。解析不能の可視化は `scripts/doctor.sh` が担う)。board.json の `wip_limit` を読まないのは、board が per-sprint の ephemeral state で逸脱値 (`_wip_note`) を含み、sprint 終了後に stale になるため

スクリプト: [`block-unplanned-feature-build.sh`](./block-unplanned-feature-build.sh)

### I. PreToolUse on `Edit | Write | MultiEdit` — 依存方向の早期強制

編集が `.bootstrap-arch` の依存方向に反する import を導入しようとした瞬間に `exit 2` で blocking (= 書いた瞬間に止め手戻りを防ぐ)。PreToolUse なので新内容はまだ disk に無く、hook input JSON を最小 unescape して新内容中の import specifier を抽出・検査する。

- `.bootstrap-arch` 不在 / layer 外の file は **fail-open**
- cross-layer は default-deny。許可は `allow FROM -> TO` 辺のみ。同 layer / 外部 package は許可
- エンジンは [`lib/arch-check.sh`](./lib/arch-check.sh)。対応言語 ts/tsx/js/jsx/mjs/cjs/py
- 詳細は SKILL.md「依存方向を強制する」節

スクリプト: [`block-cross-layer-import.sh`](./block-cross-layer-import.sh)

### B. PreToolUse on `Bash` — failing test での commit を禁止

`git commit` が呼ばれる直前にプロジェクト慣例のテストコマンドを実行。fail なら `exit 2` で **blocking**。

検出する test command:

| プロジェクトマーカー | 実行 command |
|---|---|
| `package.json` (`"test"` script あり) | `npm test --silent` |
| `pyproject.toml` / `pytest.ini` | `uv run pytest -q` or `pytest -q` |
| `go.mod` | `go test ./...` |
| `Cargo.toml` | `cargo test --quiet` |
| `Gemfile` | `bundle exec rspec` |

検出できない場合は警告だけで素通し。プロジェクト固有の test command がある場合は `.claude/settings.json` で override する。

スクリプト: [`block-commit-if-tests-fail.sh`](./block-commit-if-tests-fail.sh)

### J. PreToolUse on `Bash` — failing lint での commit を禁止 (opt-in)

repo root に `.bootstrap-lint` を置いた project だけ発火する。`git commit` 直前に project の lint command を実行し、fail なら `exit 2`。「綺麗なコード」のうち **linter が見る deterministic な層** (命名規約 / format / 未使用 / 複雑度しきい値) だけを強制する。命名の質・設計のセンスといった taste は対象外 (= 人間レビュー / `code-review` skill の領分)。プラグインが綺麗さを判断せず project の linter に委ねる。

**`.bootstrap-lint` が無ければ素通し** (= 既定 opt-out)。lint は project ごとに設定が違い、未設定 (例: `next lint` が ESLint 未設定で対話プロンプトに落ち exit 1) のリポを always-on で巻き込むと commit を壊すため、明示宣言で opt-in する (`.bootstrap-arch` / `.bootstrap-lane` / `.bootstrap-protected` と同じ思想)。

| マーカー | 実行 command (runner が PATH にある場合のみ) |
|---|---|
| `package.json` (`"lint"` script あり) | `npm run lint --silent` |
| `pyproject.toml` / `.ruff.toml` / `.flake8` | `ruff check .` or `flake8` |
| `go.mod` | `golangci-lint run` |
| `Cargo.toml` | `cargo clippy -- -D warnings` |
| `Gemfile` | `rubocop` |

linter が解決できない (script 無し / runner 不在) 場合は warn して素通し。**全分岐に `command -v` ガード**があり、toolchain 不在マシンで誤 block しない。

スクリプト: [`block-commit-if-lint-fails.sh`](./block-commit-if-lint-fails.sh)

### C. PreToolUse on `Bash` — destructive git op を blocking

並走している別 Claude / 別ターミナル / IDE の作業を消す destructive な git 操作を `exit 2` で **blocking**。

検出 pattern:

| pattern | 何を消すか |
|---|---|
| `git reset --hard` | uncommitted 全消去 (= 自他 session の WIP) |
| `git push -f` / `--force` | remote の他人 commit |
| `git checkout -- .` / `<path>` | unstaged 全消去 |
| `git restore .` / `--staged .` | 全 restore |
| `git clean -f` / `-fd` / `-fx` | untracked 全消去 (= 他 session の新規 file) |
| `git branch -D` | 未 merge branch 強制削除 |

`git push --force-with-lease` は競合検出付きなので素通し。意図して実行するときは user に明示確認してから `/permissions` で hook を一時 deny にする。

スクリプト: [`block-dangerous-git-ops.sh`](./block-dangerous-git-ops.sh)

### D. PreToolUse on `Bash` — bulk-staging を blocking

同一 working tree で並走する別 Claude / 別ターミナル / IDE の WIP を巻き込む bulk-staging 操作を `exit 2` で **blocking**。**自分が編集した file を個別 path 指定で add する**規律を強制する。

検出 pattern:

| pattern | 巻き込むもの |
|---|---|
| `git add -A` / `--all` | cwd 配下の全 tracked + untracked |
| `git add .` / `./` | cwd 配下を全 stage |
| `git add -u` / `--update` | 全 tracked |
| `git commit -a` / `-am` / `--all` | 全 tracked を auto-stage |
| `git stash -u` / `--include-untracked` | 他人 untracked も退避 |
| `git stash` (path 指定なし) | 全 modified |

`git add path/to/file` のような個別 path 指定は素通し。

スクリプト: [`block-add-all.sh`](./block-add-all.sh)

### E. PreToolUse on `Bash` for `git commit` — cross-session WIP 混入を blocking

`git commit` 直前に session transcript と `git diff --cached --name-only` を照合し、**当 session で編集していない file が staged にあれば** `exit 2` で **blocking**。

仕組み:

1. hook input の `transcript_path` から session JSONL を読む
2. `Edit` / `Write` / `MultiEdit` / `NotebookEdit` の `file_path` / `notebook_path` を抽出して self-edited set を build
3. `git diff --cached --name-only` の各 file が self-edited set に含まれているか check
4. 含まれていない file = 別 session の WIP / 手動 stage / 副作用 artifact なので blocking

`--amend` も対象に含める。共有 index 構成では `git commit --amend` が他 session の staged file を最も巻き込む経路 (実事故: 別 Terminal の staged file が amend で commit に混入し origin/main へ push)。message-only amend (index が clean) は staged file が空なので素通しになり over-block しない。transcript path が取れない環境では fail-open (= 素通し + warning) で AI の有用性を優先する。

スクリプト: [`block-cross-claude-wip.sh`](./block-cross-claude-wip.sh)

### Hook F — protected branch への直接 push を block (opt-in)

`.bootstrap-protected` (repo root、1 行 1 branch glob) を置いた project だけ発火する。`git push` の refspec destination、または refspec 無し push の現在 branch が宣言 glob に一致すると `exit 2`。**`.bootstrap-protected` が無ければ素通し** (= solo / 個人 repo は妨げない。`.bootstrap-lane` / `.bootstrap-arch` と同じ opt-in 思想)。

並走 session が作った混入 commit が共有 branch に lock-in する事故 (実事故: 別 Terminal の staged file 混入 commit が origin/main へ push された) を defense-in-depth で塞ぎ、sprint flow の「task = feature branch → 統合は integrate skill (PR / merge)」を default 化する。例外的に直接 push したいなら `/permissions` で一時 deny。

スクリプト: [`block-push-to-protected.sh`](./block-push-to-protected.sh)

### H. PreToolUse on `Bash` — commit 時の依存方向検証 (staged のみ)

`git commit` 直前に、`.bootstrap-arch` で宣言された依存方向違反を **staged file の中から検出**し、あれば `exit 2` で blocking。staged のみ検査するので (= 正しい pre-commit セマンティクス)、既存 debt のあるリポでも adopt でき、新規/変更分の違反だけ捕まえる (全 repo 網羅 scan は CI の領分)。edit 時の早期 gate は Hook I。`.bootstrap-arch` 不在なら fail-open。エンジンは [`lib/arch-check.sh`](./lib/arch-check.sh) を共有。

スクリプト: [`block-arch-violations.sh`](./block-arch-violations.sh)

### L. SessionStart — 採用状態の audit (可視化 net)

session を開いた瞬間に `scripts/doctor.sh` で project-bootstrap の採用状態を判定し、**actionable な状態のときだけ** context に注入する。規律 gate は消費先 repo でその hook が現行版で走って初めて効くが、「採用したのに gate が届いていない (partial)」「採用も提案もされない (unadopted)」状態は無音で成立し誰も気づけなかった (実事故: [`docs/incidents/2026-06-02-coverage-drift-silent/`](../docs/incidents/2026-06-02-coverage-drift-silent/README.md))。とりわけ sprint 発火 gate は build 前の判断で CI 後追いができず PreToolUse hook 以外に backstop を持てない (ADR 0002) ため、配備漏れが致命的になる。

- **強制ではない** (advisory)。採用は consent 必須なので hook で強制できない。enforcement の本体は per-action gate。本 hook は状態を**可視化する**だけ
- **unadopted** → 導入するかを user に一度だけ尋ねる (勝手に採用ファイルを作らない)。望まなければ `.bootstrap-declined` を置いて以後黙る
- **partial** → 整合しない点を警告。中核は **vendored-coverage gap** (= `.claude/hooks/` で vendoring しているのに採用機能に必要な hook が物理的に欠落 = 宣言したのに gate が不在)
- **ok / declined / 非 git** → 無音 (= advisory bloat を増やさない)
- 射程の穴: 本 hook は **plugin が在る session でしか発火しない**。plugin を入れず vendored hook だけの repo は救えない → その穴は CI template (`templates/ci/bootstrap-doctor.yml`) が plugin 非依存で塞ぐ。doctor は両者で共有する単一エンジン

スクリプト: [`bootstrap-session-doctor.sh`](./bootstrap-session-doctor.sh) / エンジン: [`scripts/doctor.sh`](../scripts/doctor.sh)

## 発火順

**SessionStart**:

1. `bootstrap-session-doctor.sh` — 採用状態を audit し unadopted/partial のとき可視化

**PreToolUse on `Edit | Write | MultiEdit`**:

1. `block-out-of-lane-edit.sh`         — 並列 lane 外編集を block
2. `block-unplanned-feature-build.sh`  — 新規 source 面を sprint 判定なしで作るのを block (opt-in)
3. `block-cross-layer-import.sh`       — 依存方向違反 import を早期 block
4. `require-test-companion.sh`         — 対応 test なき実装編集を block

**PreToolUse on `Bash`**:

1. `block-add-all.sh`               — 個別 add に矯正
2. `block-dangerous-git-ops.sh`     — 他人の作業を消す op を block
3. `block-cross-claude-wip.sh`      — commit 直前に巻き込み check (`--amend` 含む)
4. `block-push-to-protected.sh`     — 宣言 branch への直接 push を block (opt-in)
5. `block-arch-violations.sh`       — commit 時に依存方向を権威検証
6. `block-commit-if-lint-fails.sh`  — commit 時に lint を回す
7. `block-commit-if-tests-fail.sh`  — 最後に test を回す

block 系を test 実行より前に置くのは、test 実行が成功しても巻き込んだ commit / 契約違反は事故源だから。

## bypass

特殊事情で hook を一時的に無効化したい場合:

- 個別ツール: Claude Code 内で `/permissions` から該当 hook を deny に変える
- 全体: `.claude/settings.json` で hook を override

bypass は **規律を壊す**。bypass する前に「なぜそれが必要なのか」を 1 文で説明できるか確認する。説明できないなら bypass せず別経路を選ぶ (= 個別 add に書き換える / `--force-with-lease` に変える / 等)。

## 公式 docs

[Claude Code Hooks](https://code.claude.com/docs/en/hooks) / [Plugin reference - Hooks](https://code.claude.com/docs/en/plugins-reference#hooks) / [Best Practices](https://code.claude.com/docs/en/best-practices)

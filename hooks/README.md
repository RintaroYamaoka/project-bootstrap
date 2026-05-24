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

### J. PreToolUse on `Bash` — failing lint での commit を禁止

`git commit` 直前に project の lint command を実行し、fail なら `exit 2`。「綺麗なコード」のうち **linter が見る deterministic な層** (命名規約 / format / 未使用 / 複雑度しきい値) だけを強制する。命名の質・設計のセンスといった taste は対象外 (= 人間レビュー / `code-review` skill の領分)。プラグインが綺麗さを判断せず project の linter に委ねる。

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

### H. PreToolUse on `Bash` — commit 時の依存方向の権威検証

`git commit` 直前に、`.bootstrap-arch` で宣言された layer 配下の **tracked file を全部検証**し、依存方向違反があれば `exit 2` で blocking。edit 時の早期 gate (Hook I) が取りこぼしても、ここで「どの commit も契約を満たす」ことを保証する。`.bootstrap-arch` 不在なら fail-open。エンジンは [`lib/arch-check.sh`](./lib/arch-check.sh) を共有。

スクリプト: [`block-arch-violations.sh`](./block-arch-violations.sh)

## 発火順

**PreToolUse on `Edit | Write | MultiEdit`**:

1. `block-out-of-lane-edit.sh`      — 並列 lane 外編集を block
2. `block-cross-layer-import.sh`    — 依存方向違反 import を早期 block
3. `require-test-companion.sh`      — 対応 test なき実装編集を block

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

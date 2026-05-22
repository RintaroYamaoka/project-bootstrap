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

`--amend` は対象外 (= 既存 commit 修正は別議論)。transcript path が取れない環境では fail-open (= 素通し + warning) で AI の有用性を優先する。

スクリプト: [`block-cross-claude-wip.sh`](./block-cross-claude-wip.sh)

## 発火順 (PreToolUse on Bash)

1. `block-add-all.sh`               — 個別 add に矯正
2. `block-dangerous-git-ops.sh`     — 他人の作業を消す op を block
3. `block-cross-claude-wip.sh`      — commit 直前に巻き込み check
4. `block-commit-if-tests-fail.sh`  — 最後に test を回す

block 系を test 実行より前に置くのは、test 実行が成功しても巻き込んだ commit は事故源だから。

## bypass

特殊事情で hook を一時的に無効化したい場合:

- 個別ツール: Claude Code 内で `/permissions` から該当 hook を deny に変える
- 全体: `.claude/settings.json` で hook を override

bypass は **規律を壊す**。bypass する前に「なぜそれが必要なのか」を 1 文で説明できるか確認する。説明できないなら bypass せず別経路を選ぶ (= 個別 add に書き換える / `--force-with-lease` に変える / 等)。

## 公式 docs

[Claude Code Hooks](https://code.claude.com/docs/en/hooks) / [Plugin reference - Hooks](https://code.claude.com/docs/en/plugins-reference#hooks) / [Best Practices](https://code.claude.com/docs/en/best-practices)

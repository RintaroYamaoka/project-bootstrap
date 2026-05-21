# hooks/

`project-bootstrap` の規律を **deterministic に強制する hook 集**。`plugin.json` の `hooks` フィールド経由でデフォルト発火する (= ユーザーが叩かなくても常に動く)。

## 提供する hook

### A. PreToolUse on `Edit | Write | MultiEdit` — テスト先行強制

実装ファイルを編集しようとした瞬間、対応 test ファイルが無ければ `exit 2` で **blocking**。これで「テスト書かずに実装」が default で構造的に不可能になる (Red phase 強制)。

- 実装ファイル: `.ts/.tsx/.js/.jsx/.mjs/.cjs/.py/.go/.rs/.rb/.php/.java/.cs/.cpp/.c/.swift/.kt/.scala/.ex/.exs/.clj/.hs/.ml`
- test ファイル自身 / markdown / config / settings は素通し
- **`scripts/_*` も素通し** — `scripts/_foo.mjs` のような prefix `_` 付きは ephemeral debug / one-shot recovery script の慣行 namespace。test companion を要求するのは過剰なので除外する
- 対応 test の検出は慣例パターン (`foo.test.ts` / `foo.spec.ts` / `foo_test.go` / `test_foo.py` / `spec/foo_spec.rb` / `tests/` 配下 / `__tests__/` 配下) を順次探索
- `tests/` の深い階層 (例: `tests/unit/<layer>/foo.test.ts`) も再帰的に検索する。直下に置かないリポジトリ構造 (= `tests/unit/<source mirror>/<name>.test.<ext>`) でも red test 済みなら素通し

#### Windows path 対応

Claude Code は Windows 環境で `\` 区切り絶対 path を JSON-escape 済 (= literal `\\`) で渡してくる。hook 内で `tr` 経路により forward slash に正規化してから case パターン判定するので、Windows / POSIX どちらでも同じ skip ルールが効く。`sed -e 's|\\|/|g'` は Git Bash の GNU sed で「unterminated `s' command」を吐いて使えないため `tr '\\\\' '/' | tr -s '/'` を採用 (= 0.4.1 で修正)。

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

## bypass

特殊事情で hook を一時的に無効化したい場合:

- 個別ツール: Claude Code 内で `/permissions` から該当 hook を deny に変える
- 全体: `.claude/settings.json` で hook を override

ただし bypass は **規律を壊す**。bypass する前に「なぜテストを書けないのか」を 1 文で説明できるか確認する。説明できないなら bypass せずテストを書く。

## 公式 docs

[Claude Code Hooks](https://code.claude.com/docs/en/hooks) / [Plugin reference - Hooks](https://code.claude.com/docs/en/plugins-reference#hooks)

# hooks/

`project-bootstrap` の規律を **deterministic に強制する hook 集**。`plugin.json` の `hooks` フィールド経由でデフォルト発火する (= ユーザーが叩かなくても常に動く)。

> **opt-in マーカーの所在**: project が置く opt-in マーカー (arch / protected / lint / wip / actions / lane) は repo root の **`.bootstrap/` フォルダ配下** (`.bootstrap/arch` 等) に集約する。解決は単一権威 [`lib/resolve-marker.sh`](./lib/resolve-marker.sh) が担い、`.bootstrap/<name>` (新) を優先し旧 flat path `.bootstrap-<name>` に後方互換で fallback する (両方在れば新が勝つ)。以下の説明で `.bootstrap-xxx` と書かれた箇所は新 `.bootstrap/xxx` と読み替え可。

> **git コマンド検出の単一権威 (ADR 0019)**: 「このコマンドは `git <subcommand>` を呼ぶか」は全 Bash gate (commit 系 5 本 / push 2 本 / merge 2 本 / add-all) が [`lib/git-invocation.sh`](./lib/git-invocation.sh) の `cmd_invokes_git_subcommand` / `git_subcommand_arglines` で判定する。旧 regex は path-prefixed git (`/usr/bin/git commit`) と **git グローバルオプション形** (`git -C /repo push` / `git -c k=v commit` / `git --git-dir=.git push` / `git -P push`) をすべて素通りさせていた (2026-07-10 監査で実測)。walker は shell separator を pad して tokenize し、グローバルオプション (値を取るものは次トークンごと) をスキップして最初の非オプショントークンを subcommand として読む。未知の `-*` オプションは検出側 (fail-closed) に倒す。同様に、hook 入力 JSON の string field 抽出 (`command` / `file_path` / `cwd` / `transcript_path`) は [`lib/parse-command.sh`](./lib/parse-command.sh) の `parse_json_string_field` が単一権威 (旧式 `grep -oE '"key"[^,}]*'` は path 中の `,` `}` / escape で途中切り → 無音 fail-open だった)。

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
- **worktree 外の絶対 path の扱いは根拠の有無で分岐する** (fail-mode の修正、marketing-app 2026-07-09 incident M5): その path が **同一 repo の別 worktree** (典型的にはメインリポ) の中に在るなら、定義上「この lane の外」だと**確定できる**ので `exit 2` で block し、両 worktree root を message に名指しする (= 解析不能でなく解析済みの違反 → fail-closed)。どの worktree にも属さない path (`/tmp` scratchpad / `~/.claude` 等) は判断材料が無いので従来どおり fail-open (= 根拠不在 → fail-open)。かつては前者も一律 fail-open で、lane worker がメインリポの file を絶対 path で直接書く事故が素通っていた
- glob 照合と別 worktree 判定は共有エンジン [`lib/lane-match.sh`](./lib/lane-match.sh) に集約 (= commit 関所と単一権威。両 gate が別々に glob を解釈して片方だけ緩い穴になるのを防ぐ。`detect-test-suite.sh` を test/merge 両関所で共有するのと同じ思想)
- jq 非依存。hook が読むのは worktree-local な `.bootstrap-lane` だけ (= board.json の rich な真実は lead / skill が読み書きする)

スクリプト: [`block-out-of-lane-edit.sh`](./block-out-of-lane-edit.sh) / エンジン: [`lib/lane-match.sh`](./lib/lane-match.sh)

### T. PreToolUse on `Bash` for `git commit` — 並列 lane 強制の commit 側関所 (取りこぼしの網)

lane 強制は長らく `Edit | Write | MultiEdit` matcher の Hook G にしか載っておらず、**Bash 経由の書き込みは関所を一度も通らなかった** — `biome format --write` / `prettier --write` / `sed -i` / codemod / `python` / `>` redirect などは編集時 hook を素通りする。書き込み方式 (`--write`, `-i`, リダイレクト …) を列挙して塞ぐのは whack-a-mole で新方式が出るたび穴が空くので、**全ての書き込み方式が必ず通る一点 = `git commit`** に関所を置く。編集時 Hook G は速い feedback のため残し、本 hook を取りこぼしの網とする**二層構成**。lane worktree で commit するとき、その commit に載る file が全て lane glob の中であることを要求し、外れる file が 1 つでもあれば `exit 2`。根拠 = marketing-app 2026-07-09 incident M5 (`ui-leaf-producer-unwired`、L2 が `biome format --write` で lane 外の file を書き換えどの hook も鳴らなかった)。

- **判定対象**: `git diff --cached --name-only` (index に載る file)。`git commit -a` / `-am` / `--all` のときは tracked の未 stage 変更 (`git diff --name-only`) もその場で stage されるので併せて対象にする
- lane 照合は Hook G と共有エンジン [`lib/lane-match.sh`](./lib/lane-match.sh) に委ねる (= 単一権威。編集時と commit 時で glob 解釈が drift しない)
- **fail-open (根拠不在)**: lane marker 不在 (= sprint 非適用の通常作業は妨げない) / 非 `git commit` / 非 git / **index が空** (= git 自身が拒否する。判断材料が無い) / **統合操作中** (`MERGE_HEAD` / `CHERRY_PICK_HEAD` / `REVERT_HEAD` / rebase-merge / rebase-apply — lead の conflict 解決は定義上 lane を跨ぐので通す)
- **fail-closed (解析不能)**: hook 入力からコマンドを parse できない ([`lib/parse-command.sh`](./lib/parse-command.sh) の契約) → 他の commit 関所と同じく `exit 2`

スクリプト: [`block-out-of-lane-commit.sh`](./block-out-of-lane-commit.sh) / エンジン: [`lib/lane-match.sh`](./lib/lane-match.sh) ・ [`lib/commit-files.sh`](./lib/commit-files.sh) (`commit_files_from_cmd` = 「この commit が運ぶ file」の単一権威。lint 関所 Hook J と共有し `-a`/`--all` の扱いが drift しない、ADR 0018)

### K. PreToolUse on `Edit | Write | MultiEdit` — sprint 発火判定を fail-closed 強制

**新規 source file を作ろうとした瞬間**、sprint 自動分解の発火判定が記録されていなければ `exit 2` で blocking。かつて sprint 発火は `sprint-trigger-reminder.sh` (UserPromptSubmit) の **advisory** だけで担保され、判定も実行もモデル任せだった (= 長い会話で忘れられ一度も発火しない実事故あり: [`docs/incidents/2026-05-31-sprint-advisory-silent/`](../docs/incidents/2026-05-31-sprint-advisory-silent/README.md))。本 hook は TDD/lane/arch と同型に、その判定を precondition として強制する。

- **信号は prompt の語彙ではなく「新規 source file を作る行為そのもの」**。語彙 regex は proxy で自然言語の言い回しに穴があったが、行為信号は言い方に依存しない
- hook は **sprint を起動しない** (worktree 起動=人間 / disjoint 判定=モデル。ADR 0001 の既約な残余)。「gate 判定を済ませた」ことだけを強制する
- **opt-in**: `docs/sprint/` が在る project でのみ発火 (= `.bootstrap-arch`/`-lane`/`-protected` と同じ採用宣言)。無ければ fail-open
- **fail-open (根拠不在)**: file_path 不在 / 非 git / 既存 file の編集・上書き / test・config・doc / 非 source 拡張子 / `scripts/_*`。bug fix / refactor は一切 trip しない
- gate を通す記録 = `docs/sprint/.gate` (gitignore, ephemeral)。各行 `<scope-glob>  <YYYY-MM-DD>  <理由>`。entry が判定の証拠になるのは **時間** (日付が 3 日以内 = [`lib/gate-entry.sh`](./lib/gate-entry.sh) の `GATE_TTL_DAYS`) と **空間** (feature-scoped な glob = exact path か wildcard 前に 2 階層以上の prefix) の両方で bound されているときだけ — 無期限・無界に信じると消費先の `src/**` 1 行が source tree 全域の gate を恒久 fail-open にする (実事故: `docs/incidents/2026-06-11-gate-broad-glob-permanent-fail-open`)。日付なし旧形式 / 失効 / 全域 glob の entry は不採用とし、block message に列挙する (= 正データを隠させない)。記録 scope 内の新規 source は素通し、scope 外は再 block (= 新しい disjoint 面 → 再判定)。進行中 sprint なら lane hook が scope を握るので素通し — 「進行中」は board.json の**存在ではなく活性** (= `status` ≠ `done` の task の有無) で判定する。完了済み board の残置 (stale) が gate を無音バイパスさせた実事故があり (`docs/incidents/2026-06-07-stale-board-gate-bypass`)、全 done / task 無し / status 不在の board は素通しの根拠にしない (= 解析不能を素通し側に倒さない)
- checklist の `wip_limit` 表示は repo root の **`.bootstrap-wip`** (整数 1 行、opt-in) を読んで実値化する (エンジン = [`lib/resolve-wip-limit.sh`](./lib/resolve-wip-limit.sh)、`sprint-trigger-reminder.sh` と共有)。不在・解析不能なら form-aware な既定 (worker 3-4・Workflow lane は wip 非対象、ADR 0006) に fail-open (= 表示であって blocking 信号ではない。解析不能の可視化は `scripts/doctor.sh` が担う)。board.json の `wip_limit` を読まないのは、board が per-sprint の ephemeral state で逸脱値 (`_wip_note`) を含み、sprint 終了後に stale になるため

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

**信号は「この commit が運ぶ file」であってツリー全体ではない (ADR 0018)**。従来はツリー全体を lint していたが、git worktree には repo の全 tracked file が複製されるので、lane worker が **自分の所有しない file の lint debt** で commit を止められ、lane の中に正当な remedy が無く lane を出る動機を gate 自身が作っていた (marketing-app 2026-07-09 incident M5)。今は `git diff --cached --name-only` (+ `-a`/`--all` 時は tracked の未 stage 変更) が返す file だけを lint する。判定対象そのもの (= この commit) を信号にする ([`feedback_gate_signal_and_failmode`](../docs/decisions/0018-lint-gate-signal-is-the-commit-not-the-tree.md) の「gate は判定対象そのものを信号にする」)。

- **削除された file・その linter が扱う拡張子でない file は渡さない** (存在しない path / 非対象拡張子を渡すと linter 自身がエラーを出して誤 block になる)。commit がこの linter の扱う file を 1 つも運ばないなら判定対象が無いので**素通し**
- **既知の path 対応 tool だけを scope する (allowlist)**。`npm run lint` は script 文字列から tool を同定し、**`eslint` / `biome` / `oxlint` / `prettier` のときだけ** file 引数つきで呼ぶ。`next lint` のように file 引数で意味が変わる script は同定せず **whole-tree に落とす** — 誤って scope すると**存在しない lint 失敗を発明して誤 block する**ため。tool の解決は `node_modules/.bin/<tool>` を優先し (npx のネットワーク取得・版ずれを避ける)、解決できなければ whole-tree に落とす
- **file 引数を取れない linter は whole-tree のまま fail-closed で残す** (`golangci-lint run` / `cargo clippy` は package 単位で file を絞れない)。**緩めない** — 従来どおりツリー全体を検査して block するが、失敗が **自分の lane の外** の file 由来なら「それを直しに lane を出るな (= 越境編集は Hook G/T が block する)、lead に上げろ」と message で明示する (案内と強制を一致させる)
- **代償 (正直に明示)**: 既存のツリー debt はそれを触らない commit を止めなくなり、cross-file な lint 規則 (未使用 export の検出など) は commit 単位では scope できない。ツリー全体の清潔さは **CI の whole-tree lint** が backstop

| マーカー | 実行 command (runner が PATH にある場合のみ) |
|---|---|
| `package.json` (`"lint"` script あり) | `npm run lint --silent` (path 対応 tool なら commit の file に絞る) |
| `pyproject.toml` / `.ruff.toml` / `.flake8` | `ruff check .` or `flake8` (commit の file に絞る) |
| `go.mod` | `golangci-lint run` (whole-tree、file 引数不可) |
| `Cargo.toml` | `cargo clippy -- -D warnings` (whole-tree、file 引数不可) |
| `Gemfile` | `rubocop` (commit の file に絞る) |

linter が解決できない (script 無し / runner 不在) 場合は warn して素通し。**全分岐に `command -v` ガード**があり、toolchain 不在マシンで誤 block しない。

スクリプト: [`block-commit-if-lint-fails.sh`](./block-commit-if-lint-fails.sh) / エンジン: [`lib/lint-scope.sh`](./lib/lint-scope.sh) (tool 同定 `lint_script_tool` / scope base `lint_scoped_base` / 拡張子判定 `lint_ext_ok`) ・ [`lib/commit-files.sh`](./lib/commit-files.sh) (`commit_files_from_cmd` = 「この commit が運ぶ file」の単一権威、Hook T と共有)

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

判定は segment 単位の token walk ([`lib/git-invocation.sh`](./lib/git-invocation.sh) の `git_subcommand_arglines`、ADR 0019)。旧実装は stash 判定に greedy sed が残っていて compound command の最後の segment しか見ず (`git stash && echo done` の bare stash が素通り)、検出 regex も path-prefixed git / グローバルオプション形を見逃していた。

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

- **`git push --all` / `--branches` / `--mirror` は fail-closed** (ADR 0019): これらは refspec を持たず destination はコマンド文字列から列挙できない (= 全 local branch)。gate が `git for-each-ref refs/heads/` で展開し、1 つでも protected な branch があれば block する。旧実装は current-branch 判定に落ち、feature branch 上からの `git push --all origin` が保護 main を素通りさせていた (2026-07-10 監査で実測)
- push 検出・refspec destination 列挙・`--all` 判定は [`lib/protected-branch.sh`](./lib/protected-branch.sh) (`cmd_has_git_push` / `push_destination_branches` / `push_pushes_all_branches`) — freshness gate (Hook R) と共有の単一権威

スクリプト: [`block-push-to-protected.sh`](./block-push-to-protected.sh)

### R. PreToolUse on `Bash` — stale な checkout からの trunk push を freshness gate で block

`git push` の destination が **trunk** (= [`lib/repo-drift.sh`](./lib/repo-drift.sh) の `drift_main_ref` が解決する `origin/main` → `main` 等) に一致するときだけ、timeout 付き fetch を**先に**行ってから `HEAD..<remote>/<branch>` の behind 数を測り、**behind > 0 なら `exit 2`**。stale-checkout class の本番化事故が 2 件続いた (`origin/main` より 24 commit 遅れた checkout から prod migration / 進んだ remote を取りこぼす整合化) のを、コメント止まりだった drift advisory から **enforceable な precondition** に昇格させる (ADR 0009)。

- **Hook F (`block-push-to-protected`) と直交**。あちらは opt-in `.bootstrap-protected` で **PR-flow** を強制し宣言 branch への直接 push を outright で block する (freshness 無関係)。本 gate は **otherwise-allowed な trunk push の freshness** を強制する。信号は `drift_main_ref` が解決する trunk であって `.bootstrap-protected` membership ではない (= `.bootstrap-protected` を持たない本プラグイン自身の release flow でも効く)
- **順序**: Hook F の**後**に走る。trunk を保護している repo では直 push はそちらで既に止まり、本 gate はあちらが意図的に許す「`.bootstrap-protected` 無しの直接 trunk push」を freshness で守る net
- **fail-closed (安全側)**: コマンド解析不能 ([`lib/parse-command.sh`](./lib/parse-command.sh) の契約) → BLOCKING gate が入力を読めないなら push を通さない
- **fail-open (根拠不在)**: 非 git push / git も work-tree も無い / trunk ref 解決不能 / destination が trunk でない / **fetch 失敗・timeout (offline / no remote / auth fail)** / behind == 0 — block しかけたときだけ stderr で announce し無音 no-op にしない。network 不通が work を止めることは絶対にあってはならない
- 唯一 **fetch (network) を行う PreToolUse gate**。`timeout` で bound し失敗を fail-open にする。push 引数の列挙・force・refspec 無し (暗黙 current branch) は [`lib/protected-branch.sh`](./lib/protected-branch.sh) を Hook F と共有。staleness 判定は online (`fetched_behind_count`) / offline (`behind_count`、SessionStart doctor 用) を `repo-drift.sh` の**隣り合う関数**にして単一権威に保つ (= gate 信号の drift を防ぐ)

スクリプト: [`block-stale-write-to-protected.sh`](./block-stale-write-to-protected.sh)

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

### M. PreToolUse on `Bash` for `git merge` — AI レビューを統合の precondition に強制

並列フローの throughput 天井は「人間が全 diff を直列レビューする」ことに在る (sprint-plan/SKILL.md が明文化。しかも user のレビュー帯域は複数プロジェクト共有の単一資源)。trust ladder の Stage 2 として一次レビューを read-only の adversarial AI レビュー (integrate skill Step 2) に移すが、「レビューを済ませた」を advisory にすると忘れられる — 本 hook は**並列 lane の branch を `git merge` する行為そのもの**を信号に、レビュー記録の存在と verdict を fail-closed で要求する。lane = 活性 board の task branch ∪ **linked worktree に checkout された branch** (= board を作らない Workflow / 手動 worktree 並走でも捕まる。関所を方式に結合すると方式の選択で gate が無音になる — `docs/incidents/2026-06-11-parallel-mode-gate-coverage`、ADR 0004)。GitHub PR 画面の merge は手元 hook を通らないため、PR 経路は `templates/ci/bootstrap-review-gate.yml` が CI で同じ記録を要求する。TDD hook が test の存在を強制するのと同型 (= レビューの「質」は強制できないが「存在と結論」は強制できる)。

- precondition = `docs/sprint/reviews/<branch の `/`→`_`>.md` が存在し `verdict: approve` 行を持つ
- **`verdict: reject` はより強く block** (= 却下されたレビューを踏み越える merge を許さない。対処は修正 → re-review、記録の削除ではない)
- **fail-closed**: コマンド解析不能 ([`lib/parse-command.sh`](./lib/parse-command.sh) の契約)
- **fail-open (根拠不在)**: 非 merge / 非 git / docs/sprint 未採用 (opt-in) / merge 対象が lane branch でない (= worktree にも活性 board にも居ない通常 branch の merge を一切妨げない。board の活性判定は [`lib/board-liveness.sh`](./lib/board-liveness.sh) — 存在でなく活性)
- レビューの質の安全網は gate ではなく `scripts/velocity.sh` の defect rate 監視 (跳ねたらレビューを 1 段厚く戻す)
- lane 集合 (活性 board ∪ linked worktree) の組み立ては [`lib/lane-set.sh`](./lib/lane-set.sh) — verification gate (Hook N) と共有の単一権威 (verbatim 重複していた ~40 行を抽出)

スクリプト: [`block-unreviewed-merge.sh`](./block-unreviewed-merge.sh)

### N. PreToolUse on `Bash` for `git merge` — verification plan を統合の precondition に強制

コードレベルのバグは TDD hook + レビューで潰れたが、残余の事故は**継ぎ目 (cross-repo 契約 / 要件 / 「実物を見ずの完了」/ 環境)** に移動した — repo 内 unit test の射程外で、緑のテストが誤った契約を固定して false confidence を配る (mood incident: zod `min(1)` の test が緑のまま全予約 reject、ADR 0007)。本 hook は review gate と同じ lane 信号 (活性 board task branch ∪ linked worktree branch) を使い、**lane branch を `git merge` する行為**を信号に、その branch の verification plan が閉じていることを fail-closed で要求する。フォーマット権威は [`lib/verification-plan.sh`](./lib/verification-plan.sh) に集約 (gate/doctor/skill 共有 = drift 防止)。

さらに **cross-repo 契約拡張** (ADR 0011): 既存 plan check の後、lane の OWN delta (`base..lane` を offline 計算) が `docs/verification/contracts` の登記面 (`local_face_glob`) を触ったら、その契約に対し **`[contract:<id>]` タグつきの CLOSED plan 行** + **consumer 側スイートの関所自身による実走 (緑)** を追加で要求する (どちらも無ければ block)。登記の parse と lane delta の計算は単一権威 [`lib/cross-repo-contract.sh`](./lib/cross-repo-contract.sh) に集約 (gate/doctor 共有 = drift 防止)。gate は相手 repo を読まない (consumer 側のみ)、自動で回せない契約は plan 行を `STATUS=HUMAN` にして人間の実出力照合まで OPEN のままにする (free-text PASS では touched 契約を閉じさせない)。

- precondition = `docs/verification/<branch の `/`→`_`>.md` が存在し、データ行を 1 つ以上持ち、OPEN 行 (TODO/FAIL/HUMAN) がゼロ、理由なき DROP がゼロ
- **cross-repo 契約 (ADR 0011)**: lane delta が登記面を触ったら、その契約 id を CLOSED にした `[contract:<id>]` 行 AND consumer スイートの実走 (緑) も追加 precondition。無ければ block
- **plan 不在は fail-open に逃さず block** (= 「計画を書かない」で gate を素通りさせない。ADR 0002 の教訓)
- **fail-closed**: コマンド解析不能 / 採用済み lane branch の plan 不在・空・OPEN 行残存・理由なき DROP
- **fail-open (根拠不在)**: 非 merge / 非 git / `docs/verification/` 未採用 (opt-in) / merge 対象が lane branch でない
- 射程の境界: 統合 (merge) を信号にするので branch を切らない逐次作業は捕まえない (そこは `verification` skill が plan 時に担う)。kill-question「緑のままユーザーが困る状態はあるか?」は skill 側の doctrine
- GitHub PR 画面の merge は手元 hook を通らないため、PR 経路は `templates/ci/bootstrap-verification-gate.yml` が CI で同じ計画を要求する (review gate と同型)
- lane 集合の組み立ては [`lib/lane-set.sh`](./lib/lane-set.sh) — review gate (Hook M) と共有の単一権威

スクリプト: [`block-merge-if-verification-unclosed.sh`](./block-merge-if-verification-unclosed.sh)

### O. PreToolUse on `Edit | Write | MultiEdit` — mutation lane の worktree 隔離強制 (ADR 0005 guard 2)

並列開発では各 lane は隔離 worktree で mutate する (ADR 0004/0005)。だが `block-out-of-lane-edit.sh` は `.bootstrap-lane` を持つ worktree の中でしか効かず、共有 main worktree で source を mutate する行為は素通しだった (= Workflow / subagent が隔離 worktree を使わず shared tree に書く collision に穴)。本 hook がそれを塞ぐ。

**誤検知 > false negative** の方針で、全条件が揃ったときだけ `exit 2`:

- (a) `docs/sprint/` 採用 (opt-in)
- (b) **main worktree に居る** (lane worktree は `block-out-of-lane-edit.sh` が所有 → 譲る)
- (c) **active な linked worktree lane が在る** (= 並列 mutation が物理的に存在)
- (d) **統合操作中でない** (`MERGE_HEAD` / rebase / cherry-pick / revert — lead の conflict 解決は通す)
- (e) 編集対象が **source 面** (docs / config / test / sprint state は通す。[`lib/source-face.sh`](./lib/source-face.sh) で判定)

どれか曖昧なら fail-open。jq 非依存。

スクリプト: [`block-uniso-main-edit.sh`](./block-uniso-main-edit.sh)

### P. PreToolUse on `Bash` for `git worktree add` — WIP 上限の fail-closed 強制 (ADR 0005 guard 3)

`.bootstrap-wip` はこれまで [`lib/resolve-wip-limit.sh`](./lib/resolve-wip-limit.sh) が checklist に**表示**するだけの値で、並列度が超えても何も block しなかった (= 強制なき宣言)。scrum の本質は WIP 制限であり、review 帯域 (= 複数 repo 共有の単一資源) を守るには lane を開く数そのものを縛る必要がある。本 hook は「並列 lane を 1 本開く行為」= `git worktree add` を信号に、既存 linked worktree が宣言 `wip_limit` に達していれば `exit 2`。

- **限界 (ADR 0005)**: hook は Workflow 内部の isolation worktree 生成を観測できない (main session の Bash tool 呼び出しではないため)。縛るのは観測可能な `git worktree add` (skill / 人間 / lead が開く lane)。Workflow 内部 lane の暴走は統合の入口 (`block-unreviewed-merge.sh`: 各 lane に review 記録 + 実スイート) が review 帯域を守る最終 net
- **fail-closed**: コマンド解析不能 ([`lib/parse-command.sh`](./lib/parse-command.sh) の契約)
- **fail-open (根拠不在)**: 非 worktree-add / 非 git / `docs/sprint/` 未採用 (opt-in) / `.bootstrap-wip` 未宣言 or 整数として解析不能 (= 宣言した repo でだけ縛る)

スクリプト: [`block-over-wip-parallel.sh`](./block-over-wip-parallel.sh)

### Q. UserPromptSubmit — sprint 発火判定の早期ヒント (advisory)

sprint 自動分解は SKILL.md の **advisory** (= Claude が探索結果から自分で判定して `sprint-plan` をロードする設計) だが、context から SKILL が抜ける / 長い会話で忘れられると判定そのものが走らず「全然起動しない」になる — プラグイン自身が他所で否定している「advisory は忘れられる」失敗モードそのもの。本 hook は feature 実装っぽい user prompt のときだけ、sprint 発火判定の **3 条件 checklist を毎ターン context に注入**して「判定し忘れ」を防ぐ。

- **強制本体ではない**。sprint を hook で起動はできない (worktree 起動=人間、最終判定=Claude)。強制は `block-unplanned-feature-build.sh` (= 新規 source 面を作る行為を信号に fail-closed) が担う。本 hook は早期ヒント
- 非該当 prompt では**無音** (ノイズを増やさない)。over-trigger しても reminder 1 つで安く、3 条件 gate が bug fix / 単一 file を弾くので害にならない (= false negative より false positive を許す設計)。**語彙 regex の取りこぼしはもう致命的でない** (= 行為信号の gate が最終的に必ず捕まえる)

スクリプト: [`sprint-trigger-reminder.sh`](./sprint-trigger-reminder.sh)

### S. PreToolUse on `Bash` — 再発しやすい action 直前に記録済み memory を注入 (block しない)

Bash command が plugin 所有の **action-key enum** ([`lib/action-gate.sh`](./lib/action-gate.sh) の `ACTION_KEY_ENUM` = 現状 `prod-deploy` / `prod-db-migrate`) に共有トークナイザでマッチし、かつ opt-in registry `.bootstrap/actions` (旧 `.bootstrap-actions` 互換、雛形 [`templates/.bootstrap/actions.example`](../templates/.bootstrap/actions.example)) が当該キーを **arm** していれば、対応する memory を `hookSpecificOutput.additionalContext` (= `bootstrap-session-doctor.sh` と同形) として出して **exit 0**。memory に正しい fix が記録されていても効くのは「次の session 開始時に読む」ときだけで、操作を打つ瞬間には目の前に無い — その空白で deploy author 渡し忘れ型の bug が fix 記録済みのまま ~7 回再発した。本 hook は「記録したのに想起されない」を**操作の瞬間の visibility** で埋める (ADR 0010)。

- **決して `exit 2` しない / ack も取らない**。理解は強制不能で (ADR 0001)、ここで課せる前進行為が無い (deploy 自体は正当、fix を**忘れている**だけ)。必要なのは block ではなく想起のタイミング = 「強制を 4 設計判断に作り替える」②(信号選び) の **visibility 版**
- **controlled-vocabulary なマッチャ** (per-entry regex でない)。マッチ条件は共有 plugin code (`action-gate.sh` のトークナイザ + CLOSED な enum) に集約し、消費先は **enum からキーを選んで arm するだけ**。`merge-targets.sh` / `protected-branch.sh` と同じ正規化 (env-prefix 除去 / path-prefixed bin / `npx` / `bash -c` unwrap / compound walk) を踏み、消費先のインライン正規表現による未レビュー greedy-match / string-proxy 事故を構造的に締め出す
- **全面 fail-open / silent**。何も block しないので fail-closed にすべき不安全側が存在しない: パース失敗 / トークナイズ mis-split (quote 内 separator の既知限界) / enum キー未一致 / registry 不在 / 当該キー未 arm — すべて exit 0 silent (= 採用していない repo は一切撹乱されない)
- **TTL は SAFE-side**。armed entry に self-disarm な期限を付けない (= 最も再発を抑えたい古い arm が無音で死ぬのを禁止)。終端所有者は人間で、`scripts/doctor.sh` の `actions:` 行が orphan (enum に無いキーの arm) / arm 漏れ (`repeat-action` タグの incident が在るのに registry 不在) を surface する (status は flip しない)

スクリプト: [`inject-action-memory.sh`](./inject-action-memory.sh)

## 発火順

全 20 hook を `hooks.json` の結線順に列挙する (= 実際の発火順、可視化のための正本)。

**SessionStart**:

1. `bootstrap-session-doctor.sh` — 採用状態 + repo drift + 未判断 trunk 変更を可視化

**UserPromptSubmit**:

1. `sprint-trigger-reminder.sh` — feature prompt のとき sprint 発火判定 3 条件を context 注入 (advisory 早期ヒント)

**PreToolUse on `Edit | Write | MultiEdit`**:

1. `block-out-of-lane-edit.sh`         — 並列 lane 外編集を block (別 worktree の file は fail-closed、repo 外は fail-open)
2. `block-uniso-main-edit.sh`          — active lane 中の main tree 未隔離 source 編集を block (ADR 0005 guard 2)
3. `block-unplanned-feature-build.sh`  — 新規 source 面を sprint 判定なしで作るのを block (opt-in)
4. `block-cross-layer-import.sh`       — 依存方向違反 import を早期 block
5. `require-test-companion.sh`         — 対応 test なき実装編集を block

**PreToolUse on `Bash`**:

1. `block-add-all.sh`               — 個別 add に矯正
2. `block-dangerous-git-ops.sh`     — 他人の作業を消す op を block
3. `block-cross-claude-wip.sh`      — commit 直前に巻き込み check (`--amend` 含む)
4. `block-push-to-protected.sh`     — 宣言 branch への直接 push を block (opt-in)
5. `block-stale-write-to-protected.sh` — stale な checkout からの trunk push を fetch+behind で freshness block (ADR 0009)
6. `block-over-wip-parallel.sh`     — `wip_limit` 超過の `git worktree add` を block (ADR 0005 guard 3, opt-in)
7. `block-unreviewed-merge.sh`      — レビュー記録なき並列 lane branch (board task / worktree) の merge を block (opt-in)
8. `block-merge-if-verification-unclosed.sh` — verification plan が閉じていない lane branch の merge を block (opt-in)
9. `block-arch-violations.sh`       — commit 時に依存方向を権威検証
10. `block-out-of-lane-commit.sh`   — 並列 lane 外の file が載る commit を block (Bash 経由の書き込みを塞ぐ取りこぼしの網、opt-in)
11. `block-commit-if-lint-fails.sh`  — commit が運ぶ file に絞って lint を回す (path 対応 tool のみ scope、go/cargo は whole-tree、ADR 0018)
12. `block-commit-if-tests-fail.sh` — 最後に test を回す
13. `inject-action-memory.sh`       — 再発しやすい action 直前に記録済み memory を additionalContext 注入 (block しない、opt-in、ADR 0010)

block 系を test 実行より前に置くのは、test 実行が成功しても巻き込んだ commit / 契約違反は事故源だから。

## bypass

特殊事情で hook を一時的に無効化したい場合:

- 個別ツール: Claude Code 内で `/permissions` から該当 hook を deny に変える
- 全体: `.claude/settings.json` で hook を override

bypass は **規律を壊す**。bypass する前に「なぜそれが必要なのか」を 1 文で説明できるか確認する。説明できないなら bypass せず別経路を選ぶ (= 個別 add に書き換える / `--force-with-lease` に変える / 等)。

## opt-in pilot: cohort-audit (確率 gate、ADR 0008 #2)

**default の 20 hook には含まれない実験的 opt-in。** これは本プラグイン初の**非決定論 (確率) gate** で、現状 advisory のままの「完遂責任 — bug fix と同 PR で同根 cohort audit」(SKILL.md) を gate 化する試み。

- **形態**: `Stop` イベントの **prompt hook** (`type: "prompt"`)。各ターン終了時に Haiku が `$ARGUMENTS` を評価し `{"ok": bool, "reason": str}` を返す。
- **warn-only (block しない)**: `Stop` で `ok:false` のとき reason が **Claude に戻り作業を継続**する (= deny でなく nudge)。「cohort audit を忘れたかも」を促すだけで止めない。
- **cry-wolf 抑制**: prompt は「user-facing bug fix かつ cohort audit 不在のときだけ `ok:false` / feature・refactor・docs・test・config・不確実は `ok:true`」。誤検知は guard を無効化する (`docs/incidents/2026-05-29`) ので false negative 寄りに倒す。
- **なぜ default にしないか**: 確率 gate を全 consumer に毎ターン強制するのは pilot でなく full rollout。opt-in で blast radius を絞り、誤検知率を実運用で観測してから default 昇格を判断する (ADR 0008 条件 b)。
- **CI でテストできない** (モデルを呼ぶため `tests/hooks/` の射程外)。安全網は実運用の手動観測 — `scripts/velocity.sh` の defect-rate と並べ、誤検知が多ければ撤回する。

**有効化** (opt-in): [`templates/hooks/cohort-audit-pilot.json`](../templates/hooks/cohort-audit-pilot.json) の `hooks` ブロックを settings ファイル (`.claude/settings.json` 等) にコピーする。無効化はそのブロックを消すだけ。`disableAllHooks` 下では他の hook 同様効かない。

## Claude Code 契約への依存 (harness contract)

これらの hook は Claude Code が PreToolUse / SessionStart で渡す **payload JSON の key 名**に依存する。Anthropic が key を rename / 削除すると、依存する gate の挙動が変わる — **変わり方は gate ごとに違う**ので明示しておく (= 隠れた外部前提を可視化する。move ③ を CC 契約そのものに適用)。

| 依存 key | event | 依存する gate | rename されたときの挙動 |
|---|---|---|---|
| `tool_input.command` | PreToolUse `Bash` | 全 Bash gate ([`lib/parse-command.sh`](./lib/parse-command.sh) 経由) | **fail-closed (安全側)**: `parse_command` が rc≠0 → 各 hook が `exit 2`。全 Bash が止まるので**無音にならず即発覚**する |
| `tool_input.file_path` / `path` | PreToolUse `Edit\|Write\|MultiEdit` | `require-test-companion` / `block-cross-layer-import` / `block-uniso-main-edit` | **fail-open (要注意)**: `parse_json_string_field` が空 → `[ -z "$FILE" ] && exit 0` で素通し = **無音バイパス** |
| `transcript_path` | PreToolUse `Bash` (`git commit`) | `block-cross-claude-wip` | **fail-open**: transcript を読めず巻き込み check が素通し (warning は出る) |
| `cwd` | SessionStart / PreToolUse `Bash` | `bootstrap-session-doctor` / `inject-action-memory` | PWD に fallback (doctor の可視化が劣化 / injector が別 repo の registry を読む可能性 — どちらも block しないので無音劣化のみ) |

**CC をアップグレードしたら再検証する** (= 外部前提は閉じたら再検証、ADR 0004 の原則)。とくに fail-open の 2 key (`file_path` / `transcript_path`) が現行 [docs](https://code.claude.com/docs/en/hooks) と一致するかを確認する。`tests/hooks/*.test.bash` は**期待スキーマ**を pin する (= 期待 key で parse できることを保証) が、合成入力ゆえ**実ハーネスの変更そのものは検出できない** — そこは本表 + アップグレード時の手動再検証が担う。

**なぜ runtime で自動警告 (doctor の 4 軸目) を足さないか**: SessionStart で「key が rename されたか」を自動判定しようとすると、rename と「その surface では元々その key が無い」を区別できない (= 本 repo の test fixture 自体が `transcript_path` を持たない正当な SessionStart payload。surface ごとに差がある)。区別できない自動警告は**誤検知で gate 不信を生む** (cry-wolf。`docs/incidents/2026-05-29-cross-wip-bash-false-positive` が「cry-wolf は guard を無効化する」と記録)。だから自動 advisory を足さず、依存を**本表で明示**して人間のアップグレード再検証に委ねる方を選ぶ (= 強制できない判断を advisory に逃さず、可視化に留める ①②の境界)。

## 公式 docs

[Claude Code Hooks](https://code.claude.com/docs/en/hooks) / [Plugin reference - Hooks](https://code.claude.com/docs/en/plugins-reference#hooks) / [Best Practices](https://code.claude.com/docs/en/best-practices)

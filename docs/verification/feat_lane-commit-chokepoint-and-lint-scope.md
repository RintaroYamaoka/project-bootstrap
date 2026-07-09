# verification plan — lane 強制を commit 関所へ (ADR 0017) + lint の信号を commit に絞る (ADR 0018)
# 由来: marketing-app incident 2026-07-09 (M5)。incident の diagnosis 2 件はいずれも実査で棄却し、真因を置き換えた。
# 落とした範囲: go/cargo の whole-tree fallback を実 toolchain で走らせる検証 (この repo に go/cargo が無い) / 実 biome の挙動 (fake binary で代替)
# STATUS | kind | behaviour | oracle | by | evidence/note
PASS | e2e         | lane worktree で自分の lane 内 file だけを stage した commit が、lane 外の既存 lint debt で block される (= 修正前の実挙動。incident の再現) | 実 git worktree + 実 hook の exit code | ai | scratchpad/lintprobe 実走 → EXIT=2 を確認してから着手 (推測でなく再現から始めた)
PASS | e2e         | 修正後、同じ状況で commit が通る (lane worker が他人の debt で止まらない) | 実 hook の exit code | ai | scratchpad/lp2 A) EXIT=0 / tests/hooks/lint-scope.test.bash "unowned pre-existing debt does not block"
PASS | unit        | lint gate は commit が運ぶ自分の file の lint 失敗では止まる (緩めすぎていない) | 期待値 | ai | lint-scope.test.bash "this commit's own file blocks" (exit 2 + stderr に file 名)
PASS | unit        | `git commit -a` が掃き込む未 stage tracked 変更も判定対象に入る | 期待値 | ai | lint-scope.test.bash + block-out-of-lane-commit.test.bash 双方 (commit-files.sh 共有ゆえ 2 関所で同一挙動)
PASS | unit        | 削除 file / 対象外拡張子 / lintable 0 件 は linter に渡さない (誤 block しない) | 期待値 | ai | lint-scope.test.bash 3 ケース
PASS | contract    | file 引数を取れない linter (go/cargo) は whole-tree・fail-closed のまま (= 緩めていない) | 期待値 (exit 2 + 「lane を出て」案内) | ai | lint-scope.test.bash "unscopable linter still blocks"
PASS | gameable    | 既知 tool allowlist が「scope できる」を騙って `next lint` を scope し、存在しない lint 失敗を発明しないか | 期待値 | ai | lint_script_tool('next lint') == "" を固定。誤 scope は誤 block を生むので fail-safe 側に倒した
PASS | metamorphic | lint の判定は file 名でなく「commit がその file を運ぶか」の関係にのみ依存する (同じ DEBT.js でも、運ぶ commit は赤・運ばない commit は緑) | 不変関係: block ⇔ (failing file ∈ commit files) | ai | lp2 の A(緑)/B'(赤)/D(-a で赤)/E(-a 無しで緑) — file 集合だけを摂動して結論が反転
PASS | e2e         | lane 強制: Bash 経由の書き込み (formatter/sed/codemod) が commit 関所で捕まる | 実 hook exit code | ai | block-out-of-lane-commit.test.bash「out-of-lane staged file blocks commit」(Edit hook は原理的に見えない経路)
PASS | e2e         | lane worker が別 worktree (メインリポ) の絶対 path を編集すると block、repo 外 (/tmp) は素通し | 実 git worktree (`git worktree add`) + exit code | ai | block-out-of-lane-edit.test.bash 4 新ケース。旧実装は前者を fail-open していた
PASS | unit        | merge/rebase/cherry-pick/revert 中の commit は lane を跨いでよい (lead の conflict 解決を止めない) | 期待値 | ai | block-out-of-lane-commit.test.bash「merge in progress」
PASS | unit        | hook 入力が parse 不能なら fail-closed (他の commit 関所と同一 fail-mode) | 期待値 | ai | block-out-of-lane-commit.test.bash 最終ケース
PASS | mutation    | 上記 assert が実効を持つ (= 実装を壊すと赤くなる)。6 番目の seam「緑の嘘」を手動 1 発 mutation で潰す | 注入した変異をテストが殺すか (= テスト自身が外オラクル) | ai | 5 変異すべて kill: ①commit gate の offender 検出無効化 (4 assert 赤) ②edit gate を旧 fail-open に戻す (3 赤) ③scoping 無効化 (4 赤) ④lint_ext_ok 全許可 (4 赤) ⑤未知 script を scopable 扱い (4 赤)。復元後すべて緑
PASS | unit        | 自作テスト自身の緑の嘘を 1 件検出・修正した | 実装を壊して赤化するか | ai | `cmd && assert_eq 0 0 \|\| assert_eq 0 1` は両分岐で緑になる偽 assert だった → 終了コードを値として明示する形に書き直し
PASS | contract    | 新 hook が hooks.json (Bash matcher) に登録され、doctor.sh の sprint REQ に載る (= 配備漏れが partial として鳴る) | doctor.sh 実走 + JSON parse | ai | 登録 hook 数 20 = plugin.json 記述と一致。doctor.test.bash の「complete vendoring」fixture が新 hook 不在を partial として検出したので fixture 更新 (= 配備カバレッジ gate が正しく鳴った証拠)
PASS | contract    | 全 hook スイート回帰なし | tests/hooks/run.sh | ai | 38 suites, 0 failed。shellcheck -S warning もゼロ
PASS | manual      | 事故: テストが `git rev-parse --git-dir` の相対出力を使い、本 repo の .git に MERGE_HEAD を書いた | 実ファイル確認 | ai | 検出・除去済み (`--absolute-git-dir` に修正)。repo が merge 状態でないことを確認
PASS | manual      | **仕様判断**: lint gate の信号を commit に絞った結果、「ツリーに既存 debt があっても、それに触らない commit は通る」ようになった。これは意図した緩和だが、gate の約束を変えている | 設計者 (単一 orchestrator) の意図 — repo にも AI にも無い | human | merge 前に「変更前 exit 2 / 変更後 exit 0・自分で運ぶ file なら exit 2」の出力モックを提示し、3 択 (この緩和 / lane 内だけ緩める / revert) から「この緩和で merge」を明示選択。ADR 0018 に trade-off 明記、CI whole-tree lint が backstop
DROP | e2e         | go/cargo の whole-tree fallback を実 toolchain で検証 | n/a | ai | この repo に go/cargo が無い。挙動は変更していない (分岐を触っていない) ので、fake linter 経由の fail-closed 確認で足りると判断
DROP | e2e         | 実 biome/eslint での scope 実行 | n/a | ai | fake binary で「引数に渡った file 集合」を観測しており、判定対象は bootstrap 側の file 集合計算。実 linter の内部挙動は bootstrap の責務外 (linter に委ねる設計)

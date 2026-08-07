# verification plan — feat/commission-upstream (ADR 0022-0024: 上流工程を bootstrap に統合)
#
# 意図: AI が人間不在で走り切るための事前条件を「人が読む文書」でなく **機械検証可能な契約
#   (作業指示書 = WO)** にし、発注という行為そのものを関所にする。前身 2 実装が死んだ原因
#   (強制を 1 つも持たなかった / 成果物 13 種で記憶の負担が使用を止めた) を①の分解で潰す。
# 跨いだ境界:
#   (a) **新しい blocking gate を 3 本足す面** — 誤 block は全 commit / 全新規 file を止めうる。
#       特に「commission 未採用の repo が完全に無音のままか」は全採用 repo に影響する回帰面
#   (b) **commit が運ぶ中身と、検査した中身が一致するか** — file 名は index、中身は worktree、
#       という食い違いは「検査は通ったが commit されたのは別物」という無音の fail-open になる
#   (c) **被覆の判定が Edit 経路だけに載っていないか** — 編集時 matcher しか持たない gate は
#       redirect / codemod / scaffolder を素通しする (ADR 0017 が lane で通った道)
#   (d) **配備の可視化 (③)** — commission は CI twin をまだ持たないので、配備漏れを後追いで
#       拾う net が doctor しか無い。REQ への登録漏れは gate ごと無音になる
# 落とした範囲: 下記 DROP 3 行
# STATUS | kind | behaviour | oracle | by | evidence/note

PASS | unit        | WO パーサ: 節の充足 (placeholder `<...>` の行/セル単位判定・行中の山括弧は generics として通す)・節の欠落は未記入・frontmatter の読み・DoD⇔オラクルの検算・事前レビュー表の行/状態・未決 ID の抽出・scope glob | 期待値 | ai | tests/hooks/wo.test.bash 38 assert。**実テンプレート**を読んで「全 12 節が未記入と判定される」ことを含む (= TEMPLATE.md と `WO_SECTION_COUNT` の同期漏れがここで落ちる)
PASS | unit        | 発注 gate: 未記入節 / 検算不一致 / 事前レビュー未決着・未実施 (表が空) / `retry_limit` 不正 / 未決台帳の 3 検査 (OPEN 依存・参照先の実在・`deferred:` 先の実在) で exit 2、完全な WO は通す。**draft は止めない**、この commit が運ばない WO は見ない、git グローバルオプション形も捕まえる | 実 temp git repo + 実 hook の exit code | ai | tests/hooks/block-commit-if-wo-incomplete.test.bash 29 assert
PASS | unit        | 被覆 gate (編集時): 未発注で新規 source 面を作ると block / ordered な WO の 2 節が覆えば通す / 既存 file 編集・test・config・doc・commission 自身の成果物は素通し | 実 hook の exit code | ai | tests/hooks/block-impl-without-wo.test.bash 12 assert
PASS | unit        | 被覆 gate (commit 側): **この commit が追加する file だけ**を見る (変更・削除は素通し = bug fix / refactor は trip しない) / 未発注は block / draft は発注でない / 統合操作中 (MERGE_HEAD) は fail-open / index 空は fail-open / 解析不能は fail-closed | 実 temp git repo (実 index 状態) + 実 hook の exit code | ai | tests/hooks/block-commit-if-impl-uncovered.test.bash 15 assert
PASS | unit        | commit エンジン: `commit_file_content` が **index の版**を返す (`-a` のときだけ worktree)・untracked は worktree に fallback・どちらにも無ければ空 / `commit_added_files` が追加のみを返す | 実 repo で index と worktree を意図的に食い違わせて比較 | ai | tests/hooks/commit-files.test.bash 21 assert (`git add -p` 相当の食い違いを直接 pin)
PASS | unit        | doctor: commission dir が採用として数えられる / charter.md 不在は partial / 3 gate の vendoring 漏れは partial / 3 本揃えば ok | doctor の STATUS + 出力文字列 | ai | tests/hooks/doctor.test.bash 68 assert (新規 8 assert、うち肯定・否定の対を含む)
PASS | metamorphic | assert が実装を握っているか — 新規部分の中核をそれぞれ壊してテストが赤くなるか | 注入した変異をテストが殺すか | ai | 6 変異すべて KILL: ①`commit_file_content` を常に worktree 読みに ②`deferred:` の台帳実在チェックを削除 ③`commit_added_files` から `--diff-filter=A` を削除 ④doctor の commission REQ を削除 ⑤被覆 gate の統合操作 exemption を潰す ⑥`charter_unknown_ids` を常に空に。②④は**今回塞いだ穴そのもの**なので、再発したら赤くなることを直接確認した
PASS | regression  | commission 未採用の repo で挙動が一切変わらない (= 全採用 repo への回帰面) | 既存スイートが無改変で緑 + 本 repo (commission 未採用) での doctor 判定 | ai | run.sh 53 suites / 0 failed。`scripts/doctor.sh .` = STATUS ok (`commission=0`)。3 gate はいずれも dir 不在で即 exit 0
PASS | contract    | 全 shell の構文チェック + hook 配線 JSON の妥当性と本数 | `bash -n` 全 .sh / `json.load` / `hooks.json` の command 数 | ai | hooks・hooks/lib・scripts・tests 全緑、hooks.json = 24 command (README 発火順・plugin.json・README.md の記載と一致)
PASS | e2e         | 必須チェック (`hooks` / `verification-closed`) が実 PR で動き、赤くなるべきときに赤い | GitHub Actions の実 check 結果 | human+ai | PR #25。① 1 回目の push で `hooks` = **緑** (run 31186714902、ubuntu の GNU 環境で 53 suite 再現)・`doctor` 緑 (31186715193)・`retired-check` 緑 (31186715519)。② 同 push で `verification-closed` = **赤** (run 31186715258) — 本 plan のこの行が `TODO` のままだったため。**自分の gate に自分で捕まった** = required check が飾りでないことの直接の証拠。③ この行を実測で閉じた次の push で緑に戻ることを merge 前に確認
DROP | e2e         | 採用 repo に `docs/bootstrap/commission/` を置いての実運用 1 巡 (発注 → 実装 → 検収) | n/a | ai | このプラグインは採用 repo のファイルを勝手に作らない (採用は人の判断、ADR 0003 と同型)。かつ **実運用 0 件のまま設計を足さない**方針なので、1 巡は次の作業として切り出す。配備漏れは doctor の vendored-coverage が可視化する
DROP | scope       | commission gate のサーバ側 (CI) twin | n/a | ai | ADR 0023 で「実運用 1 巡してから ADR 0012 の二層化に載せるか判断」と明記済み。本 PR の範囲外 (= 意図的に未実装の穴であり、無自覚な欠落ではない)
DROP | scope       | `--amend` での追加 file 判定 (`--cached --diff-filter=A` は HEAD 基準なので amend では親がずれる) | n/a | ai | amend は「直前の commit の作り直し」で、元の commit が既に同じ関所を通っている。二重に厳密化するより、射程を明示して bound する方を選ぶ (lint 関所・retired 関所と同じ既知の射程)

# verification plan — feat/windows-hook-dispatch (ADR 0026: 単一プロセス dispatcher)
#
# 意図: Windows (Git Bash / MSYS) で hook が 1 tool call 数秒かかる速度税を撤廃する。
#   遅い gate は deny される動機を作る — 誤検知が規律を殺すのと同型の逆効果なので、
#   これは快適さでなく規律の生存の問題。挙動 (block/pass の判定集合) は一切変えない。
# 跨いだ境界:
#   (a) **22 個の blocking gate 全部の実行モデルを一度に変える面** — 変換ミス 1 つが
#       その gate の無音 fail-open (または全 tool call の誤 block) になる
#   (b) **1 プロセス共有** — 旧配線に無かった failure class (変数汚染 / cwd 汚染 / trap 衝突)
#   (c) **Windows 実機** — この repo の開発機は WSL2 で、肝心のターゲット環境は手元に無い
#   (d) **配線の正本が 2 つに割れた** — hooks.json (旧) と dispatch.sh の GATES (新)。
#       足し忘れ = plugin 経由で発火しない
# 落とした範囲: 下記 DROP 2 行
# STATUS | kind | behaviour | oracle | by | evidence/note

PASS | regression  | 22 gate + lib の既存挙動が変換後も不変 (block する入力は block、通す入力は通す、fail-mode 契約不変) | 既存スイート (block/pass を実 exit code で pin する characterization tests) が無改変で緑 | ai | tests/hooks/run.sh = 54 suites / 0 failed (既存 53 + dispatch)。gate 変換は 1 本ずつ行い、各変換直後にその gate のテストを個別実行して green を確認した
PASS | unit        | fork ゼロ API の等価性: json_field_var / parse_command_var が stdin 版と同じ decode・同じ fail 契約 (key 不在/未終端 = rc 1)・heredoc 除去 (ADR 0025) を保つ | 期待値 assert | ai | tests/hooks/parse-command.test.bash 31→42 assert (新 11)
PASS | unit        | walker の純 bash 化の等価性: `&&&`・`\|\|\|`・separator 密着・backtick 密着・制御文字 \x01 (sed fallback)・「git を含まない command は即 no」で新旧同一 / cmd_invokes_git_subcommand は stdout 汚染ゼロ | 差が出る入力での期待値 assert (bash 5.2 patsub_replacement バグはこのピンが実際に捕まえた) | ai | tests/hooks/git-invocation.test.bash 26→33 assert。既存の compound-command 3 ケースが padding 破壊を検出→修正→green の Red-Green を実際に踏んだ
PASS | integration | dispatcher parity: gate 1 が block / 後続 gate が先行 gate の full walk 後に block / 非 git は全通し / unparseable は fail-closed / 空 command は exit 0 / heredoc 本文は data / injector の stdout JSON passthrough / 複数 gate 同時 block は先勝ち / edit の fail-open / 未知 mode は fail-closed | 実 dispatch.sh の exit code + stderr/stdout | ai | tests/hooks/dispatch.test.bash 19 assert (新規)
PASS | contract    | 1 プロセス共有の汚染封じ込め: cd する gate (tests-fail) は subshell、EXIT trap (wo-incomplete) は明示 rm、gate 関数の scratch は local 宣言 | 複合 command で複数 gate の parser を通すケース + 各 gate 単体テストが temp repo で相互独立に緑 | ai | dispatch.test.bash の「LATER gate still blocks」ケース + run.sh 全緑 (54 suite は同一プロセスでなく別プロセスだが、dispatch 経由ケースが in-process 経路を踏む)
PASS | perf        | Linux 実測で新配線が旧配線より速い (回帰していないことの下限確認) | scripts/bench-hooks.sh (date +%s%N) | ai | WSL2: Bash call 76ms→24ms / Edit 38ms→19ms (N=30)。fork 数は非 git Bash call で 100+ → 数個
DROP | perf        | **Windows 実機 (Git Bash) で体感が快適になったか** — bench の数値と、実セッションで Edit/Bash が引っかからないこと | user の Windows 機で `bash scripts/bench-hooks.sh 20` + 実セッション体感 | human | オラクル (Windows 実機 + 更新済み plugin) が merge の後にしか存在しない — 0.35.0 の heredoc 修正と同じ**リリース後実査**として merge 後に user が実施する (発注者指示 2026-08-31「マージも」)。予測: 旧 数秒/call → 新 0.2-0.5s/call。**数値が予測と大きく違えば plugin cache が旧版のままをまず疑う** (下の行)。実査結果は本 plan の archive 時に追記する
DROP | deploy      | plugin cache が新版に更新されて初めて効く (merge ≠ deployed、配備カバレッジ③)。本作業中も cache は 0.31.0 で 4 版遅れの gate が発火していた (heredoc 誤検知を実際に踏んだ) | 両マシン (WSL2 / Windows) で plugin の版が 0.36.0 以上であること | human | 配備は定義上 merge 後の行為なので merge 前には閉じられない — リリース後実査 (上の行と同時に確認)。更新しない限り本変更は 1ms も効かない
DROP | e2e         | Claude Code 実セッションでの hook 発火 E2E (PreToolUse → dispatch → block) を CI で | n/a | ai | ハーネス実体越しの E2E は CI に組めない (Claude Code 本体が要る)。dispatch.test.bash が「ハーネスが渡すのと同形の payload + 同じ起動形」で代替し、実セッション確認は上の HUMAN 行が担う
DROP | scope       | vendoring 消費者 (.claude/hooks/ 個別配線) の自動リワイヤ | n/a | ai | 旧配線のままでも挙動は同一 (遅いだけ)。dispatch.sh + lib/ を vendor して 2 エントリにし直す手順は hooks/README.md「実行モデル」に記載 — 採用は consent (ADR 0003 と同型)

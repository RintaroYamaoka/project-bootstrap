# verification plan — feat/docs-parent-dir (ADR 0020: docs 成果物を docs/bootstrap/ へ集約)
# 意図: bootstrap 固有の docs 4 ディレクトリを docs/bootstrap/<name> に集約する。
# 跨いだ境界: 全 gate の opt-in 判定 (= ディレクトリの存在)。ここを間違えると採用済み repo が
#   plugin 更新の瞬間に 5 gate を一斉に失う。しかも既存 fixture は旧レイアウトしか組まないので
#   テストは全部緑のまま — 「緑の嘘」が構造的に起きうる面。よって新レイアウトの発火自体を
#   オラクルにし、その実効性を mutation で裏取りする。
# 落とした範囲: 採用 repo の実移行 (下記 DROP 1) / 歴史的記録の path 表記 (下記 DROP 2)
# STATUS | kind | behaviour | oracle | by | evidence/note
PASS | unit        | resolve_docs_dir が新を優先し・旧に fallback し・両在なら新が勝ち・不在なら新 canonical を返す。dir でない stray file は旧 dir を shadow しない | 期待値 | ai | tests/hooks/resolve-docs.test.bash 24 assert。run.sh 46 suites / 0 failed
PASS | metamorphic | resolver を旧 path 固定に潰すと新レイアウトの gate が実際に落ちる (= assert が実装を握っている、緑の嘘でない) | 注入した変異をテストが殺すか | ai | 全 kill: resolve_docs_dir を legacy 固定 → 11 suites 赤。うち sprint/review/verification/wip/未隔離編集の各 gate が「exit 2 期待 → 実際 0」= 無音 fail-open として検出。復元後に 46/0 を再確認
PASS | unit        | 旧レイアウトの repo では 5 gate が従来どおり block し続ける (plugin 更新で gate を失わない) | 実 temp repo + 実 hook の exit code | ai | 既存 fixture (全て旧レイアウトを構築) を無改変のまま全緑
PASS | unit        | 半移行 (新 dir + 旧 path に記録) では新が勝ち、gate は fail-closed 側に倒れる。旧 .gate / 旧 review approve / 旧 plan / 旧 board のいずれも通さない | 実 temp repo + exit code | ai | 4 スイートの half-migrated ケース
PASS | unit        | 自己状態の書き込み例外が、新レイアウトがまだ存在しない時点でも効く (最初の board.json を gate 自身が block しない) | 実 hook exit code + 述語の直接呼び出し | ai | docs_state_face の両レイアウト無条件マッチ 4 assert + block-unplanned-feature-build の移行ケース
PASS | unit        | doctor が新レイアウトを採用として検出し、旧残存を advisory (partial でなく ok) で可視化する。移行済み repo では advisory が鳴らない | doctor の STATUS + 出力文字列 | ai | doctor.test.bash 新規 11 assert (否定形 = 移行済みで鳴らないことを含む)
PASS | e2e         | 本 repo 自身を新レイアウトへ移して doctor が ok を返す (dogfood) | 実 repo に対する scripts/doctor.sh の出力 | ai | STATUS: ok (sprint=1 verify=1 memory=1)・旧レイアウト advisory なし
PASS | unit        | block message が実際に解決したパスを名指しする (旧レイアウトの repo を空ディレクトリへ送らない) | stderr の文字列 assert | ai | resolve_docs_label 4 assert + sprint/verification gate の message assertion
PASS | contract    | 全 hook スイート回帰なし + 全 shell の構文チェック | tests/hooks/run.sh / bash -n | ai | 45 → 46 suites, 0 failed。hooks/lib/scripts/tests の全 .sh/.bash が構文 OK
DROP | e2e         | 採用 repo (marketing-app / propagate-ai) での実移行と、そこでの gate 実発火 | n/a | ai | このプラグインは採用 repo のファイルを勝手に動かさない (採用は人の判断。ADR 0003 と同型)。移行は各 repo 側のタイミングで行い、未了は doctor の advisory が可視化する = 本 PR の射程外
DROP | unit        | 歴史的記録 (CHANGELOG / ADR 0001-0019 / incidents / handoffs 本文) の path 表記 | n/a | ai | 書かれた当時のレイアウトを記述した日付つき記録なので遡って書き換えない (ADR 0020 に明記)。実体の移動は git が追跡しており、掘るなら git 履歴が正

# verification plan — feat/docs-parent-dir (ADR 0020: docs 成果物を docs/bootstrap/ へ集約)

意図: bootstrap 固有の docs 4 ディレクトリを `docs/bootstrap/<name>` に集約する。
跨いだ境界: **全 gate の opt-in 判定** (= ディレクトリの存在)。ここを間違えると採用済み repo が
plugin 更新の瞬間に 5 gate を一斉に失う。しかも**テストは全部緑のまま**になる (既存 fixture は
旧レイアウトしか組まないため) — つまり「緑の嘘」が構造的に起きうる面。

行: STATUS | kind | behaviour | oracle | by | evidence

PASS | unit | resolve_docs_dir が新を優先し・旧に fallback し・両在なら新が勝ち・不在なら新 canonical を返す | tests/hooks/resolve-docs.test.bash (24 assertion。stray file が旧 dir を shadow しないケース含む) | ai | run.sh 46 suites / 0 failed
PASS | metamorphic | resolver を旧 path 固定に潰すと、新レイアウトの gate が実際に落ちる (= テストが実装を握っている) | mutation: resolve_docs_dir を legacy 固定 → 11 suites fail。うち sprint/review/verification/wip/未隔離編集の各 gate が「exit 2 期待 → 実際 0」= 無音 fail-open として検出 | ai | mutation 実行ログ (2026-07-30)
PASS | unit | 旧レイアウトの repo では 5 gate が従来どおり block し続ける (更新で gate を失わない) | 既存 fixture (全て旧レイアウトを構築) が無改変で緑 | ai | run.sh 46/0
PASS | unit | 半移行 (新 dir + 旧 path に記録) では新が勝ち、gate は fail-closed 側に倒れる | 4 スイートの half-migrated ケース (.gate / review approve / plan / board が旧 path にあっても通さない) | ai | run.sh
PASS | unit | 自己状態の書き込み例外が、新レイアウトがまだ存在しない時点でも効く (最初の board.json を自分で block しない) | docs_state_face の両レイアウト無条件マッチ + 移行ケース 2 本 | ai | resolve-docs.test.bash / block-unplanned-feature-build.test.bash
PASS | unit | doctor が新レイアウトを採用として検出し、旧残存を advisory (partial でなく ok) で可視化する | doctor.test.bash の新規 7 assertion (移行済み repo で advisory が鳴らないことの否定形も含む) | ai | run.sh
PASS | e2e | 本 repo 自身を新レイアウトへ移して doctor が ok を返す (dogfood) | bash scripts/doctor.sh . | ai | STATUS: ok (sprint=1 verify=1 memory=1)・旧レイアウト advisory なし
PASS | unit | block message が実際に解決したパスを名指しする (旧レイアウト repo を空ディレクトリへ送らない) | resolve_docs_label のテスト 4 本 + sprint/verification gate の message assertion | ai | run.sh
DROP | e2e | 採用 repo (marketing-app / propagate-ai) の実移行と、そこでの gate 実発火 | このプラグインは採用 repo のファイルを勝手に動かさない (採用は人の判断。ADR 0003 と同型)。移行は各 repo 側のタイミングで行い、doctor の advisory がその未了を可視化する = 本 PR の射程外 | ai | ADR 0020「採用 repo の移行作業は手動」
DROP | unit | 歴史的記録 (CHANGELOG / ADR 0001-0019 / incidents / handoffs 本文) の path 表記 | 書かれた当時のレイアウトを記述した日付つき記録なので遡って書き換えない (ADR 0020 に明記)。実体の移動は git が追跡している | ai | ADR 0020「歴史的記録は書き換えない」

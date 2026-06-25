# verification plan — データ修復時の「修復か仕様か」意図確認 inject (ADR 0013)
# 意図: AI が「値の欠落=バグ」と推測して domain owner 確認前に backfill する失敗を、
#       backfill/UPDATE/migration の瞬間に普遍 doctrine を可視化して機械的に防ぐ。
# 落とした範囲 (無音カット禁止): WHERE 厳密判定 / DDL vs DML 区別はしない (documented limit、
#       never-block ゆえ過検出は advisory ノイズのみ)。consumer 側の型レベル防御 (discriminated
#       union/CHECK) は project の責務で本 hook の射程外。
# STATUS | kind | behaviour | oracle | by | evidence/note

PASS | unit  | backfill/data-migrate スクリプト名・prisma db execute・psql/mysql inline UPDATE/DELETE・knex/alembic 等が data-backfill にマップ | 期待値 (既知) | ai | action-gate.test.bash 新 10 ケース緑
PASS | unit  | echo backfill / select / build 等の benign は誤検出しない (visibility ノイズ制御) | 期待値 | ai | action-gate.test.bash 負例 4 ケース緑
PASS | unit  | action_default_memo が data-backfill に普遍 doctrine を返し、prod-deploy には返さない | 期待値 | ai | 同 test
PASS | integration | injector が registry 未 arm でも data-backfill のデフォルト doctrine を additionalContext JSON で出す | 実 hook の JSON 出力 | ai | action-gate.test.bash + smoke (python で additionalContext を decode し本文確認)
PASS | integration | registry が arm していれば project メモを default の後に追記 | 実 hook 出力 | ai | action-gate.test.bash "both" ケース緑
PASS | invariant | hook は data-backfill でも決して exit 2 しない (可視化であって block でない) | exit code | ai | "NEVER exits 2" ケース緑
PASS | regression | 既存 action-key (prod-deploy/prod-db-migrate) と全 hook suite に回帰なし | 全テストスイート | ai | run.sh 35 suites 0 failed
HUMAN | e2e | 実 product repo の session で実際に backfill 系コマンドを打つと doctrine が読めて actionable に出る | 実 Claude Code session で目視 | human | 機構は既存 inject-action-memory と同一・smoke で JSON 確認済み。最終確認は orchestrator (single-orchestrator frontier)
DROP | unit | WHERE 句の有無・DDL/DML の厳密判別 | n/a | ai | トークナイザ射程外・意図的 documented limit。never-block ゆえ過検出は advisory ノイズのみで害なし
DROP | contract | consumer 側の discriminated union/CHECK 制約による型レベル防御 | n/a | ai | project (appo 等) の責務。本 lane は bootstrap 側の可視化のみが scope

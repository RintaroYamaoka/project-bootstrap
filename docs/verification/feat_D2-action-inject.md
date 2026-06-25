# verification plan — feat/D2-action-inject
#
# 意図: 再発しやすい action の直前に該当 memory を additionalContext 注入する。決して block しない。
# matcher は controlled-vocab enum (string proxy でない)。
# 継ぎ目: コマンドのトークン化 (string proxy 化の罠) + 注入のみで exit 2 しない契約。
# オラクル = 実 hook の出力 (additionalContext JSON / 無音) と exit code。
#
# STATUS | kind | behaviour | oracle | by | evidence/note

PASS  | inject      | match + armed の action で additionalContext JSON を出して exit 0 | 実 hook | ai | action-gate test 38 assertions / reviewer
PASS  | never-block | parse-fail / 非match / 非armed → exit 0 無音 / **決して exit 2 しない** | 実 hook | ai | reviewer 全状態で exit 2 無しを確認
PASS  | matcher     | 共有 tokenizer 経由の enum (path-prefixed / 複合 / env-prefixed) で per-entry 正規表現でない・benign を誤 match しない | unit | ai | action-gate test
PASS  | doctor      | doctor が registry presence / orphan を surface・既存 doctor test 不変 | 全 suite (doctor.test 26/0) | ai | reviewer が orphan/clean/incident-no-registry/silent を手動実行
DROP  | scope       | 任意ネスト shell の完全 parse (bash -c は近似) | n/a | ai | 文書化済み fail-open (取りこぼし得る memo、誤 block は決してしない) / ADR 0010

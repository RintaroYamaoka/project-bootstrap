# verification plan — feat/D1-stale-write-protected-gate
#
# 意図: trunk への push が stale checkout から走るのを behind>0 のとき block / offline・非trunk
# は fail-open / block-push-to-protected (フロー強制) と非重複 (鮮度強制)。
# 継ぎ目: コマンドのトークン化 (string proxy) + network fetch + offline fail-open。
# オラクル = network 無しの file:// remote/clone fixture に対する実 hook の exit code。
# kill-question: false-block 行と fail-open 行で両方向を塞ぐ。
#
# STATUS | kind | behaviour | oracle | by | evidence/note

PASS  | trunk-block  | trunk push が behind のとき exit 2 + 乖離数 + fetch/rebase 助言 | 実 hook (file:// stale clone, N=2-4) | ai | block-stale-write test 14 assertions / reviewer trace
PASS  | signal       | trunk dest を protected-branch.sh 再利用で列挙 (複合 / path-prefixed / src:dst / +force / refs/heads / 暗黙current) → 全 block | 実 hook | ai | reviewer 全ケース exit 2 / unit
PASS  | no-false-block| flag 値 'main' / 非trunk push while stale / 非push → exit 0 | 実 hook | ai | reviewer trace ('-o main' は値、destでない)
PASS  | fail-open    | offline / fetch-fail / trunk 解決不能 / behind==0 → exit 0 (作業を止めない) | 実 hook + fetched_behind_count rc=1 | ai | repo-drift test fetch-failure 別シグナル / reviewer
PASS  | engine       | fetched_behind_count が実 fetch する (offline behind=0 vs fetched=2) + refspec bounded (無制限 sync しない) | repo-drift test 20 assertions | ai | reviewer 検証
PASS  | non-dup      | block-push-to-protected と直交 (flow vs freshness)・offline doctor 不変 | code review + 全 suite 32/0 | ai | ADR 0009 が明記
DROP  | scope        | 任意の本番スクリプト (tsx migrate.ts) の stale 実行 | n/a | ai | 決定的痕跡なし → SessionStart drift advisory に残す (ADR 0009 に明記)

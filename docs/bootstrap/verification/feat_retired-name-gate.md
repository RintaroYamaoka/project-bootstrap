# verification plan — feat/retired-name-gate (ADR 0021: 引退した名前の混入を commit で止める)
# 意図: 改名で引退した語が「改名の後に書く人」によって新しいコードに混入するのを、改名者の
#   自己申告ではなく独立した機構で止める。
# 跨いだ境界:
#   (a) 新しい blocking gate を全 `git commit` 経路に足す面 — 誤 block は全 commit を止めうる。
#       特に「marker 不在の repo が無音のままか」は、全採用 repo に影響する回帰面
#   (b) gate の射程の**外**に意図的に置いた蓄積残存 — 射程外が「見えない」になると、gate を
#       置いたこと自体が誤った安心を配る (緑の嘘の構造版)
#   (c) 判定エンジンを 3 消費者 (hook / CI / doctor) が共有する面 — 1 つだけ緩いと無音の穴
# 落とした範囲: 下記 DROP 2 行
# STATUS | kind | behaviour | oracle | by | evidence/note
PASS | unit        | エンジン: marker の parse (コメント/空行/trim/列欠け)・単語境界 (`typeNo` は `i.typeNo` に当たり `typeNotation` には当たらない)・射程 glob・多バイト語の部分一致 fallback・追加行の抽出 (`+++` 除外・exempt path 除外・`-a` の有無) | 期待値 | ai | tests/hooks/retired-terms.test.bash 36 assert
PASS | unit        | gate: 追加行の混入で exit 2 かつ置換先を message に出す / 既存残存では止まらない / 改名 commit 自身は止まらない / docs は素通し / 近縁識別子で止まらない / 空 marker は素通し / 旧 flat marker でも発火 / 解析不能は fail-closed / repo 外は fail-open | 実 temp git repo + 実 hook の exit code | ai | tests/hooks/block-commit-if-retired-term.test.bash 19 assert
PASS | unit        | CI net が hook と同じものを判定する (追加行のみ)。三点差分では base 側の改名をこの branch のせいにしない | 実 temp git repo の 2 branch + CLI exit code | ai | tests/hooks/retired-check-cli.test.bash 10 assert。二点だと exit 1 になることも pin (誤読の再発検出)
PASS | unit        | doctor: 採用検出 / 空 marker は partial / 残存は advisory で status を落とさない / 残存ゼロなら advisory を出さない / docs を残存に数えない / vendoring 漏れは partial | doctor の STATUS + 出力文字列 | ai | tests/hooks/doctor.test.bash 新規 14 assert (否定形 2 つ = 「鳴らないこと」を含む)
PASS | metamorphic | assert が実装を握っているか — エンジンの中核をそれぞれ壊してテストが赤くなるか | 注入した変異をテストが殺すか | ai | 4 変異とも kill。**この pass は実バグを 1 件出した**: 変異③ (exempt 述語を無効化) が doctor スイートで生き残り、doctor が除外規則を pathspec で**二重に**持っていたことが露見した (gate が見ない path を doctor が数えるズレ = 単一権威違反)。engine に `retired_pathspec_args` を切り出して修正し、2 表現が同じ repo 上で一致することを直接 assert するテストを追加。修正後: 変異③ = engine/gate が kill (doctor は述語を使わないので生存が正)、変異④ (pathspec を潰す) = engine/doctor が kill (gate は pathspec を使わないので生存が正)
PASS | unit        | marker 不在の repo で挙動が一切変わらない (= 全採用 repo への回帰面) | 既存 48 スイートが無改変で緑 + gate の marker 不在ケース | ai | run.sh 49 suites / 0 failed
PASS | contract    | 全 shell の構文チェック | bash -n | ai | hooks/lib/scripts/tests の全 .sh/.bash
PASS | e2e         | 本 repo 自身に marker を置いて doctor が正しく読む (dogfood の最小形) | 実 repo に対する scripts/doctor.sh の出力 | ai | 一時 marker で retired=1 と残存 advisory を確認、後に撤去 (本 repo には引退した名前がまだ無いので恒久 marker は置かない = 空 marker は partial になる)
DROP | e2e         | 採用 repo (marketing-app / propagate-ai) への marker 配置と実発火 | n/a | ai | このプラグインは採用 repo のファイルを勝手に作らない (採用は人の判断。ADR 0003 と同型)。配置漏れは doctor の vendoring チェックが可視化する
DROP | unit        | 「重複した定義」の検出 | n/a | ai | 機構自体を作らないと決めた (ADR 0021 決定④)。実例が 1 件出たら機械化を検討する、が昇格条件
OPEN | e2e         | CI net (`templates/ci/bootstrap-retired.yml`) が実 PR で実際に落ちる | **HUMAN** — 実 PR を 1 本立てて workflow の赤を見る | human | template は consumer repo にコピーして初めて効く。本 repo にはまだ配線していないので、CI での実発火は未観測。ローカル CLI としては tests/hooks/retired-check-cli.test.bash が実 git repo で検証済み

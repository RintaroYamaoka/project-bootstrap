# verification plan — AI ハードコード対策: verification 7th seam + held-out advisory (axis 3) + secret-scan (ADR 0016)
# 落とした範囲: secret-scan.yml の実 CI 実行 (この repo に wire しない配布 template ゆえ) / gitleaks の誤検知率
# STATUS | kind | behaviour | oracle | by | evidence/note
PASS | unit        | axis 3 は kind=gameable かつ kind=metamorphic 不在で advisory を出す | 期待値 (advisory 文字列) | ai | tests/hooks/verification-drift.test.bash case16
PASS | unit        | axis 3 は metamorphic で裏打ちされたら該当軸で沈黙する | 期待値 | ai | case17
PASS | metamorphic | 発火は kind フィールドのみに依存し、behaviour/note の prose ("hardcode/game") を変えても発火しない (lexicon-scan 誤発火の否定 = 入力摂動で結論不変) | 不変関係: fire ⇔ (gameable ∧ ¬metamorphic) | ai | case18 — prose を変えても非発火
PASS | unit        | axis 3 は docs-only 変更で沈黙 / 常に exit 0 (advisory・never block) | 期待値 | ai | case19, case20
PASS | monitor     | この repo の実 plan 群 (合成でなく本番) に対し axis 3 が誤発火しない — held-out 相当 (自作の合成テストでなく実データで採点) | 実 repo の doctor 実走 | ai | verification_drift_report "$PWD" → "テストゲーミング" 0 件、scripts/doctor.sh も clean
PASS | unit        | kind 語彙への gameable/metamorphic 追加が OPEN/CLOSED 判定・他 gate を壊さない | 期待値 | ai | tests/hooks/run.sh → 36 suites, 0 failed (vplan_* は STATUS keyed で kind 非依存)
PASS | contract    | secret-scan.yml が YAML として妥当 + gitleaks/gitleaks-action@v2 の documented interface (GITHUB_TOKEN env / fetch-depth:0) に一致 | YAML parser + action 公開仕様 | ai | python yaml.safe_load OK; action README のインターフェースに一致
PASS | manual      | ADR 0016 の doctrine (2 クラス分離 + held-out・宣言駆動 advisory) が設計意図に合致し、マージしてよいか | 設計者 (単一 orchestrator) の判断 | human | 会話で doctrine→機械化→マージを段階承認 (「具現化して」→「進める」→「マージまでやって」)
DROP | e2e         | secret-scan gate を実 CI で走らせ実 leak を検出する | n/a | ai | この template は本 repo の .github に wire しない配布物 — 採用 repo 側で発火する。ここで走らせると本 repo の運用を変えてしまう (価値<副作用)

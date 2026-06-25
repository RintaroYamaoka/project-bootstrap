# 2026-06-25-stale-staged-commit: stale な main から trunk へ push して commit を落とした (rebase-drops-deploy)

ライブ product の運用で、`origin/main` より遅れた local `main` から trunk へ直接 push した。push 前に remote が進んでいたが、local が stale だったため push の整合化 (rebase / pull) で **remote 側にあった commit が落ち** (= rebase-drops-deploy)、その分が trunk から消えた。status は clean で、ローカルでは「自分の変更を push しただけ」に見えていた。

2026-06-16 の prod-migration 事故と同じ stale-checkout class。あちらは「古いロジックで本番を汚す」方向の害で、こちらは「remote が進んだ分を取りこぼす」方向の害。どちらも **status clean を on-latest-main と誤読** した同根。

## 関係する file / 識別子

- `hooks/lib/repo-drift.sh` — ヘッダで本 incident を named reference として記載
- `origin/main` — push 先 trunk (drift_main_ref が解決する ref)
- local `main` — remote trunk より遅れた checkout (push 元)

---

## 1. ミスの一覧

### 1.1 stale な local main から trunk へ直接 push した

- **何をした**: `origin/main` より遅れた local `main` で、追従 (fetch + rebase/pull) せずに trunk へ push した
- **何が問題だった**: remote が先に進んでいる状態で stale な tip を push すると、整合化の過程で **remote 側の commit を取りこぼす** 経路ができる。non-fast-forward を force で押し切る / 古い base で rebase して remote の差分を握りつぶす、いずれも commit を落とす
- **観測された結果**: trunk から commit が 1 件消えた (= 本番に出ているはずの変更が落ちた)

### 1.2 push 前の freshness 確認が習慣任せだった

- **何をした**: push 前の `git fetch` / 遅れ確認を人間の注意力に任せていた
- **何が問題だった**: 注意力は信頼できない強制 — 忙しい運用や status clean の安心感で省略される。decision を人間に委ねる advisory では、push の瞬間を止められない
- **観測された結果**: 遅れに気づかないまま push が成立した

## 2. 真因

> stale-checkout class の二つ目の現れ。**status clean を「on latest trunk」と読み**、remote が進んでいるのに stale な tip を trunk へ push した結果、整合化で remote の commit を取りこぼした。2026-06-16 と同じく、決定論的 trace を持つ操作 (= trunk への `git push`) に freshness の precondition が無かったことが構造原因。trunk push という行為そのものを信号にして、fetch 後 behind > 0 なら止めれば、両方向の害 (古いロジックで汚す / 進んだ分を落とす) を 1 つの gate で塞げる。

## 3. 構造的再発防止

- [x] **hook (新)**: `block-stale-write-to-protected.sh` — push 先が trunk branch で fetch 成功かつ behind > 0 のとき `exit 2`。`git fetch && git rebase/pull` で追従して behind 0 にしてから push し直すよう促す (本 incident と 2026-06-16 を message に named reference)
- [x] **engine (新)**: `lib/repo-drift.sh` の `fetched_behind_count` を gate の信号源にし、offline doctor (`behind_count`) と staleness の single authority を共有 (drift しない)
- [x] **fail-mode**: 非 trunk push / fetch 失敗 (offline) / behind 0 は fail-open。trunk push + fetch 成功 + behind>0 のときだけ block (= force push で押し切る前に止める)
- [x] **test**: trunk push behind → exit 2、fresh → exit 0、fetch 失敗 → fail-open を pin (`tests/hooks/block-stale-write-to-protected.test.bash`)

## 4. 関連 memory / docs

- `docs/incidents/2026-06-16-prod-migration-from-stale-checkout/` — 同 class の姉妹事故 (stale checkout からの prod migration)
- `docs/decisions/0009-stale-trunk-push-freshness-gate.md` — 本 gate の設計 ADR
- `hooks/lib/repo-drift.sh` — drift 判定の single authority
- memory `feedback_gate_signal_and_failmode` — 行為を信号にする / 強制したい判定は前進行為に precondition を課す

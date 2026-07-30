# 2026-06-16-prod-migration-from-stale-checkout: 24 commit 遅れの checkout から本番 migration を走らせた

ライブ product の運用で、`git status` が clean な checkout から prod の DB migration を実行した。その checkout は remote trunk (`origin/main`) より **24 commit 遅れ**ていたが、status clean だったため「最新 main にいる」と信じてそのまま走らせ、**古い schema/ロジックで本番を触った**。被害が出てから、checkout が古かったことに気づいた。

これは `lib/repo-drift.sh` のヘッダにコメントとして記録されていた stale-checkout class の本番化事故。SessionStart の drift advisory は behind 数を可視化していたが、**advisory は判断を人間に委ねる** ので、migration を走らせる瞬間には何も止めなかった。

## 関係する file / 識別子

- `hooks/lib/repo-drift.sh` — ヘッダで本 incident を named reference として記載 (`behind_count` の OFFLINE 判定エンジン)
- `origin/main` — 比較対象の remote trunk (drift_main_ref が解決する ref)
- prod migration コマンド (例: `tsx migrate.ts` 系) — 決定論的な「stale checkout への紐付け」trace を持たない操作

---

## 1. ミスの一覧

### 1.1 status clean を「最新 main にいる」と読んだ

- **何をした**: `git status` が clean なのを確認して、最新 trunk にいると判断して prod migration を実行した
- **何が問題だった**: status clean は「working tree に未 commit 変更が無い」を意味するだけで、「HEAD が remote trunk に追いついている」は**一切保証しない**。両者は独立 — 24 commit 遅れていても working tree は clean になりうる
- **観測された結果**: 24 commit 前のロジック/schema で本番 DB を migrate し、本番を汚した

### 1.2 本番に副作用を持つ操作に freshness gate が無かった

- **何をした**: trunk 起点の prod 操作 (migration / deploy / 直 push) を、追従確認なしで実行できる状態にしていた
- **何が問題だった**: stale-checkout class の防御は SessionStart の **advisory** (drift_report が behind を出す) 止まりで、操作の瞬間を止める precondition が無かった。advisory は consent/判断を人間に委ねるので、忙しい運用では読み飛ばされる
- **観測された結果**: 可視化はされていたが、migration の実行は止まらなかった

### 1.3 オンラインの authoritative な behind 数が無かった

- **何をした**: drift 判定は SessionStart の no-fetch (offline) な `behind_count` だけだった
- **何が問題だった**: offline 判定は **local の remote-tracking ref** と比較するので、fetch していなければ実際の遅れを **under-report** する (= 黙る方向に倒れる)。本番を触る瞬間に「今この瞬間の authoritative な遅れ」を知る手段が無かった
- **観測された結果**: 「behind 0 に見えるが実は遅れている」を排除できなかった

## 2. 真因

> **`git status` clean を「on latest trunk」と読む** のが共通の認知ミス。両者は独立で、status clean は HEAD が remote trunk に追いついている保証にならない。stale-checkout class の防御が advisory 止まりだったため、本番に不可逆な副作用を持つ trunk 操作 (migration / deploy / 直 push) を**追従確認なしで**実行でき、24 commit 前のロジックが本番を汚した。advisory は判断を人間に委ねる構造上、操作の瞬間は止められない — 決定論的な trace を持つ操作 (= trunk への `git push`) には enforceable な precondition (freshness gate) を課すべきだった。

## 3. 構造的再発防止

- [x] **engine (新)**: `lib/repo-drift.sh` に `fetched_behind_count <dir> <remote> <branch>` を追加 — 明示 refspec + timeout 付き fetch を先に行い authoritative な behind を返す。fetch 失敗は distinct な non-zero return で signal し、offline では gate が fail-open する。offline の `behind_count` (doctor 用) は no-fetch のまま据え置き、staleness の single authority を online/offline で 1 本に保つ
- [x] **hook (新)**: `block-stale-write-to-protected.sh` (PreToolUse on Bash) — push 先が trunk branch (drift_main_ref 解決) で、fetch 成功かつ behind > 0 のときだけ `exit 2`。fetch して divergence count を見せ、`git fetch && git rebase/pull` で追従してから push し直すよう促す
- [x] **fail-mode**: parse 不能 = fail-closed。trunk でない push / fetch 失敗 (offline) / behind 0 / trunk ref 未解決 / 非 push は fail-open (= 非対象 repo と offline を一切妨げない)
- [x] **非 gating の明文化**: 任意の prod script (`tsx migrate.ts` 等) は決定論的 trace を持たないので gate しない — その class は SessionStart の drift advisory (drift_report が behind を可視化) に残す。決定論的に書ける `git push` だけを enforce する (ADR 0009)
- [x] **test**: `tests/hooks/repo-drift.test.bash` (fetched_behind_count: behind>0 / behind==0 / fetch 失敗 → distinct signal) と `tests/hooks/block-stale-write-to-protected.test.bash` (trunk push behind → exit 2 / fresh → exit 0 / 非 trunk → fail-open / fetch 失敗 → fail-open / 非 push → exit 0) を pin

## 4. 関連 memory / docs

- `docs/decisions/0009-stale-trunk-push-freshness-gate.md` — 本 gate の設計 ADR (信号選び・fail-mode・block-push-to-protected との非重複と順序)
- `docs/incidents/2026-06-25-stale-staged-commit/` — 同 class の姉妹事故 (stale trunk push が commit を落とした)
- `hooks/lib/repo-drift.sh` — drift 判定の single authority (offline doctor + online gate)
- memory `feedback_gate_signal_and_failmode` — 行為を信号にする / fail-mode を選ぶ / 強制したい判定は前進行為に precondition を課す

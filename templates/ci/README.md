# templates/ci/ — 依存方向を「全員が通る場所」で強制する

Claude Code の PreToolUse hook (`block-cross-layer-import.sh` / `block-arch-violations.sh`) は **Claude のセッションでしか発火しない**。人間が IDE で編集してターミナルで commit したり、plugin が未ロードのセッションだったりすると、強制が静かに消える。

「本気で / 今後絶対に」依存方向を守るには、同じ `.bootstrap/arch` 契約 (旧 flat path `.bootstrap-arch` も互換) を **誰がどう変更しても通る場所** で強制する。`scripts/arch-check.sh` (Claude 非依存 CLI) を 3 層で使う:

| 層 | ファイル | 発火 | 保証 |
|---|---|---|---|
| Claude PreToolUse | plugin の hook | Claude の編集/commit | 速いが環境依存で消えうる |
| git pre-commit | `templates/hooks/pre-commit` | 誰でもローカル commit | ローカルを捕捉 (--no-verify で回避可) |
| **CI on PR** | `templates/ci/bootstrap-arch.yml` | push/PR | **bypass 不可・マージ gate・最終砦** |

## consumer repo への導入

1. `.bootstrap/arch` を repo root の `.bootstrap/` フォルダに置く (依存方向契約。`templates/.bootstrap/arch` 参照。旧 flat path `.bootstrap-arch` も可)
2. CLI とエンジンを vendor する:
   - `scripts/arch-check.sh`        ← 本リポ `scripts/arch-check.sh`
   - `scripts/arch-check-engine.sh` ← 本リポ `hooks/lib/arch-check.sh` (この名前で)
   - `scripts/resolve-marker.sh`    ← 本リポ `hooks/lib/resolve-marker.sh` (この名前で。無いと `.bootstrap/arch` を読めず旧 flat path のみに退避)
3. CI: `templates/ci/bootstrap-arch.yml` を `.github/workflows/` にコピー
4. (任意) ローカル: `templates/hooks/pre-commit` を `.git/hooks/pre-commit` に

CI は **PR の変更ファイルのみ検査**するので、既存 debt があるリポでも全 PR を止めず、新規/変更分の違反だけ gate する (= 既存リポに段階導入できる)。

## 採用状態そのものを検証する (bootstrap-doctor)

依存方向だけでなく **「採用したのに gate が物理的に届いているか」** も CI で検証する。`bootstrap-session-doctor.sh` (SessionStart) の採用 audit は **plugin が在る Claude session でしか発火しない** ため、plugin を入れず `.claude/hooks/` に subset だけ vendoring した repo (= 実際の事故) では session audit がそもそも走らない。CI なら plugin 非依存で必ず通る。

1. `scripts/doctor.sh` を repo に vendor する
2. `templates/ci/bootstrap-doctor.yml` を `.github/workflows/` にコピー

doctor は採用済みなのに必要 hook が欠けている `partial` 状態を `exit 2` で返し、CI がそれを bypass 不可で fail にする。未採用 (`unadopted`) は fail させない (= 採用を強制しない)。

## 統合レビュー gate の PR 経路 (bootstrap-review-gate)

`hooks/block-unreviewed-merge.sh` (Stage 2 の統合関所) は Claude session の手元の `git merge` しか見られない。**GitHub の PR 画面で押す merge ボタンは手元の hook を一切通らない** — 実際に並列開発 10 branch が PR merge で統合された実績がある (`docs/incidents/2026-06-11-parallel-mode-gate-coverage`)。PR 経路の関所は CI にしか置けない。

1. `templates/ci/bootstrap-review-gate.yml` を `.github/workflows/` にコピー
2. レビュー記録の規約は手元の hook と共通: `docs/sprint/reviews/<branch の / を _ に置換>.md` に `verdict: approve`。branch 上でレビューを回し、記録を commit してから PR を出す

GitHub 側では「この branch が並列 lane だったか」を判別できないため、**この file を置いた repo では全 PR にレビュー記録を要求する** (= PR を作ること自体を統合行為とみなす。語彙/命名の proxy に逃げない)。

**required にするかの判断**: branch protection の required status check に指定すると bypass 不可になるが、**main への直接 push も check 待ちで弾かれる**。「日常は main へ直接 commit、並列開発のときだけ PR」という運用の repo では required にせず、PR 上の赤い X を人間が尊重する運用から始める (それでも「無音」ではなくなる — 関所の目的は気づかず素通りを無くすこと)。

## 動作テスト gate の PR 経路 (bootstrap-verification-gate)

`hooks/block-merge-if-verification-unclosed.sh` (ADR 0007 の統合関所) も同じく手元の `git merge` しか見られない。**PR 画面の merge ボタンは手元の hook を通らない**ので、動作テスト計画 (verification plan) を PR 経路でも要求するには CI が要る。

1. `templates/ci/bootstrap-verification-gate.yml` を `.github/workflows/` にコピー (self-contained なので plugin lib の vendoring 不要)
2. 計画の規約は手元の hook と共通: `docs/verification/<branch の / を _ に置換>.md`。OPEN 行 (TODO/FAIL/HUMAN) ゼロ・理由なき DROP ゼロを満たしてから PR を出す

review gate と同型に「PR を作ること自体を統合行為とみなし全 PR に閉じた計画を要求する」。required 化の判断も review gate と同じ。

## 秘密情報のハードコード検出 (secret-scan / ADR 0016 Class A)

`templates/github/workflows/secret-scan.yml`。上の bootstrap-* gate が bootstrap の**自前契約** (依存方向 / レビュー / 動作テスト) の CI twin なのに対し、これは毛色が違う: **AI がしがちなハードコードの静的検出できる半分** (ADR 0016 の Class A) を CI に足す opt-in gate で、plugin lib を一切 vendor せず外部ツール **gitleaks** に委譲する。

なぜ自前スキャナを内蔵しないか: ADR 0016 の判断どおり、独自 matcher は `merge-targets.sh` / `protected-branch.sh` が潰した「未レビュー matcher を consumer に持ち込む」事故クラスの再輸入であり、誤検知が正データを隠す fail-mode を抱える。既存の gitleaks に寄せて再発明を避ける。

**catches**: tracked source に埋め込まれた secrets / credentials / API キー / トークン (実測で AI は人間の約 2 倍埋め込む: arXiv 2603.27130)。
**catches NOT**: Class A の残り (プロンプト過適合の定数 / stub の決め打ち返り値) と Class B (テストゲーミング) 全部 — これらはスキャナでなく動作テスト (verification skill の 7th seam) の領分。

1. `templates/github/workflows/secret-scan.yml` を `.github/workflows/` にコピー (self-contained、vendor 不要)
2. 個人/public repo は secret 不要 (auto の `GITHUB_TOKEN` を使う)。**GitHub org 所有 repo のときだけ** `GITLEAKS_LICENSE` を repo/org secret に設定 (無料、gitleaks.io)
3. (任意) `gitleaks` を branch protection の required status check に指定すると leak が bypass 不可で merge を止める。しなければ赤い X を人間が尊重する運用

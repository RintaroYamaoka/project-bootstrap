# templates/ci/ — 依存方向を「全員が通る場所」で強制する

Claude Code の PreToolUse hook (`block-cross-layer-import.sh` / `block-arch-violations.sh`) は **Claude のセッションでしか発火しない**。人間が IDE で編集してターミナルで commit したり、plugin が未ロードのセッションだったりすると、強制が静かに消える。

「本気で / 今後絶対に」依存方向を守るには、同じ `.bootstrap-arch` 契約を **誰がどう変更しても通る場所** で強制する。`scripts/arch-check.sh` (Claude 非依存 CLI) を 3 層で使う:

| 層 | ファイル | 発火 | 保証 |
|---|---|---|---|
| Claude PreToolUse | plugin の hook | Claude の編集/commit | 速いが環境依存で消えうる |
| git pre-commit | `templates/hooks/pre-commit` | 誰でもローカル commit | ローカルを捕捉 (--no-verify で回避可) |
| **CI on PR** | `templates/ci/bootstrap-arch.yml` | push/PR | **bypass 不可・マージ gate・最終砦** |

## consumer repo への導入

1. `.bootstrap-arch` を repo root に置く (依存方向契約。`templates/.bootstrap-arch` 参照)
2. CLI とエンジンを vendor する:
   - `scripts/arch-check.sh`        ← 本リポ `scripts/arch-check.sh`
   - `scripts/arch-check-engine.sh` ← 本リポ `hooks/lib/arch-check.sh` (この名前で)
3. CI: `templates/ci/bootstrap-arch.yml` を `.github/workflows/` にコピー
4. (任意) ローカル: `templates/hooks/pre-commit` を `.git/hooks/pre-commit` に

CI は **PR の変更ファイルのみ検査**するので、既存 debt があるリポでも全 PR を止めず、新規/変更分の違反だけ gate する (= 既存リポに段階導入できる)。

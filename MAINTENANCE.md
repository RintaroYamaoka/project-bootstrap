# MAINTENANCE.md

`project-bootstrap` のリリース手順。

## バージョニング

[Semantic Versioning](https://semver.org/lang/ja/) に従い `plugin.json` の `version` を明示的に bump する。

- **MAJOR** (`X.0.0`): 互換性破壊 (= skill/agent/hook の名前変更 / 削除 / 根本変更)
- **MINOR** (`0.X.0`): 後方互換な機能追加
- **PATCH** (`0.0.X`): 後方互換な修正

## 同期が要る対 (片方だけ変えると無音で緩む)

| 変えるもの | 一緒に直すもの | 検出 |
|---|---|---|
| 作業指示書 (WO) の節番号・見出し (`templates/docs/bootstrap/commission/wo/TEMPLATE.md`) | `hooks/lib/wo.sh` の `WO_SECTION_COUNT` と placeholder 規則 | `tests/hooks/wo.test.bash` が**実テンプレートを読んで**「全 12 節が未記入と判定される」ことを検査するので落ちる |
| WO 12 節の構成 | `scripts/wo-metrics.sh` の節名テーブル / `docs/bootstrap/commission/metrics.tsv` の過去行の意味 (ADR 0024) | 検出なし — 節を変えたら metrics.tsv に `# --- schema v2 since YYYY-MM-DD ---` を入れ、集計を跨がせない |
| `.bootstrap/` マーカー名・`docs/bootstrap/` の dir 名 | `hooks/lib/resolve-marker.sh` / `resolve-docs.sh` (単一権威) | `tests/hooks/resolve-*.test.bash` |
| Bash gate を 1 本足す (コマンド文字列を見る hook) | **入口は gate 関数 + `lib/standalone.sh` footer の二面構成にし、CMD (heredoc 除去済み) を読む** (ADR 0025/0026)。stdin を直接読んで正規表現を当てると heredoc 本文の除去が効かず、規約を説明する commit を誤検知する。hot path (早期 return より前) に `$( )` / pipeline / 外部コマンドを置かない — Windows (Git Bash) では fork 1 つが ~30-100ms (ADR 0026) | 検出なし — 新 hook を足すときに手で確認する。誤検知は「安全側」でなく規律を回避する動機を作る |
| gate を 1 本足す・消す | ① **`hooks/dispatch.sh` の `BASH_GATES` / `EDIT_GATES`** (= plugin 経由の発火はここが正本。**足し忘れるとその gate は plugin 経由で一度も発火しない**) ② `scripts/doctor.sh` の `REQ` (= vendoring 先の配備漏れ検出。**足し忘れるとその gate だけ配備漏れが無音になる**) ③ `hooks/README.md` の「提供する hook」+「発火順」 ④ `README.md` と `.claude-plugin/plugin.json` の記述 | ① は `tests/hooks/dispatch.test.bash` が代表 payload の parity を固定 (新 gate のケースを足す)。doctor は `tests/hooks/doctor.test.bash` に採用機能ごとの vendored-coverage ケースがある。**③④ は検出なし** — 足すたびに手で直す |

## リリース手順

1. `CHANGELOG.md` の `[Unreleased]` を新バージョンに昇格
2. `.claude-plugin/plugin.json` の `version` を bump
3. commit:
   ```bash
   git add .claude-plugin/plugin.json CHANGELOG.md
   git commit -m "Release X.Y.Z"
   ```
   ※ `marketplace.json` は 0.30.0 (#21) で配布インデックス専用 repo
   <https://github.com/RintaroYamaoka/claude-plugins> へ切り出し済み。`plugins[].version`
   の同期はそちらの repo 側で行う (この repo には実体が無い)。
4. tag + push:
   ```bash
   git tag vX.Y.Z && git push origin main vX.Y.Z
   ```

ユーザー側は `/plugin update` で更新を受け取る。

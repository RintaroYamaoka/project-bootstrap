# MAINTENANCE.md

`project-bootstrap` のリリース手順。

## バージョニング

[Semantic Versioning](https://semver.org/lang/ja/) に従い `plugin.json` の `version` を明示的に bump する。

- **MAJOR** (`X.0.0`): 互換性破壊 (= skill/agent/hook の名前変更 / 削除 / 根本変更)
- **MINOR** (`0.X.0`): 後方互換な機能追加
- **PATCH** (`0.0.X`): 後方互換な修正

## リリース手順

1. `CHANGELOG.md` の `[Unreleased]` を新バージョンに昇格
2. `.claude-plugin/plugin.json` の `version` を bump
3. `.claude-plugin/marketplace.json` の `plugins[].version` も同値に bump
4. commit:
   ```bash
   git add .claude-plugin/plugin.json .claude-plugin/marketplace.json CHANGELOG.md
   git commit -m "Release X.Y.Z"
   ```
5. tag + push:
   ```bash
   git tag vX.Y.Z && git push origin main vX.Y.Z
   ```

ユーザー側は `/plugin update` で更新を受け取る。

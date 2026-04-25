# MAINTENANCE.md

`project-bootstrap` を **長く使えるもの** として育てるための運用ドキュメント。

このプラグイン自身は「規律を仕組みで強制する」道具なので、**プラグインの保守も同じ規律に従って行う**。`SKILL.md` の原則 (KISS / YAGNI / Code is Truth など) はここでも適用される。

---

## バージョニング方針

[Semantic Versioning](https://semver.org/lang/ja/) に従う。`plugin.json` の `version` を明示的に bump する (commit-SHA 方式は採らない)。理由は、各プロジェクトでの install / update タイミングをユーザーが制御できるようにするため。

- **MAJOR** (`X.0.0`): 互換性破壊
  - 既存の skill / agent / command の名前変更 / 削除
  - 計画書フォーマットの非互換変更
  - 鉄則 (例: TDD 中心の前提) の根本変更
- **MINOR** (`0.X.0`): 後方互換な機能追加
  - 新しい skill / agent / command / hook テンプレートの追加
  - 既存原則の補強・追記
- **PATCH** (`0.0.X`): 後方互換な修正
  - typo / 表記揺れ / 説明の改善
  - hook テンプレートの不具合修正

**1.0.0 の基準**: 実プロジェクトで 3 ヶ月以上稼働し、原則 / プリミティブの大幅変更が発生していない状態。それまでは `0.x.y` のまま。

---

## リリース手順

新バージョンをリリースする標準フロー:

1. **`CHANGELOG.md` の `[Unreleased]` を新バージョンに昇格**
   ```markdown
   ## [Unreleased]

   ## [0.2.0] - YYYY-MM-DD

   ### Added
   ...
   ```

2. **`.claude-plugin/plugin.json` の `version` を bump**

3. **`.claude-plugin/marketplace.json` の `plugins[].version` を bump** (plugin.json と同じ値に揃える)

4. **コミット**
   ```bash
   git add .claude-plugin/plugin.json .claude-plugin/marketplace.json CHANGELOG.md
   git commit -m "Release X.Y.Z"
   ```

5. **タグを付ける**
   ```bash
   claude plugin tag --push
   # または手動で:
   # git tag vX.Y.Z && git push origin vX.Y.Z
   ```

6. **push** (default branch)
   ```bash
   git push
   ```

ユーザー側はインストール済みの場合 `/plugin update` で更新を受け取る。

---

## 定期レビュー

3 ヶ月ごと (または重要なバージョン bump 前) に以下を見直す。

### レビュー項目

1. **`SKILL.md` の原則は今も妥当か**
   - 直近のセッションログ (`examples/`) を読み返し、原則と実際の AI の動きにズレがないか確認
   - ズレている場合、原則を更新するかプリミティブを足すかを判断
2. **使われていないプリミティブはあるか**
   - subagent / command / hook テンプレートで、3 ヶ月以上呼ばれていないものは削除候補 (YAGNI)
3. **`examples/` のセッションログから何が学べるか**
   - 共通する困りごとは原則 / プリミティブの不足を示唆する
   - うまくいかなかったセッションこそ改善の材料
4. **依存している外部仕様 (Claude Code plugin format など) の変更**
   - 公式ドキュメントを追って、必要なら追従

### レビュー成果物

- `CHANGELOG.md` の `[Unreleased]` に「Reviewed: YYYY-MM-DD」エントリと、必要なら `Changed` / `Deprecated` / `Removed` を記録
- 大きな変更が必要なら issue を立てて作業化

---

## 新しいプリミティブを足すか判断する

新しい subagent / slash command / hook を追加する前に、以下を満たすか確認する:

1. **実際の摩擦に基づいているか** (仮想ニーズではなく、`examples/` または実体験に裏付けがある)
2. **既存のプリミティブで代替できないか**
3. **責務が 1 つに絞れているか** (SRP)
4. **配置場所が明確か** (skill / agent / command / hook / template のどれに属すか)
5. **削除可能性を考慮しているか** (将来削除しやすい単位で切れているか)

満たさない場合は **足さない**。原則のドキュメント化や `examples/` への記録で十分なことも多い。

---

## 削除 / 廃止する

使われなくなったプリミティブの扱い:

1. **deprecate**: そのバージョンの `CHANGELOG.md` の `Deprecated` セクションに記載 (説明 + 代替手段)
2. **次の MAJOR で削除**: `[X.0.0]` の `Removed` で除去
3. **テンプレート (templates/, hooks/, examples/TEMPLATE.md) の更新**: 旧プリミティブへの参照を消す

> 「念のため残す」は YAGNI 違反。使われていないものは負債。

---

## このドキュメント自体の保守

`MAINTENANCE.md` も `SKILL.md` の原則に従う:

- KISS — 手順は最短で
- YAGNI — 使わないルールを書かない
- Code is Truth — 手順が古くなったら、文書ではなく現実 (リリース手順) を直してから文書を更新する

このドキュメントを変更する場合、`CHANGELOG.md` に記録する。

# docs/ — external memory として AI を助ける

このプロジェクトの **AI 駆動開発の context 経済** を支える外部記憶。`CLAUDE.md` / `SKILL.md` / `memory/` で代替できないものだけを置く。

## 採用する 3 ディレクトリ

```
docs/
├─ README.md       ← この文書 (= 歩き方)
├─ handoffs/       並走 / 再開のための時系列スナップショット
├─ decisions/      ADR (= なぜそう選んだか、永続記録)
└─ incidents/      事故・調査記録 (= 再発防止教材、永続)
```

| dir | 賞味期限 | 書く対象 | 書かない |
|---|---|---|---|
| `handoffs/` | 1-2 週間 | 並走 Claude / 別ターミナル / 翌日の自分 が cold restore するための状態スナップショット | 普遍ルール (= `SKILL.md`) / 既定仕様 (= `CLAUDE.md`) |
| `decisions/` | 永続 | 不可逆な選択の **理由** (= ADR Context / Decision / Consequences) | 機能の解説 (= コード本体) |
| `incidents/` | 永続 | AI / 人間が踏んだ事故と再発防止策。memory `feedback_*` の昇格元 | 個人攻撃 / 業務固有の客先情報 |

## opt-in の 2 ディレクトリ (= gate の on-switch)

以下は **置くこと自体が hook gate の opt-in マーカー** になる (`.bootstrap/<name>` marker と同格。plugin.json の opt-in 一覧参照):

| dir | 有効になる gate | 規約 |
|---|---|---|
| `sprint/` | sprint 発火判定 gate + 並列 lane 系 hook | `templates/docs/sprint/README.md` (board.json / .gate / reviews/) |
| `verification/` | 統合前に閉じた動作テスト計画を要求 (ADR 0007) | `docs/verification/<branch の / を _ に置換>.md`。**閉じた plan の `archive/` への移動は終端責務** (滞留させない) |

## 採用しないディレクトリと理由

参考にした propagate-ai では 8 dir 構成だが、AI 駆動開発で本当に効くのは上記 3 つに絞られる。残り 5 dir は **CLAUDE.md / SKILL.md / memory / コード本体で代替** できるか、**graveyard 化** して負債になる:

| 不採用 dir | 不採用の理由 | 代替 |
|---|---|---|
| `current/` (= 今正しい事実) | `CLAUDE.md` と機能重複。「今の事実」は CLAUDE.md とコード本体が正本 | `CLAUDE.md` + コード |
| `exploring/` (= 未確定試案) | 肥大化して current 昇格しないまま事実上の正本化する兆候が強い | 試案は会話 / plan skill / TodoWrite で扱う、永続化は decision で |
| `reference/` (= 外部 API quirks) | プロジェクトごとに対象 API が違う、雛形化に意味がない | 必要なら project 個別に作る (= `docs/reference/` を後から追加可) |
| `ops/` (= 運用 SOP) | business specific 度が高い、雛形化に意味がない | 必要なら project 個別に追加 |
| `archive/` (= 凍結正本) | 実際に参照されることがほぼない、容量だけ食う | 必要なら git history を辿る。例外: `sprint/archive/` / `verification/archive/` は gate の信号 (活性 plan) と終了済み記録を分ける終端処理先で、これは採用する |

**追加が必要になったら個別に作る**。雛形に空の dir を作ると「書かれていない = やっていない」signal が出続けて負債化する。

## 真実の所在 — docs に書かないもの

| 種別 | 真実 |
|---|---|
| コードの動作 | コード本体 + `tests/` |
| 規律 / AI 協働ルール | `skills/<name>/SKILL.md` |
| プロジェクト固有指示 | `CLAUDE.md` |
| AI に再注入したい教訓 | `~/.claude/projects/<project>/memory/` (= `feedback_*.md`, `reference_*.md`) |
| 設定値 / 環境変数 | `.env.example` / `<framework>.config.*` |
| DB schema | migration ファイル |

`docs/` に書くのは:
- **何を / なぜ決めたか** (= `decisions/`)
- **次の Claude が cold restore に必要な状態** (= `handoffs/`)
- **AI が踏んだ事故と教訓** (= `incidents/`)

これ以外は二重化禁止。

## 失敗兆候 (= テンプレ化しても無意味になる典型パターン)

書き始めたら以下を **3 ヶ月に 1 回** 自分でチェックする:

1. **権威の分散** — 同じ進行 (= phase / step 番号 / 名前) が複数 doc で別記法で書かれる。AI がどれを正本と判別できなくなる。**最新だけ正本にする / 旧記述に `SUPERSEDED` 明示**
2. **handoff の重複化** — handoff → handoff → incident の 3 hop で cold restore コストが膨張する。**1 handoff = 1 hop で完結 / 関連 doc は本文末尾の references にだけ書く**
3. **ADR 習慣未定着** — `decisions/` が空 or 1 件しかない = 判断していない signal と AI に誤読される。**1 不可逆判断 = 1 ADR を default 挙動化** (= `skills/handoff/` / `skills/incident/` と並ぶ判断系 skill 化を検討)
4. **business 固有名混入** — 顧客名 / cid / 客先案件名が `decisions/` `incidents/` の本文に直接書かれる。**外部展開時に削除コストが発生**。識別子は `<customer-A>` `<account-X>` のような placeholder で書く

## 関連 skill

- `skills/handoff/SKILL.md` — handoff doc を書く規律 (session 終了前 / `/clear` 前 / 並走連携前にロード)
- `skills/incident/SKILL.md` — incident doc + memory `reference_*` への昇格 (fix / revert / hotfix / user 叱責後にロード)
- 関連: `skills/project-bootstrap/SKILL.md` の「並列 Claude 安全運用」「完遂責任 cohort audit」節
